//
//  H264Decoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/12/25.
//

import Foundation
import AVFoundation
import VideoToolbox

protocol H264DecoderDelegate: AnyObject {
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer)
}

class H264Decoder {
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private var frameIndex = 0
    private var lastPTS = CMTime(value: 0, timescale: 30000)
    
    private let videoQueue: ThreadSafeQueue<Data>
    
    var delegate: H264DecoderDelegate?
    
    private var isDecoding = false
    private var decodeThread: Thread?
    
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
            print("디코딩 된 이미지 버퍼 없음")
            print("디코딩 오류: status = \(status), imageBuffer = \(String(describing: imageBuffer))")
            // -8969 : codecBadDataErr
            // -12902: kVTInvalidSessionErr 세션이 유효하지 않음
            // -12911: kVTVideoDecoderBadDataErr 잘못된 데이터
            // -12909: kVTParameterErr 잘못된 파라미터
            // -12633: kVTInvalidImageBufferErr 이미지 버퍼가 유효하지 않음
            if let refCon = decompressionOutputRefCon {
                let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
                //decoder.videoSemaphore.signal()  //디코딩 실패 시 다음 루프로 이동
                //print("H264Decoder decode Semaphore signal")
            }
            return
        }
        let pixelBuffer = imageBuffer as CVPixelBuffer
        print("비디오 디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
         
        if let refCon = decompressionOutputRefCon {
            let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
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
        VTDecompressionSessionInvalidate(self.decompressionSession!)
        self.decompressionSession = nil
        self.formatDescription = nil
        self.frameIndex = 0
        print("H264Decoder stopped and resources released.")
    }
    
    // H.264 NAL Unit 처리 함수
    func decode() {
        print("H264Decoder class started. decode()")
        //DispatchQueue.global(qos: .userInteractive).async {
            print("[Thread] devode h264 thread: \(Thread.current)")
            while isDecoding {
                if let videoData = self.videoQueue.dequeue() {
                    let spsInfo = videoDecodingInfo.sps
                    let ppsInfo = videoDecodingInfo.pps
                    self.setupDecoder(sps: spsInfo, pps: ppsInfo)
                    self.decodeFrame(nalData: videoData)
                } else {
                    usleep(10_000)
                }
            }
        //}
    }
    
    // Decompression: 감압. 압축 해제
    // VTDecompressionSession 생성
    private func setupDecoder(sps: Data, pps: Data) {
        // 중복 초기화 방지 (formatDescription이 이미 설정되어 있는 경우 함수 종료)
        guard self.formatDescription == nil else {
            return
        }
        let nalUnitHeaderLength: Int32 = 4
        let status = pps.withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                return kCMFormatDescriptionBridgeError_InvalidParameter
            }
            return sps.withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> OSStatus in
                guard let spsBaseAddress = spsBuffer.baseAddress else {
                    return kCMFormatDescriptionBridgeError_InvalidParameter
                }
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                    ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes: [Int] = [spsBuffer.count, ppsBuffer.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: nalUnitHeaderLength,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
        guard status == noErr, let formatDescription = formatDescription else {
            print("CMVideoFormatDescription Create Failed: \(status)")
            return
        }
        
        print("CMVideoFormatDescription 생성 성공 \(status)")
        print("formatDescription: \(String(describing: formatDescription))")

        // 콜백 초기화
        var outputCallback = VTDecompressionOutputCallbackRecord()
        outputCallback.decompressionOutputCallback = nil
        
        // 디코딩 완료 시 호출될 콜백 설정 (decompressionOutputCallback)
        // decompressionOutputRefCon: 객체의 참고를 UnsafeMutableRawPointer 로 변환하여 전달
        outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            //decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        let decoderParameters = NSMutableDictionary()
        
        // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : NV12
        let attributes: [NSString: AnyObject] = [
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ]
        
        // DecompressionSession 초기화
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        
        // VTDecompressionSession 생성
        // videoDecoderSpecification: The particular video decoder that must be used. Pass NULL to let VideoToolbox choose a decoder.
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
    
    // NAL Unit 데이터를 VTDecompressionSession을 이용해 디코딩
    private func decodeFrame(nalData: Data) {
        // 세션이 존재하는지 확인
        guard let decompressionSession = self.decompressionSession,
              let formatDescription = self.formatDescription else {
            print("decompressionSession이 설정되지 않음")
            return
        }
        
        //압축 해제 세션 무효화 함수
        //VTDecompressionSessionInvalidate(decompressionSession)
        
        var blockBuffer: CMBlockBuffer?
        print("nalData count: \(nalData.count)")
        
        var nalSize = CFSwapInt32HostToBig(UInt32(nalData.count - 4)) // NALU 길이를 4바이트로 변환
        var lengthBytes = [UInt8](repeating: 0, count: 8)
        memcpy(&lengthBytes, &nalSize, 4)
//        memcpy(&nalData, &nalSize, 4)
        var nalDataWithLengthPrefix = Data(bytes: &nalSize, count: 4) + nalData[4...]
        
        // NAL data를 CMBlockBuffer로 변환
        // memoryBlock: 원본 NAL Unit 데이터
        // blockBufferOut: 변환된 CMBlockBuffer
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
        
        // CMSammpleBuffer 생성(VTDecompressionSession에서 처리 가능하도록 변환)
        // dataBuffer: CMBlockBuffer(NAL Unit 포함)
        // sampleSizeArray: 샘플 크기 정보
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
            sampleBufferOut: &sampleBuffer
        )
        
        guard statusSB == noErr, let sampleBuffer = sampleBuffer else {
            print("CMSampleBuffer 생성 실패: \(statusSB), \(String(describing: sampleBuffer))")
            return
        }
        print("CMSampleBuffer 생성 성공: \(statusSB), \(String(describing: sampleBuffer))")
        print("CMSampleBuffer totalSampleSize : \(sampleBuffer.totalSampleSize)")
        
        // log에서 이 부분 수상함 >> outputPTS = {INVALID}(computed from PTS, duration and attachments)
        // CMSampleBuffer 생성 시 presentationTimeStamp를 설정하지 않으면 기본값이 INVALID로 설정됨 >>> sampleTimingArray: &sampleTimingInfo 설정
        // presentationTimeStamp: CMTime(value: 0, timescale: 0, flags: __C.CMTimeFlags(rawValue: 0), epoch: 0) : 잘못된 값
        // 정상적인 PTS 값 예시: CMTime(value: 1001, timescale: 30000) (30fps)

        
        // 비디오 프레임 디코딩
        let statusDecode = VTDecompressionSessionDecodeFrame(
            decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: nil
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
