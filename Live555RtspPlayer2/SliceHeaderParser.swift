//
//  SliceHeaderParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/15/25.
//

import Foundation

class H265SliceHeaderParser {
    /// NAL Unit (start code 포함)에서 Picture Order Count (POC)를 추출
    static func parsePOC(from nalUnit: Data) -> Int? {
        // Start code (0x00000001) 제거 후 NAL Unit payload만 추출
        guard let startCodeRange = findStartCode(in: nalUnit) else { return nil }
        let nalPayload = nalUnit[startCodeRange.upperBound...]

        // 3-byte escape 제거 → RBSP 변환
        let rbsp = convertToRBSP(Data(nalPayload))

        // BitReader를 이용한 parsing
        let bitReader = BitReader(rbsp)

        // 1. NAL Unit header: 2 bytes → 이미 처리됐으므로 skip
        bitReader.skipBits(16)

        // 2. slice_type parsing 위한 slice_segment_header
        _ = bitReader.readUE() // first_slice_segment_in_pic_flag
        let nalUnitType = (rbsp[0] >> 1) & 0x3F
        let isIdr = (nalUnitType >= 16 && nalUnitType <= 21)

        if !isIdr {
            // slice_pic_order_cnt_lsb only present in non-IDR frames
            _ = bitReader.readUE() // slice_type 등 skip 필요에 따라 추가
            let pic_order_cnt_lsb = bitReader.readBits(16) // 일반적으로 16비트 사용
            return Int(pic_order_cnt_lsb)
        } else {
            return 0 // IDR은 POC = 0 으로 고정
        }
    }

    /// Start code (0x00000001 or 0x000001) 위치를 찾아 범위 반환
    private static func findStartCode(in data: Data) -> Range<Data.Index>? {
        for i in 0..<data.count - 3 {
            if data[i] == 0x00 && data[i+1] == 0x00 {
                if data[i+2] == 0x01 {
                    return i..<(i+3)
                } else if i + 3 < data.count && data[i+2] == 0x00 && data[i+3] == 0x01 {
                    return i..<(i+4)
                }
            }
        }
        return nil
    }

    /// Emulation Prevention Byte (0x03) 제거하여 RBSP 반환
    private static func convertToRBSP(_ data: Data) -> Data {
        var rbsp = Data()
        var i = 0
        while i < data.count {
            if i + 2 < data.count &&
               data[i] == 0x00 && data[i+1] == 0x00 && data[i+2] == 0x03 {
                rbsp.append(contentsOf: [data[i], data[i+1]])
                i += 3
            } else {
                rbsp.append(data[i])
                i += 1
            }
        }
        return rbsp
    }
}
