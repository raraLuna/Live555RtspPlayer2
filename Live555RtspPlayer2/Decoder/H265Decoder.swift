//
//  H265Decoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/10/25.
//

import Foundation
import AVFoundation
import VideoToolbox

struct H265Frame {
    let poc: Int
    let dts: CMTime
    var pts: CMTime
    let nalUnit: Data
}

struct VideoFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTimeStamp: CMTime
}

protocol H265DecoderDelegate: AnyObject {
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer)
}

// I‑frames are the least compressible but don't require other video frames to decode.
// P‑frames can use data from previous frames to decompress and are more compressible than I‑frames.
// B‑frames can use both previous and forward frames for data reference to get the highest amount of data compression.

// H265는 프레임의 재생 순서가 도착 순서와 일치하지 않음 -> sort 해야한다. 무엇을 기준으로??? timestamp???
// A - B - C - D 순서로 도착햇으나, 재생 순서는 B - C - D - A 임.

class H265Decoder {
    public static var defaultDecodeFlags: VTDecodeFrameFlags = [
        ._EnableAsynchronousDecompression,
        ._EnableTemporalProcessing
    ]
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var vps: Data?
    private var sps: Data?
    private var pps: Data?
    
    private var frameIndex = 0
    private var isDecoderInitialized = false
    
    private let videoQueue: ThreadSafeQueue<(data: Data, rtpTimestamp: UInt32, nalType: UInt8)>
    weak var delegate: H265DecoderDelegate?
    let calculator = H265POCCalculator()
    
    private var isDecoding = false
    private var flagIn: VTDecodeFrameFlags {
        H265Decoder.defaultDecodeFlags
    }
    
    private var frames: [VideoFrame] = []
    private let frameQueue = ThreadSafeQueue<(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime)>()
    
    private var rtpClockRate: Double = 90000.0
    private var baseRTPTimestamp: UInt32?
    private var baseCMTime: CMTime = .zero
    
    private var decodeBuffer: [(data: Data, dts: CMTime)] = []
    private var frameBuffer: [H265Frame] = []
    private var sampleBufferArray: [CMSampleBuffer] = []
    private var imageBuffer: [CVPixelBuffer] = []
    open var isBaseline: Bool = true
    
    private var lastPoc: Int = 0
    
    private let decompressionOutputCallback: VTDecompressionOutputCallback = { (
        decompressionOutputRefCon,
        sourceFrameRefCon,
        status,
        infoFlags,
        imageBuffer,
        presentationTimeStamp,
        duration
    ) in
        //print("decompressionOutputRefCon: \(String(describing: decompressionOutputRefCon))\nsourceFrameRefCon: \(String(describing: sourceFrameRefCon))\nstatus: \(status)\ninfoFlags: \(infoFlags)\nimageBuffer: \(String(describing: imageBuffer))\npresentationTimeStamp: \(presentationTimeStamp)\nduration: \(duration)")
        
        guard status == noErr, let imageBuffer = imageBuffer else {
            print("디코딩 오류: status = \(status), imageBuffer = \(String(describing: imageBuffer))")
            return
        }
        
        let pixelBuffer = imageBuffer as CVPixelBuffer
        //print("비디오 디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
        print("비디오 디코딩 완료 - CVPixelBuffer 얻음")
        print("비디오 디코딩 완료 presentationTimeStamp: \(presentationTimeStamp)")
        print("비디오 디코딩 완료 duration: \(duration)")
        //let dumpFilePath = "/Users/yumi/Documents/videoDump/decoded265_frame.yuv"
        //MakeDumpFile.dumpCVPixelBuffer(pixelBuffer, to: dumpFilePath)
        
        
        
        if let refCon = decompressionOutputRefCon {
            let decoder = Unmanaged<H265Decoder>.fromOpaque(refCon).takeUnretainedValue()
            let dumpFilePath = "/Users/yumi/Documents/videoDump/decoded265_frame\(decoder.frameIndex).yuv"
            MakeDumpFile.dumpCVPixelBuffer(pixelBuffer, to: dumpFilePath)
            //print("decoder.delegate: \(String(describing: decoder.delegate))")
            
            decoder.frameQueue.enqueueFrame(pixelBuffer: pixelBuffer, presentationTimeStamp: presentationTimeStamp)
            // I - B - B - B - P 순서로 프레임 재정렬 큐
            decoder.frameQueue.sortByPresentationTimeStamp()
            
//            if decoder.frameQueue.count() >= 5 {
//                if let pixelFrameBuffer = decoder.frameQueue.dequeueFrame()?.pixelBuffer {
//                    decoder.delegate?.didDecodeFrame(pixelFrameBuffer)
//                }
//            }
        }
            
            //decoder.delegate?.didDecodeFrame(pixelBuffer)
        
    }
    
