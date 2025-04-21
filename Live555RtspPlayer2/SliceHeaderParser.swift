//
//  SliceHeaderParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/15/25.
//

import Foundation

struct H265SPS {
    let log2MaxPicOrderCntLsb: Int
}

struct H265SliceHeader {
    let picOrderCntLsb: Int
}

struct Frame {
    let poc: Int
    let nalType: Int
    let data: Data
}

class H265SliceHeaderParser {
    /// NAL Unit (start code 포함)에서 Picture Order Count (POC)를 추출
    static func parse(data: Data, log2MaxPicOrderCntLsb: Int) -> H265SliceHeader? {

        //print("\(nalUnitData.hexString)")
        // Start code (0x00000001) 제거 후 NAL Unit payload만 추출
        guard let startCodeRange = findStartCode(in: data) else { return nil }
        let nalPayload = data[startCodeRange.upperBound...]

        //print("parsePOC hex nalPayload: \(nalPayload.hexString)")
        // 3-byte escape 제거 → RBSP 변환
        let rbsp = convertToRBSP(Data(nalPayload))

        // BitReader를 이용한 parsing
        let reader = BitReader(rbsp)
        _ = reader.readBits(1) // first_slice_segment_in_pic_flag
        
        let dependentSliceFlag = reader.readBit()
        if dependentSliceFlag == 1 {
            return nil // not handling dependent slices
        }

        _ = reader.readUE() // slice_segment_address
        _ = reader.readUE() // slice_type
        let picOrderCntLsb = Int(reader.readBits(log2MaxPicOrderCntLsb))

        return H265SliceHeader(picOrderCntLsb: picOrderCntLsb)
        
        
        /*
        // 1. NAL Unit header: 2 bytes → 이미 처리됐으므로 skip
        bitReader.skipBits(16)

        // 2. slice_type parsing 위한 slice_segment_header
        _ = bitReader.readUE() // first_slice_segment_in_pic_flag
        let nalUnitType = (rbsp[0] >> 1) & 0x3F
        let isIdr = (nalUnitType >= 16 && nalUnitType <= 21)
        
        let nalUnitData = rbsp[0..<15]
        print("TEST LOG: \(nalUnitType)  \(nalUnitData.hexString)")

        if !isIdr {
            // slice_pic_order_cnt_lsb only present in non-IDR frames
            //_ = bitReader.readUE() // slice_type 등 skip 필요에 따라 추가
            let pic_order_cnt_lsb = bitReader.readBits(10) // 일반적으로 16비트 사용
            print("NALType: \(nalUnitType), isIDR: \(isIdr), parsed POC: \(pic_order_cnt_lsb)")

            return Int(pic_order_cnt_lsb)
        } else {
            print("NALType: \(nalUnitType), isIDR: \(isIdr)")
            return 0 // IDR은 POC = 0 으로 고정
        }
         */
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
    /// Raw Byte Sequence Payload : 실제 비디오의 유효 데이터
    /// start code 0001 외에 내부 데이터로 0001 이 존재하는 경우 인코더는 이를 start code와 구분하기 위해
    /// 3번째 바이트에 0x03을 삽입하여 start code와 내부 데이터 코드 사이에 구별이 있도록 함.
    /// 이때 추가한 0x03은 무의미한 데이터이므로 디코딩 전에 제거해줘야함.
    static func convertToRBSP(_ data: Data) -> Data {
        var rbsp = Data()
        var i = 0
        while i < data.count {
            //print("i: \(i)")
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
}

final class H265SPSParser {
    static func parse(rbsp: Data) -> H265SPS? {
        let reader = BitReader(rbsp)

        _ = reader.readBits(4) // sps_video_parameter_set_id
        _ = reader.readBits(3) // sps_max_sub_layers_minus1
        _ = reader.readBit()   // sps_temporal_id_nesting_flag

        // skip profile_tier_level
        skipProfileTierLevel(reader: reader)

        _ = reader.readUE() // sps_seq_parameter_set_id
        _ = reader.readUE() // chroma_format_idc
        _ = reader.readUE() // pic_width_in_luma_samples
        _ = reader.readUE() // pic_height_in_luma_samples

        let conformanceWindowFlag = reader.readBit()
        if conformanceWindowFlag == 1 {
            _ = reader.readUE() // left offset
            _ = reader.readUE() // right offset
            _ = reader.readUE() // top offset
            _ = reader.readUE() // bottom offset
        }

        _ = reader.readUE() // bit_depth_luma_minus8
        _ = reader.readUE() // bit_depth_chroma_minus8
        let log2MaxPicOrderCntLsb = Int(reader.readUE() + 4)

        return H265SPS(log2MaxPicOrderCntLsb: log2MaxPicOrderCntLsb)
    }

    private static func skipProfileTierLevel(reader: BitReader) {
        _ = reader.readBits(2) // general_profile_space + general_tier_flag
        _ = reader.readBits(5) // general_profile_idc
        _ = reader.readBits(32) // profile_compatibility_flag
        _ = reader.readBits(48) // constraint_indicator_flags
        _ = reader.readBits(8)  // general_level_idc

        // sps_max_sub_layers_minus1 is 0 in most cases
        let subLayerCount = 0
        for _ in 0..<subLayerCount {
            _ = reader.readBit() // sub_layer_profile_present_flag
            _ = reader.readBit() // sub_layer_level_present_flag
        }
    }
}

final class H265POCCalculator {
    private var prevPicOrderCntLsb: Int = 0
    private var prevPocMsb: Int = 0

    func calculatePOC(currentPocLsb: Int, log2MaxPicOrderCntLsb: Int) -> Int {
        let maxPicOrderCntLsb = 1 << log2MaxPicOrderCntLsb
        var pocMsb: Int

        if (currentPocLsb < prevPicOrderCntLsb) &&
            ((prevPicOrderCntLsb - currentPocLsb) >= maxPicOrderCntLsb / 2) {
            pocMsb = prevPocMsb + maxPicOrderCntLsb
        } else if (currentPocLsb > prevPicOrderCntLsb) &&
                    ((currentPocLsb - prevPicOrderCntLsb) > maxPicOrderCntLsb / 2) {
            pocMsb = prevPocMsb - maxPicOrderCntLsb
        } else {
            pocMsb = prevPocMsb
        }

        let poc = pocMsb + currentPocLsb
        prevPicOrderCntLsb = currentPocLsb
        prevPocMsb = pocMsb

        return poc
    }
}

extension Data {
    var hexString: String {
        self.map { String(format: "%02X", $0) }.joined()
    }
}

final class FrameSorter {
    private var bufferedFrames: [Frame] = []
    private let pocCalculator: H265POCCalculator
    private let log2MaxPicOrderCntLsb: Int

    init(log2MaxPicOrderCntLsb: Int) {
        self.pocCalculator = H265POCCalculator()
        self.log2MaxPicOrderCntLsb = log2MaxPicOrderCntLsb
    }

    func push(picOrderCntLsb: Int, nalType: Int, data: Data) -> [Frame] {
        //let poc = pocCalculator.calculatePOC(currentPocLsb: picOrderCntLsb.picOrderCntLsb, log2MaxPicOrderCntLsb: log2MaxPicOrderCntLsb)
        let frame = Frame(poc: picOrderCntLsb, nalType: nalType, data: data)
        
        bufferedFrames.append(frame)

        // IDR (nalType 19): GOP 새로 시작
        if nalType == 19 {
            let output = flushBufferedFrames()
            return output
        }
        
        // P-frame (nalType 0): B-frame과 함께 출력할 타이밍
        if nalType == 0 {
            let output = flushBufferedFrames()
            return output
        }

        // B-frame (nalType 1): 일단 쌓기
        return []
    }

    private func flushBufferedFrames() -> [Frame] {
        let sorted = bufferedFrames.sorted { $0.poc < $1.poc }
        bufferedFrames.removeAll()
        return sorted
    }

    func flushRemaining() -> [Frame] {
        return flushBufferedFrames()
    }
}
