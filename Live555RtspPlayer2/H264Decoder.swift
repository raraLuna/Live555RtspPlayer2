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
        guard status == noErr, let imageBuffer = imageBuffer else {
            print("디코딩 된 이미지 버퍼 없음")
            return
        }
        let pixelBuffer = imageBuffer as CVPixelBuffer
        print("디코딩 완료 - CVPixelBuffer 얻음 \(pixelBuffer)")
    }
    
    // H.264 NAL Unit 처리 함수
    func decode(nalData: Data) {
        let nalType = nalData[0] & 0x1F // NAL Unit Type 추출
        print("NAL Type: \(nalType)")
        
        switch nalType {
        case 7: // SPS (Sequence Parameter Set)
            print("Received SPS")
            self.sps = nalData
        case 8: // PPS (Picture Parameter Set)
            print("Received PPS")
            self.pps = nalData
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
    
    private func setupDecoder(sps: Data, pps: Data) {
        guard self.formatDescription == nil else {
            return
        }
        
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            (sps as NSData).bytes.bindMemory(to: UInt8.self, capacity: sps.count),
            (pps as NSData).bytes.bindMemory(to: UInt8.self, capacity: pps.count)
        ]
        let parameterSetSize: [Int] = [sps.count, pps.count]
        
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSize,
            nalUnitHeaderLength: 4, // 4바이트 NAL 헤더 사용
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription = formatDescription else {
            print("CMVideoFormatDescription Create Failed: \(status)")
            return
        }
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        let attributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: 1920,
            kCVPixelBufferHeightKey: 1080
        ]
        
        let statusSession = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &decompressionSession
        )
        
        if statusSession != noErr {
            print("VTDecompreesionSession Create Failed: \(statusSession)")
        } else {
            print("VTDecompresionSession Create Success")
        }
    }
    
    // 비디오 프레임 디코딩 함수
    private func decodeFrame(nalData: Data) {
        guard let decompressionSession = self.decompressionSession,
              let formatDescription = self.formatDescription else {
            print("디코딩 세션이 설정되지 않음")
            return
        }
        
        var blockBuffer: CMBlockBuffer?
        let nalDataWithStartCode = Data([0x00, 0x00, 0x00, 0x01]) + nalData // start code 추가함
        
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
    }
}
