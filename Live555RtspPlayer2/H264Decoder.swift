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
    
    weak var delegate: H264DecoderDelegate?
    
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
            
            return
        }
        let pixelBuffer = imageBuffer as CVPixelBuffer
        print("디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
        //let dumpFilePath = FileManager.default.temporaryDirectory.appendingPathComponent("decoded_frame.yuv").path()
        //MakeDumpFile.dumpCVPixelBuffer(pixelBuffer, to: dumpFilePath)
        //print("PixelBuffer 덤프 저장 경로: \(dumpFilePath)")
         
        if let refCon = decompressionOutputRefCon {
            let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
            decoder.delegate?.didDecodeFrame(pixelBuffer)
        }
    }
    
    // H.264 NAL Unit 처리 함수
    func decode(nalData: Data) {
        print("decode NAL Data (첫 32바이트): \(nalData.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " "))")
        let nalType = nalData[4] & 0x1F // NAL Unit Type 추출
        print("decode nalData: \(nalData[4])")
        print("decode NAL Type: \(nalType)")
        
        switch nalType {
        case 7: // SPS (Sequence Parameter Set)
            print("Received SPS")
            self.sps = nalData.dropFirst(4)
        case 8: // PPS (Picture Parameter Set)
            print("Received PPS")
            self.pps = nalData.dropFirst(4)
        case 5, 1: // I-Frame (IDR) 또는 P-Freme (첫 프레임은 5, 이후로는 1)
            print("Received Frame (I/P)")
            print("Frame Index: \(frameIndex)")
            guard let sps = sps, let pps = pps else {
                print("SPS/PPS 정보가 없습니다. 프레임을 디코딩 할 수 없습니다.")
                return
            }
            setupDecoder(sps: sps, pps: pps) // 디코더 설정
            decodeFrame(nalData: nalData) // 디코딩 수행
        default:
            print("Unsupported NAL Type: \(nalType)")
        }
        
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
        
        /*
         ====================================================================================
        // SPS, PPS 데이터를 UnsafePointer<UInt8>로 변환하여 사용
//        let parameterSetPointers: [UnsafePointer<UInt8>] = [
//            (sps as NSData).bytes.bindMemory(to: UInt8.self, capacity: sps.count),
//            (pps as NSData).bytes.bindMemory(to: UInt8.self, capacity: pps.count)
//        ]
//        let parameterSetSize: [Int] = [sps.count, pps.count]
        let spsPointer = sps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let ppsPointer = pps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        
        // H.264의 SPS, PPS 데이터를 사용하여 CMFormatDescriptionRef 생성
//        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
//            allocator: kCFAllocatorDefault,
//            parameterSetCount: 2,
//            parameterSetPointers: parameterSetPointers,
//            parameterSetSizes: parameterSetSize,
//            nalUnitHeaderLength: 4, // 4바이트 NAL 헤더 길이 (0x00 00 00 01)
//            formatDescriptionOut: &formatDescription
//        )
        
        // CMFormatDescription 생성
        // Creates a format description for a video media stream that the parameter set describes.
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: [spsPointer, ppsPointer],
            parameterSetSizes: [sps.count, pps.count],
            nalUnitHeaderLength: 4, // 4바이트 NAL 헤더 길이 (0x00 00 00 01)
            formatDescriptionOut: &formatDescription
        )
        
        // CMFormatDescription 생성 확인 (성공 시 formatDescription 저장)
        guard status == noErr, let formatDescription = formatDescription else {
            print("CMVideoFormatDescription Create Failed: \(status)")
            return
        }
        print("CMVideoFormatDescription 생성 성공 \(status)")
        print("formatDescription: \(formatDescription)")
         
         // formatDescription 에서 avcC 데이터 추출하여 확인 (이 데이터가 SPS/PPS와 동일하다면 제대로 생성된 것)
         // avcC의 구조:  01 [profile] [compatibility] [level] [flags] SPS_count SPS ... PPS_count PPS ...
         // SPS_count: 0xE1(1개), PPS_count: 0x01(1개), 이후 데이터로 SPS/PPS가 일치해야함
         if let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any],
            let atoms = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any],
            let avcCData = atoms["avcC"] as? Data {
             print("avcC Hex: \(avcCData.map { String(format: "%02X", $0) }.joined(separator: " "))")
         }
         
         // CMVideoFormatDescription 해상도 출력하여 SPS의 해상도와 일치하는지 확인
         let width = CMVideoFormatDescriptionGetDimensions(formatDescription).width
         let height = CMVideoFormatDescriptionGetDimensions(formatDescription).height
         print("디코딩 해상도: \(width)x\(height)")
         
         
         ====================================================================================
        */
        
        
    
        
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
        
        // 디코딩 된 이미지 속 버퍼 속성 설정
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: YUV 4:2:0 format
//        let attributes: [NSString: Any] = [
//            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
//            kCVPixelBufferWidthKey: formatDescription.dimensions.width,
//            kCVPixelBufferHeightKey: formatDescription.dimensions.height
//        ]
//        print("attributes as CFDictionary: \(attributes as CFDictionary)")
//        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange // NV12
        
//        let attributes: [NSString: Any] = [
//            kCVPixelBufferPixelFormatTypeKey : NSNumber(value: pixelFormat),
//            kCVPixelBufferIOSurfacePropertiesKey: [:] as  AnyObject,
//            kCVPixelBufferOpenGLESCompatibilityKey: NSNumber(booleanLiteral: true)
//        ]
        
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
        //let nalDataWithStartCode = Data([0x00, 0x00, 0x00, 0x01]) + nalData // start code 추가함
        //let nalDataWithStartCode = nalData
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
        //print("decoding 성공 statusDecode : \(statusDecode)")
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
}





