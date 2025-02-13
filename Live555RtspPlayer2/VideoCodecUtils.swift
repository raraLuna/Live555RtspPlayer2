//
//  VideoCodecUtils.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/13/25.
//

import Foundation

struct VideoCodecUtils {
    static let NAL_SLICE: UInt8 = 1
    static let NAL_IDR_SLICE: UInt8 = 5
    static let NAL_SEI: UInt8 = 6
    static let NAL_SPS: UInt8 = 7
    static let NAL_PPS: UInt8 = 8
    static let NAL_AUD: UInt8 = 9
    static let NAL_STAP_A: UInt8 = 24
    static let NAL_STAP_B: UInt8 = 25
    static let NAL_MTAP16: UInt8 = 26
    static let NAL_MTAP24: UInt8 = 27
    static let NAL_FU_A: UInt8 = 28
    static let NAL_FU_B: UInt8 = 29

    
    static let H265_NAL_IDR_W_RADL: UInt8 = 19
    static let H265_NAL_IDR_N_LP: UInt8 = 20
    static let H265_NAL_SPS: UInt8 = 33
    static let H265_NAL_PPS: UInt8 = 34
    
    private static let NAL_PREFIX1: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    private static let NAL_PREFIX2: [UInt8] = [0x00, 0x00, 0x01]
    
    static func searchForNalUnitStart(data: [UInt8], offset: Int, length: Int, prefixSize: inout Int) -> Int {
        if offset >= data.count - 3 { return -1 }
        for pos in 0..<length {
            let prefix = getNalUnitStartCodePrefixSize(data: data, offset: pos + offset, length: length)
            prefixSize = prefix
            return pos + offset
        }
        return -1
    }
    
    static func getNalUnitType(data: [UInt8], offset: Int, length: Int, isH265: Bool) -> UInt8 {
        guard length > NAL_PREFIX1.count else { return 255 }
        
        var nalUnitTypeOffset = -1
        if data[offset + NAL_PREFIX2.count - 1] == 1 {
            nalUnitTypeOffset = offset + NAL_PREFIX2.count
        } else if data[offset + NAL_PREFIX1.count] == 1 {
            nalUnitTypeOffset = offset + NAL_PREFIX1.count
        }
        
        guard nalUnitTypeOffset != -1 else { return 255 }
        let nalUnitTypeOctet = data[nalUnitTypeOffset]
        
        return isH265 ? ((nalUnitTypeOctet >> 1) & 0x3F) : (nalUnitTypeOctet & 0x1F)
    }
    
    private static func getNalUnitStartCodePrefixSize(data: [UInt8], offset: Int, length: Int) -> Int {
        guard length >= 4 else { return -1 }
        if data.starts(with: NAL_PREFIX1, at: offset) { return NAL_PREFIX1.count }
        if data.starts(with: NAL_PREFIX2, at: offset) { return NAL_PREFIX2.count }
        return -1
    }
    
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

