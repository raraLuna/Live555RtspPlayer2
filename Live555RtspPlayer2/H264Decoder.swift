//
//  H264Decoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/12/25.
//

import Foundation
import VideoToolbox
import CoreVideo

class H264Decoder {
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    
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
            // -8969: kVTInvalidSessionErr 세션이 유효하지 않음
            // -12911: kVTVideoDecoderBadDataErr 잘못된 데이터
            // -12909: kVTParameterErr 잘못된 파라미터
            // -12633: kVTInvalidImageBufferErr 이미지 버퍼가 유효하지 않음
            
            return
        }
        let pixelBuffer = imageBuffer as CVPixelBuffer
        print("디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
    }
    
    // H.264 NAL Unit 처리 함수
    func decode(nalData: Data) {
        print("NAL Data (첫 16바이트): \(nalData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
        let nalType = nalData[4] & 0x1F // NAL Unit Type 추출
        print("nalData[0]: \(nalData[0])")
        print("NAL Type: \(nalType)")
        
        switch nalType {
        case 7: // SPS (Sequence Parameter Set)
            print("Received SPS")
            self.sps = nalData[4...]
        case 8: // PPS (Picture Parameter Set)
            print("Received PPS")
            self.pps = nalData[4...]
        case 5, 1: // I-Frame (IDR) 또는 P-Freme
            print("Received Frame (I/P)")
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
    
    // Decompression: 감압.
    // VTDecompressionSession 생성
    private func setupDecoder(sps: Data, pps: Data) {
        // 중복 초기화 방지 (formatDescription이 이미 설정되어 있는 경우 함수 종료)
        guard self.formatDescription == nil else {
            return
        }
        
        // SPS, PPS 데이터를 UnsafePointer<UInt8>로 변환하여 사용
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            (sps as NSData).bytes.bindMemory(to: UInt8.self, capacity: sps.count),
            (pps as NSData).bytes.bindMemory(to: UInt8.self, capacity: pps.count)
        ]
        let parameterSetSize: [Int] = [sps.count, pps.count]
        
        // H.264의 SPS, PPS 데이터를 사용하여 CMFormatDescriptionRef 생성
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSize,
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
        
        // 디코딩 완료 시 호출될 콜백 설정 (decompressionOutputCallback)
        // decompressionOutputRefCon: 객체의 참고를 UnsafeMutableRawPointer 로 변환하여 전달
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        // 디코딩 된 이미지 속 버퍼 속성 설정
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: YUV 4:2:0 format
        let attributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: formatDescription.dimensions.width,
            kCVPixelBufferHeightKey: formatDescription.dimensions.height
        ]
        print("attributes as CFDictionary: \(attributes as CFDictionary)")
        
        // VTDecompressionSession 생성
        let statusSession = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &decompressionSession
        )
        
        if decompressionSession == nil {
            print("디코딩 세션이 생성되지 않았습니다.")
        } else {
            print("디코딩 세션 생성 완료: \(String(describing: decompressionSession))")
        }
        
        if statusSession != noErr {
            print("VTDecompreesionSession 생성 실패: \(statusSession)")
        } else {
            print("VTDecompresionSession 생성 성공 \(statusSession)")
        }
    }
    
    // NAL Unit 데이터를 VTDecompressionSession을 이용해 디코딩
    private func decodeFrame(nalData: Data) {
        // 세션이 존재하는지 확인
        guard let decompressionSession = self.decompressionSession,
              let formatDescription = self.formatDescription else {
            print("디코딩 세션이 설정되지 않음")
            return
        }
        
        var blockBuffer: CMBlockBuffer?
        //let nalDataWithStartCode = Data([0x00, 0x00, 0x00, 0x01]) + nalData // start code 추가함
        let nalDataWithStartCode = nalData
        
        // NAL data를 CMBlockBuffer로 변환
        // memoryBlock: 원본 NAL Unit 데이터
        // blockBufferOut: 변환된 CMBlockBuffer
        let statusBB = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: UnsafeMutableRawPointer(mutating: (nalDataWithStartCode as NSData).bytes),
            blockLength: nalDataWithStartCode.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalDataWithStartCode.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard statusBB == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            print("CMBlockBuffer 생성 실패: \(statusBB)")
            return
        }
        print("CMBlockBuffer 생성 성공: \(statusBB)")
        
        // CMSammpleBuffer 생성(VTDecompressionSession에서 처리 가능하도록 변환)
        // dataBuffer: CMBlockBuffer(NAL Unit 포함)
        // sampleSizeArray: 샘플 크기 정보
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [nalDataWithStartCode.count]
        
        let statusSB = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        guard statusSB == noErr, let sampleBuffer = sampleBuffer else {
            print("CMSampleBuffer 생성 실패: \(statusSB)")
            return
        }
        print("CMSampleBuffer 생성 성공: \(statusSB)")
        
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
        print("decoding 성공 statusDecode : \(statusDecode)")
    }
}








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