//
//let statusDecode = decompressionSession.decodeFrame(
//    samplebuffer: sampleBuffer,
//    outputHandler: { status, flags, imageBuffer, timeStamp, duration in
//        if status == noErr, let imageBuffer = imageBuffer {
//            print("Decoded frame: \(imageBuffer)")
//        } else {
//            print("Decoding error: \(status)")
//        }
//    }
//)
//
//extension VTDecompressionSession {
//    func decodeFrame(
//        samplebuffer: CMSampleBuffer,
//        flags: VTDecodeFrameFlags = [],
//        outputHandler: @escaping VTDecompressionOutputHandler
//    ) -> OSStatus {
//        var infoFlags = VTDecodeInfoFlags.asynchronous
//        return VTDecompressionSessionDecodeFrame(
//            self, sampleBuffer: samplebuffer,
//            flags: flags,
//            infoFlagsOut: &infoFlags,
//            outputHandler: outputHandler
//        )
//    }
//}








//
//func createAVCHeader(sps: Data, pps: Data) -> Data? {
//    guard sps.count > 4, pps.count > 4 else {
//        print("SPS 또는 PPS 데이터가 너무 짧습니다. ")
//        return nil
//    }
//    
//    let spsBody = sps.dropFirst(4)
//    let ppsBody = pps.dropFirst(4)
//    
//    let spsBodyLen = spsBody.count
//    let ppsBodyLen = ppsBody.count
//    
//    let length = 8 + spsBodyLen + 1 + 2  + ppsBodyLen // 전체 버퍼 크기 계산
//    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
//    //defer { buf.deallocate() } // 메모리 해제
//    
//    var idx = 0
//    
//    buf[idx] = 0x01 // Version
//    idx += 1
//    
//    buf[idx] = sps[5] // Profile
//    idx += 1
//    
//    buf[idx] = sps[6] // Compatibility
//    idx += 1
//    
//    buf[idx] = sps[7] // Level
//    idx += 1
//    
//    buf[idx] = 0xFC | 3 // Reversed 6bit + NALU Length Size -1 (2bit)
//    idx += 1
//    
//    buf[idx] = 0xE0 | 1 // Reversed 3bit + SPS Count (1개)
//    idx += 1
//    
//    buf[idx] = UInt8((spsBodyLen & 0xFF00) >> 8) // SPS 길이 (상위 바이트)
//    idx += 1
//    
//    buf[idx] = UInt8(spsBodyLen & 0x00FF) // SPS 길이 (하위바이트)
//    idx += 1
//    
//    // SPS 데이터 복사
////        spsBody.withUnsafeBytes { rawBuffer in
////            buf.advanced(by: idx).update(from: rawBuffer.bindMemory(to: UInt8.self).baseAddress!, count: spsBodyLen)
////        }
////        idx += spsBodyLen
//    
//    // SPS 복사 (NAL 헤더 제거)
//    spsBody.withUnsafeBytes { rawBuffer in
//        let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
//        memcpy(buf + idx, base + 4, spsBodyLen) // 4바이트 NAL 헤더 제거
//    }
//    idx += spsBodyLen
//    
//    buf[idx] = 0x01 // PPS 개수 (1개)
//    idx += 1
//    
//    buf[idx] = UInt8((ppsBodyLen & 0xFF00) >> 8) // PPS 길이 (상위 바이트)
//    idx += 1
//    
//    buf[idx] = UInt8(ppsBodyLen & 0x00FF) // PPS 길이 (하위 바이트)
//    idx += 1
//    
//    // PPS 데이터 복사
////        ppsBody.withUnsafeBytes { rawBuffer in
////            buf.advanced(by: idx).update(from: rawBuffer.bindMemory(to: UInt8.self).baseAddress!, count: ppsBodyLen)
////        }
//    
//    // PPS 복사 (NAL 헤더 제거)
//    ppsBody.withUnsafeBytes { rawBuffer in
//        let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
//        memcpy(buf + idx, base + 4, ppsBodyLen) // 4바이트 NAL 헤더 제거
//    }
//    
//    // Data 객체 생성 (메모리 자동 해제 설정)
//    let avccData = Data(bytesNoCopy: buf, count: length, deallocator: .free)
//    
//    return avccData
//    
//}

//guard let avccData = self.createAVCHeader(sps: sps, pps: pps) else {
//    print("AVCC 헤더 생성 실패")
//    return
//}
//print("AVCC 헤더 생성 성공 : \(avccData as NSData)")
//
//// CFMutableDictionaryRef 생성
//let ext = NSMutableDictionary()
//ext["avcC"] = avccData
//
//// NSDictionary -> CFDicotionaryRef 변환
//let dictionary: [CFString: Any] = [
//    kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ext
//]
//
//// CMVideoFormatDescriptionCreate 호출하여 H.264 포맷 정보 포함하는 CMFormatDescriptionRef 생성
//// width, height는 sps, pps에 포함되어 있음
//// formatDesc는 이후 비디오 디코딩에 사용됨
//var formatDesc: CMFormatDescription?
//let status = CMVideoFormatDescriptionCreate(
//    allocator: nil,
//    codecType: kCMVideoCodecType_H264,
//    width: 1920,
//    height: 1080,
//    extensions: dictionary as CFDictionary,
//    formatDescriptionOut: &formatDesc
//)
//
//if status == noErr {
//    print("CMVideoFormatDescription 생성 성공")
//} else {
//    print("CMVideoFormatDescription 생성 실패: \(status)")
//}