    init(videoQueue: ThreadSafeQueue<(data: Data, rtpTimestamp: UInt32, nalType: UInt8)>) {
        self.videoQueue = videoQueue
    }
    
    deinit {
        invalidateSession()
    }
    
    func start() {
        isDecoding = true
        DispatchQueue.global(qos: .userInitiated).async {
            self.decode()
        }
    }
    
    func stop() {
        isDecoding = false
        invalidateSession()
        print("H265Decoder stopped and resources released.")
    }
    
    private func decode() {
        print("H265Decoder class started. decode()")
        print("[Thread] decode h265 thread: \(Thread.current)")
        while isDecoding {
            if let (nalData, rtpTimestamp, nalType) = self.videoQueue.dequeuePacket() {
                if !isDecoderInitialized {
                    let vpsInfo = videoDecodingInfo.vps
                    let spsInfo = videoDecodingInfo.sps
                    let ppsInfo = videoDecodingInfo.pps
                    self.setupDecoder(vps: vpsInfo, sps: spsInfo, pps: ppsInfo)
                    isDecoderInitialized = true
                }
                
                let dts = convertRTPTimestampToCMTime(rtpTimestamp)
                var pts = CMTime()
                
                // [start code] + [nal header 2 bytes] + [payload (rbsp)]
                let spsData = videoDecodingInfo.sps
                //print("spsDATA[0]: \(spsData[0])")
                let rbspSPS = extractRBSP(from: spsData)
                print("rbspSPS: \(rbspSPS)")
                print("rbspSPS hex: \(rbspSPS.hexString)")
                
                // log2_max_pic_order_cnt_lsb
                guard let spsInfoParsing = H265SPSParser.parse(rbsp: rbspSPS) else { return }
                print("spsInfoParsing: \(spsInfoParsing)") // 0~15
                
                guard let picOrderCntLsb = H265SliceHeaderParser.parse(data: nalData, log2MaxPicOrderCntLsb: spsInfoParsing.log2MaxPicOrderCntLsb) else { return }
                print("picOrderCntLsb: \(picOrderCntLsb.picOrderCntLsb), nalType: \(nalType)")
                
                
                var poc = calculator.calculatePOC(currentPocLsb: picOrderCntLsb.picOrderCntLsb, log2MaxPicOrderCntLsb: spsInfoParsing.log2MaxPicOrderCntLsb, nalType: Int(nalType), lastPoc: lastPoc)
                self.lastPoc = poc
                
                
                print("calculated poc: \(poc) ; nalType: \(nalType) ; frameIndex: \(frameIndex)")
                if nalType == 1 {
                    // 1 - 0 - 0 - 0 순서로 디코딩, but 재생할 때는 0 - 0 - 0 - 1 순서로 재생해주기 위함
                    poc += 14
                }
                if nalType == 6 {
                    // nalType 6은 원래 SEI 이나, 현재 예제로 사용 중인 영상에서 19 - 6 - 6- 6으로 오는 프레임이 있는데 이때 6이 B프레임인 것으로 보임
                    // 1 -0- 0-0과 같이 디코딩 순서는 19 -6 -6-6이지만 재생 순서는 6 - 6 -6- 19가 맞다.
                    // 이 것을 맞춰주기 위한 하드코딩 부분임. 예제 영상이 달라지면 (서버에서 보내는 영상이 달라지면) 이 부분 수정이 필요하다.
                    /// nalType 6은 SEI 로 디코딩의 보조 정보를 담은 데이터일 뿐 실제 프레임이 아닌 경우가 많은데, 인코딩의 설정에 따라 6임에도 실제 프레임일 수 있음. 지금이 그런 경우로 보인다. 
                    poc -= 1
                }
                
                print("calculated2 poc: \(poc) ; nalType: \(nalType) ; frameIndex: \(frameIndex)")
                pts = CMTime(value: CMTimeValue(poc), timescale: 90000)
                
                
                print("dts: \(dts), \npts: \(pts)")
                print("poc: \(poc), naltype: \(nalType)")
                let frame = H265Frame(poc: poc, dts: dts, pts: pts, nalUnit: nalData)
                decodeFrame(framedata: frame)
                } else {
                    usleep(10_000)
                }
            }
        }
     
    private func extractRBSP(from data: Data) -> Data {
        let nalHeaderSize = 2
        guard data.count > nalHeaderSize else {
            return Data()
        }
        
        let payload = Data(data.dropFirst(nalHeaderSize))
        //print("payload[0]: \(payload[0])")
        //print("payload hexString: \(payload.hexString)")
        return convertToRBSP(payload)
    }
    
