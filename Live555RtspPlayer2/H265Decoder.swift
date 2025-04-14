//
//  H265Decoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/10/25.
//

import Foundation
import AVFoundation
import VideoToolbox

protocol H265DecoderDelegate: AnyObject {
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer)
}

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
    private var lastPTS = CMTime(value: 0, timescale: 30000)
    private var isDecoderInitialized = false
    
    private let videoQueue: ThreadSafeQueue<Data>
    weak var delegate: H265DecoderDelegate?
    
    private var isDecoding = false
    private var flagIn: VTDecodeFrameFlags {
        H265Decoder.defaultDecodeFlags
    }
    
    private let decompressionOutputCallback: VTDecompressionOutputCallback = { (
        decompressionOutputRefCon,
        sourceFrameRefCon,
        status,
        infoFlags,
        imageBuffer,
        presentationTimeStamp,
        duration
    ) in
        print("decompressionOutputRefCon: \(String(describing: decompressionOutputRefCon))\nsourceFrameRefCon: \(String(describing: sourceFrameRefCon))\nstatus: \(status)\ninfoFlags: \(infoFlags)\nimageBuffer: \(String(describing: imageBuffer))\npresentationTimeStamp: \(presentationTimeStamp)\nduration: \(duration)")
        
        guard status == noErr, let imageBuffer = imageBuffer else {
            print("디코딩 오류: status = \(status), imageBuffer = \(String(describing: imageBuffer))")
            return
        }
        let pixelBuffer = imageBuffer as CVPixelBuffer
        print("비디오 디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
        
//        let dumpFilePath = "/Users/yumi/Documents/videoDump/decoded265_frame.yuv"
//        MakeDumpFile.dumpCVPixelBuffer(pixelBuffer, to: dumpFilePath)
        
        if let refCon = decompressionOutputRefCon {
            let decoder = Unmanaged<H265Decoder>.fromOpaque(refCon).takeUnretainedValue()
            print("decoder.delegate: \(String(describing: decoder.delegate))")
            decoder.delegate?.didDecodeFrame(pixelBuffer)
        }
    }
    
    init(videoQueue: ThreadSafeQueue<Data>) {
        self.videoQueue = videoQueue
    }
    
    deinit {
        invalidateSession()
    }
    
    func start() {
        isDecoding = true
        DispatchQueue.global(qos: .userInteractive).async {
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
            if let videoData = self.videoQueue.dequeue() {
                if !isDecoderInitialized {
                    let vpsInfo = videoDecodingInfo.vps
                    let spsInfo = videoDecodingInfo.sps
                    let ppsInfo = videoDecodingInfo.pps
                    self.setupDecoder(vps: vpsInfo, sps: spsInfo, pps: ppsInfo)
                    isDecoderInitialized = true
                }
                
                if isDecoderInitialized {
                    decodeFrame(nalData: videoData)
                }
            } else {
                usleep(10_000)
            }
        }
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
        print("formatDescription: \(String(describing: formatDescription))")
        
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
            print("decompressionSession 생성 완료: \(String(describing: decompressionSession))")
            if let session = decompressionSession {
                VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            }
        }
        
        if statusSession != noErr {
            print("VTDecompressionSession 생성 실패: \(statusSession)")
        } else {
            print("VTDecompressionSession 생성 성공 \(statusSession)")
        }
        
    }
    
    private func decodeFrame(nalData: Data) {
        guard let decompressionSession = self.decompressionSession,
              let formatDescription = self.formatDescription else {
            print("decompressionSession이 설정되지 않음")
            return
        }
        
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
        print("CMBlockBuffer 생성 성공: \(statusBB), \(String(describing: blockBuffer))")
        print("CMBlockBuffer dataLength : \(blockBuffer.dataLength)")
        
        
        var sampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1001, timescale: 30000),
            presentationTimeStamp: getCorrectPTS(for: frameIndex),
            decodeTimeStamp: CMTime.invalid
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
        print("CMSampleBuffer 생성 성공: \(statusSB), \(String(describing: sampleBuffer))")
        print("CMSampleBuffer totalSampleSize : \(sampleBuffer.totalSampleSize)")
        
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
    
    func getCorrectPTS(for frameIndex: Int) -> CMTime {
        let newPTS = CMTime(value: Int64(frameIndex * 1001), timescale: 30000)
        if newPTS > lastPTS {
            lastPTS = newPTS
            return newPTS
        } else {
            return lastPTS + CMTime(value: 1001, timescale: 30000)
        }
    }
    
    func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
    }

}
