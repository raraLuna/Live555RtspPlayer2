//
//  VideoCodecUtils.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/13/25.
//

import Foundation

struct VideoCodecUtils {
    static let NAL_SLICE: UInt8 = 1     // 일반 P-Frame Slice
    static let NAL_IDR_SLICE: UInt8 = 5 // IDR 키 프레임 (I-Frame)
    static let NAL_SEI: UInt8 = 6       // 보조 정보(SEI)
    static let NAL_SPS: UInt8 = 7       // 시퀀스 파라미터 세트 (SPS)
    static let NAL_PPS: UInt8 = 8       // 픽쳐 파라미터 세트 (PPS)
    static let NAL_AUD: UInt8 = 9       // 액세스 유닛 구분자 (AUD)
    static let NAL_STAP_A: UInt8 = 24
    static let NAL_STAP_B: UInt8 = 25
    static let NAL_MTAP16: UInt8 = 26
    static let NAL_MTAP24: UInt8 = 27
    static let NAL_FU_A: UInt8 = 28
    static let NAL_FU_B: UInt8 = 29

    
    static let H265_NAL_IDR_W_RADL: UInt8 = 19  // IDR 키 프레임
    static let H265_NAL_IDR_N_LP: UInt8 = 20    // 비실시간 IDR 키 프레임
    static let H265_NAL_SPS: UInt8 = 33         // SPS
    static let H265_NAL_PPS: UInt8 = 34         // PPS
    
    private static let NAL_PREFIX1: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    private static let NAL_PREFIX2: [UInt8] = [0x00, 0x00, 0x01]
    
    // NAL Unit의 시작 지점을 찾음
    // offset부터 length 바이트 내에서 NAL Unit 시작 코드(0x00000001 또는 0x000001)를 탐색
    // prefixSize에 NAL 시작 코드 길이 (3 또는 4)를 저장
    static func searchForNalUnitStart(data: [UInt8], offset: Int, length: Int, prefixSize: inout Int) -> Int {
        if offset >= data.count - 3 { return -1 }
        for pos in 0..<length {
            let prefix = getNalUnitStartCodePrefixSize(data: data, offset: pos + offset, length: length)
            prefixSize = prefix
            return pos + offset
        }
        return -1
    }
    
    // NAL Unit의 타입을 분석
    static func getNalUnitType(data: [UInt8], offset: Int, length: Int, isH265: Bool) -> UInt8 {
        guard length > NAL_PREFIX1.count else { return 255 }
        
        var nalUnitTypeOffset = -1
        if data[offset + NAL_PREFIX2.count - 1] == 1 {
            nalUnitTypeOffset = offset + NAL_PREFIX2.count
        } else if data[offset + NAL_PREFIX1.count - 1] == 1 {
            nalUnitTypeOffset = offset + NAL_PREFIX1.count
        }
        print("nalUnitTypeOffset: \(nalUnitTypeOffset)")
        guard nalUnitTypeOffset != -1 else { return 255 }
        let nalUnitTypeOctet = data[nalUnitTypeOffset]
        print("nalUnitTypeOctet: \(nalUnitTypeOctet)")
        
        return isH265 ? ((nalUnitTypeOctet >> 1) & 0x3F) : (nalUnitTypeOctet & 0x1F)
    }
    
    // NAL Unit 시작 코드 길이 확인
    private static func getNalUnitStartCodePrefixSize(data: [UInt8], offset: Int, length: Int) -> Int {
        guard length >= 4 else { return -1 }
        if data.starts(with: NAL_PREFIX1, at: offset) { return NAL_PREFIX1.count }
        if data.starts(with: NAL_PREFIX2, at: offset) { return NAL_PREFIX2.count }
        return -1
    }
    
    // NAL Unit이 키 프레임인지 판별
    // H.265: H265_NAL_IDR_W_RADL 또는 H265_NAL_IDR_N_LP → 키 프레임
    // H.264: NAL_IDR_SLICE이면 키 프레임
    static func isAnyKeyFrame(data: [UInt8], offset: Int, length: Int, isH265: Bool) -> Bool {
        guard length > 0 else { return false }
        
        var currOffset = offset
        var prefixSize = 0
        var startTime = Date().timeIntervalSince1970
        
        while true {
            let nalUnitIndex = searchForNalUnitStart(data: data, offset: currOffset, length: length, prefixSize: &prefixSize)
            
            if nalUnitIndex >= 0 {
                let nalUnitOffset = nalUnitIndex + prefixSize
                let nalUnitTypeOctet = data[nalUnitOffset]
                
                if isH265 {
                    let nalUnitType = (nalUnitTypeOctet & 0x7E) >> 1
                    if nalUnitType == H265_NAL_IDR_W_RADL || nalUnitType == H265_NAL_IDR_N_LP {
                        return true
                    }
                } else {
                    let nalUnitType = nalUnitTypeOctet & 0x1F
                    if nalUnitType == NAL_IDR_SLICE { return true }
                    if nalUnitType == NAL_SLICE { return false }
                }
                
                currOffset = nalUnitOffset
                
                if Date().timeIntervalSince1970 - startTime > 0.1 {
                    print("Cannot process data within 100 msec in %d bytes", length)
                    break
                }
            } else {
                break
            }
        }
        return false
    }
}

private extension Array where Element == UInt8 {
    func starts(with prefix: [UInt8], at offset: Int) -> Bool {
        guard self.count >= offset + prefix.count else { return false }
        return self[offset..<offset + prefix.count].elementsEqual(prefix)
    }
}