    private func convertToRBSP(_ data: Data) -> Data {
        var rbsp = Data()
        var i = 0
        while i < data.count {
            //print("i: \(i)")
            //print("data.count: \(data.count)")
            //print("data[\(i)]: \(data[i])")
            if i + 2 < data.count {
                if data[i] == 0x00 && data[i+1] == 0x00 && data[i+2] == 0x03 {
                    rbsp.append(contentsOf: [data[i], data[i+1]])
                    i += 3
                } else {
                    rbsp.append(data[i])
                    i += 1
                }
            } else {
                rbsp.append(data[i])
                i += 1
            }

        }
        return rbsp
    }
    
    private func convertRTPTimestampToCMTime(_ rtpTimestamp: UInt32) -> CMTime {
        if baseRTPTimestamp == nil {
            baseRTPTimestamp = rtpTimestamp
            baseCMTime = CMTime(value: 0, timescale: Int32(rtpClockRate))
            return baseCMTime
        }
        
        print("convertRTPTimestampToCMTime\(frameIndex) rtpTimestamp: \(rtpTimestamp), baseRTPTimestamp: \(baseRTPTimestamp)")
        //let diff = UInt32(bitPattern: rtpTimestamp &- baseRTPTimestamp!)
        let diff = rtpTimestamp &- baseRTPTimestamp!
        let dts = CMTime(value: Int64(diff), timescale: 90000)
        let seconds = Double(diff) / rtpClockRate
        print("convertRTPTimestampToCMTime\(frameIndex) diff: \(diff), seconds: \(seconds)")
        return CMTime(seconds: seconds, preferredTimescale: Int32(rtpClockRate))
    }
    
    private func setupDecoder(vps: Data, sps: Data, pps: Data) {
        guard self.formatDescription == nil else { return }
        
        let nalUnitHeaderLength: Int32 = 4
        let status = vps.withUnsafeBytes { (vpsBuffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let vpsBaseAddress = vpsBuffer.baseAddress else {
                return kCMFormatDescriptionBridgeError_InvalidParameter
            }
            return sps.withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> OSStatus in
                guard let spsBaseAddress = spsBuffer.baseAddress else {
                    return kCMFormatDescriptionBridgeError_InvalidParameter
                }
                return pps.withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> OSStatus in
                    guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                        return kCMFormatDescriptionBridgeError_InvalidParameter
                    }
                    let pointers: [UnsafePointer<UInt8>] = [
                        vpsBaseAddress.assumingMemoryBound(to: UInt8.self),
                        spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                        ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                    ]
                    let sizes: [Int] = [vpsBuffer.count, spsBuffer.count, ppsBuffer.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: nalUnitHeaderLength,
                        extensions: nil,
                        formatDescriptionOut: &formatDescription)
                }
            }
        }
        guard status == noErr, let formatDescription = formatDescription else {
            print("CMVideoFormatDescription Create Failed: \(status)")
            return
        }
        
        print("CMVideoFormatDescription 생성 성공 \(status)")
        //print("formatDescription: \(String(describing: formatDescription))")
        
        var outputCallback = VTDecompressionOutputCallbackRecord()
        outputCallback.decompressionOutputCallback = nil
        
        outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let decoderParameters = NSMutableDictionary()
        let attributes: [NSString: AnyObject] = [
            //kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ]
        
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        
        let statusSession = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &decompressionSession
        )
        
        if decompressionSession == nil {
            print("decompressionSession이 생성되지 않았습니다.")
        } else {
            //print("decompressionSession 생성 완료: \(String(describing: decompressionSession))")
            if let session = decompressionSession {
                VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            }
        }
        
        if statusSession != noErr {
            print("VTDecompressionSession 생성 실패: \(statusSession)")
        } else {
            //print("VTDecompressionSession 생성 성공 \(statusSession)")
        }
        
    }
    
        //private func decodeFrame(framedata : H265Frame) {
    private func decodeFrame(framedata : H265Frame) {
        guard let decompressionSession = self.decompressionSession,
              let formatDescription = self.formatDescription else {
            print("decompressionSession이 설정되지 않음")
            return
        }
        
        let nalData = framedata.nalUnit
        var blockBuffer: CMBlockBuffer?
        print("nalData count: \(nalData.count)")
        
        var nalSize = CFSwapInt32HostToBig(UInt32(nalData.count - 4))
        var lengthBytes = [UInt8](repeating: 0, count: 8)
        memcpy(&lengthBytes, &nalSize, 4)
        let nalDataWithLengthPrefix = Data(bytes: &nalSize, count: 4) + nalData[4...]
        
        let statusBB = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: UnsafeMutableRawPointer(mutating: (nalDataWithLengthPrefix as NSData).bytes),
            blockLength: nalDataWithLengthPrefix.count,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalDataWithLengthPrefix.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard statusBB == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            print("CMBlockBuffer 생성 실패: \(statusBB), \(String(describing: blockBuffer))")
            return
        }
        //print("CMBlockBuffer 생성 성공: \(statusBB), \(String(describing: blockBuffer))")
        //print("CMBlockBuffer dataLength : \(blockBuffer.dataLength)")
        
        var sampleTimingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: framedata.pts,
            decodeTimeStamp: framedata.dts
        )
        print("sampleTimingInfo: \(sampleTimingInfo)")
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [nalDataWithLengthPrefix.count]
        
        let statusSB = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTimingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer)
        guard statusSB == noErr, let sampleBuffer = sampleBuffer else {
            print("CMSampleBuffer 생성 실패: \(statusSB), \(String(describing: sampleBuffer))")
            return
        }
        //print("CMSampleBuffer 생성 성공: \(statusSB), \(String(describing: sampleBuffer))")
        //print("CMSampleBuffer totalSampleSize : \(sampleBuffer.totalSampleSize)")
        
        //let pts = sampleBuffer.presentationTimeStamp
        //print("")
        
        var flagOut: VTDecodeInfoFlags = []
        let statusDecode = VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: flagIn,
            frameRefcon: nil,
            infoFlagsOut: &flagOut
        )
        
        if statusDecode != noErr {
            print("decoding error: \(statusDecode)")
        }
        
        frameIndex += 1
    }
    
    
//    private func outFrameForSession(_ status: OSStatus, infoFlags: VTDecodeInfoFlags, imageBuffer: CVImageBuffer?, presentationTimestamp: CMTime, duration: CMTime) {
//        guard let imageBuffer: CVPixelBuffer = imageBuffer, status == noErr else {
//            print("failed to get imageBuffer or status is not noErr")
//            return
//        }
//        
//        var timingInfo = CMSampleTimingInfo(
//            duration: duration,
//            presentationTimeStamp: presentationTimestamp,
//            decodeTimeStamp: CMTime.invalid
//        )
//        
//        var videoFormatDescription: CMVideoFormatDescription?
//        var status = CMVideoFormatDescriptionCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: imageBuffer,
//            formatDescriptionOut: &videoFormatDescription
//        )
//        guard status == noErr else {
//            print("failed to create CMVideoFormatDescriptionCreateForImageBuffer")
//            return
//        }
//        
//        var sampleBuffer: CMSampleBuffer?
//        status = CMSampleBufferCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: imageBuffer,
//            dataReady: true,
//            makeDataReadyCallback: nil,
//            refcon: nil,
//            formatDescription: videoFormatDescription!,
//            sampleTiming: &timingInfo,
//            sampleBufferOut: &sampleBuffer
//        )
//        guard status == noErr else {
//            print("failed to create CMSampleBufferCreateForImageBuffer")
//            return
//        }
//        
//        guard let buffer: CMSampleBuffer = sampleBuffer else {
//            return
//        }
//        
//        self.sampleBufferArray.append(buffer)
//        self.sampleBufferArray.sort {
//            $0.presentationTimeStamp < $1.presentationTimeStamp
//        }
//        
//    }
    
    func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
    }
    
    func insertFrame(poc: Int, dts: CMTime, pts: CMTime, nalUnit: Data) {
        let frame = H265Frame(poc: poc, dts: dts, pts: pts, nalUnit: nalUnit)
        frameBuffer.append(frame)
    }

    func sortAndGetReadyFrames() -> [H265Frame] {
        // sort: 제자리 정렬. 배열 자체를 변경함
        // sorted: 새롭게 정렬한 배열을 return. 원본 배열은변하지 않음.
        // DTS 기준으로 정렬해서 디코딩 순서대로 처리
            frameBuffer.sort { $0.dts < $1.dts }

            // B/P 프레임이 있을 수 있으므로 일정 수 이상 모였을 때만 출력
            guard frameBuffer.count >= 1 else { return [] }

            // PTS 기준으로 정렬해 재생 순서를 맞춤
            let outputFrames = frameBuffer.sorted { $0.pts < $1.pts }

            // 이미 출력된 프레임은 제거
            frameBuffer.removeAll()

            return outputFrames

        
        
//        // POC 순으로 정렬 (화면 재생 순서)
//        let sortedByPOC = frameBuffer.sorted { $0.pts < $1.pts }
//
//        // DTS 기준 정렬 → 실제 디코딩 순서
//        let sortedByDTS = frameBuffer.sorted { $0.dts < $1.dts }
//
//        var outputFrames: [H265Frame] = []
//        for (i, var frame) in sortedByPOC.enumerated() {
//            // PTS를 재생 순서대로 설정 (DTS 기준 인덱스 i 사용)
//            if i < sortedByDTS.count {
//                frame.pts = sortedByDTS[i].pts
//            }
//            outputFrames.append(frame)
//        }
//
//        frameBuffer.removeAll()
//        return sortedByDTS
    }

    func getFrameQueue() -> ThreadSafeQueue<(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime)> {
        return frameQueue
    }

}
