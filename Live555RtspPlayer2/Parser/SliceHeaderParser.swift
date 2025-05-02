//
//  SliceHeaderParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/15/25.
//

import Foundation

struct H265SliceHeader {
    var firstSliceSegmentInPicFlag: Bool
    var noOutputOfPriorPicsFlag: Bool?
    var slicePicParameterSetId: UInt
    var dependentSliceSegmentFlag: Bool?
    var sliceSegmentAddress: UInt
    var sliceType: UInt
    var picOutputFlag: Bool?
    var colourPlaneId: UInt?
    var slicePicOrderCntLsb: UInt
    var shortTermRefPicSetSpsFlag: Bool
    // RPS 관련 필드 생략 없이 추가 가능
    var shortTermRefPicSetIdx: UInt?
    // 다른 slice_header 필드
    var sliceSaoLumaFlag: Bool?
    var sliceSaoChromaFlag: Bool?
    var numRefIdxActiveOverrideFlag: Bool?
    
    //참고 프레임 인덱스 수에 따라 예측 방향을 유추
    var numRefIdxL0ActiveMinus1: UInt? // 과거 프레임 (P 예측)
    var numRefIdxL1ActiveMinus1: UInt? // 미래 프레임 (B 예측 포함)
    
    var mvdL1ZeroFlag: Bool?
    var cabacInitFlag: Bool?
    var collocatedFromL0Flag: Bool?
    var collocatedRefIdx: UInt?
    var fiveMinusMaxNumMergeCand: UInt?
    var sliceQpDelta: Int
    var sliceCbQpOffset: Int?
    var sliceCrQpOffset: Int?
    var deblockingFilterOverrideFlag: Bool?
    var sliceDeblockingFilterDisabledFlag: Bool?
    var sliceBetaOffsetDiv2: Int?
    var sliceTcOffsetDiv2: Int?
    var sliceLoopFilterAcrossSlicesEnabledFlag: Bool?
}

class SliceHeaderParser {
    func parseH265SliceHeader(reader: BitReader, sps: H265SPS, pps: H265PPS, nalType: UInt8) -> H265SliceHeader {
        
        // --- 1. first_slice_segment_in_pic_flag (1 bit)
        let firstSliceSegmentInPicFlag = reader.readFlag()
        print("[parseH265SliceHeader] firstSliceSegmentInPicFlag: \(firstSliceSegmentInPicFlag)")
        
        // --- 2. no_output_of_prior_pics_flag (1 bit) (if IDR or BLA)
        var noOutputOfPriorPicsFlag: Bool? = nil
        //if sps.maxSubLayersMinus1 > 0 {
        if nalType == 19 || nalType == 20 {
            noOutputOfPriorPicsFlag = reader.readFlag()
        }
        //print("[parseH265SliceHeader] sps.maxSubLayersMinus1: \(sps.maxSubLayersMinus1)")
        print("[parseH265SliceHeader] noOutputOfPriorPicsFlag: \(noOutputOfPriorPicsFlag)")
        
        // --- 3. slice_pic_parameter_set_id (UE)
        let slicePicParameterSetId = reader.readUE()
        print("[parseH265SliceHeader] slicePicParameterSetId: \(slicePicParameterSetId)")

        // --- 4. dependent_slice_segment_flag (1 bit, if not first slice segment)
        var dependentSliceSegmentFlag: Bool? = nil
        if !firstSliceSegmentInPicFlag && pps.dependentSliceSegmentsEnabledFlag {
            dependentSliceSegmentFlag = reader.readFlag()
        }
        //print("[parseH265SliceHeader] pps.dependentSliceSegmentsEnabledFlag: \(pps.dependentSliceSegmentsEnabledFlag)")
        print("[parseH265SliceHeader] dependentSliceSegmentFlag: \(dependentSliceSegmentFlag)")

        // --- 5. slice_segment_address (variable length)
        //let sliceSegmentAddress = reader.readBits(Int(sps.ctbLog2SizeY + 1)) // may vary depending on picture size
        ///H265는 한 프레임(한 장의 이미지)를 여러개의 CTU로 나눈다
        ///프레임은 CTU 블록들의 그리드처럼 구성되어있다.
        ///CTU 1개 =기본 인코딩 단의
        ///sliceSegmentAddress는 이 슬라이스가 몇번째 CTU부터 시작하는지 나타냄
        ///즉, 프레임 내부 위치 정보
        ///이 값은 PTS, DTS에 사용하는 값이 아니다.
        let ctbSizeY = 1 << sps.ctbLog2SizeY
        let picWidthInCtbsY = (Int(sps.picWidthInLumaSamples) + ctbSizeY - 1) / ctbSizeY
        let picHeightInCtbsY = (Int(sps.picHeightInLumaSamples) + ctbSizeY - 1) / ctbSizeY
        //print("[parseH265SliceHeader] sps.picWidthInLumaSamples: \(sps.picWidthInLumaSamples)")
        //print("[parseH265SliceHeader] sps.picHeightInLumaSamples: \(sps.picHeightInLumaSamples)")
        let totalCtbs = picWidthInCtbsY * picHeightInCtbsY
        let bitsNeeds = Int(ceil(log2(Double(totalCtbs))))
        let sliceSegmentAddress = reader.readBits(bitsNeeds)
        //print("[parseH265SliceHeader] sps.ctbLog2SizeY: \(sps.ctbLog2SizeY)")
        //print("[parseH265SliceHeader] bitsNeeds: \(bitsNeeds)")
        print("[parseH265SliceHeader] sliceSegmentAddress: \(sliceSegmentAddress)")

        // --- 6. If dependent_slice_segment_flag == false, parse the rest
        // 6.1 slice_reserved_flags (pps.num_extra_slice_header_bits bits)
        for _ in 0..<pps.numExtraSliceHeaderBits {
            _ = reader.readFlag() // discard
        }
        //print("[parseH265SliceHeader] pps.numExtraSliceHeaderBits: \(pps.numExtraSliceHeaderBits)")

        // 6.2 slice_type (UE)
        let sliceType = reader.readUE()
        print("[parseH265SliceHeader] sliceType: \(sliceType)")
        
        // 6.3 pic_output_flag (1 bit, if sps.separate_colour_plane_flag == false)
        var picOutputFlag: Bool? = nil
        if pps.outputFlagPresentFlag {
            picOutputFlag = reader.readFlag()
        }
        //print("[parseH265SliceHeader] sps.separateColourPlaneFlag: \(sps.separateColourPlaneFlag)")
        print("[parseH265SliceHeader] picOutputFlag: \(picOutputFlag)")

        // 6.4 colour_plane_id (2 bits, if sps.separate_colour_plane_flag == true)
        var colourPlaneId: UInt? = nil
        if sps.separateColourPlaneFlag {
            colourPlaneId = reader.readBits(2)
        }
        print("[parseH265SliceHeader] colourPlaneId: \(colourPlaneId)")

        // 6.5 slice_pic_order_cnt_lsb (sps.log2_max_pic_order_cnt_lsb_minus4 + 4 bits)
        let slicePicOrderCntLsb = reader.readBits(Int(sps.log2MaxPicOrderCntLsbMinus4 + 4))
        //print("[parseH265SliceHeader] sps.log2MaxPicOrderCntLsbMinus4 + 4: \(sps.log2MaxPicOrderCntLsbMinus4 + 4)")
        print("[parseH265SliceHeader] slicePicOrderCntLsb: \(slicePicOrderCntLsb), nalType: \(nalType), sliceSegmentAddress: \(sliceSegmentAddress), sliceType: \(sliceType)")

        // 6.6 short_term_ref_pic_set_sps_flag (1 bit)
        let shortTermRefPicSetSpsFlag = reader.readFlag()
        print("[parseH265SliceHeader] shortTermRefPicSetSpsFlag: \(shortTermRefPicSetSpsFlag)")
        
        // short_term_ref_pic_set_idx (UE)
        var shortTermRefPicSetIdx: UInt? = nil
        if shortTermRefPicSetSpsFlag {
            shortTermRefPicSetIdx = reader.readUE()
        } else {
            // RPS 정보 직접 파싱 필요
            // short_term_ref_pic_set (custom parsing)
        }
        print("[parseH265SliceHeader] shortTermRefPicSetIdx: \(shortTermRefPicSetIdx)")

        // 6.7 long_term_ref_pics_present_flag (if sps.long_term_ref_pics_present_flag == true)?
        //print("[parseH265SliceHeader] sps.longTermRefPicsPresentFlag: \(sps.longTermRefPicsPresentFlag)")
        
        // 6.8 slice_sao_luma_flag, slice_sao_chroma_flag (if sao_enabled)
        var sliceSaoLumaFlag: Bool? = nil
        var sliceSaoChromaFlag: Bool? = nil
        if sps.sampleAdaptiveOffsetEnabledFlag {
            sliceSaoLumaFlag = reader.readFlag()
            sliceSaoChromaFlag = reader.readFlag()
        }
        //print("[parseH265SliceHeader] sps.sampleAdaptiveOffsetEnabledFlag: \(sps.sampleAdaptiveOffsetEnabledFlag)")
        print("[parseH265SliceHeader] sliceSaoLumaFlag: \(sliceSaoLumaFlag)")
        print("[parseH265SliceHeader] sliceSaoChromaFlag: \(sliceSaoChromaFlag)")

        // 6.9 num_ref_idx_active_override_flag (1 bit)
        var numRefIdxActiveOverrideFlag: Bool? = nil
        var numRefIdxL0ActiveMinus1: UInt? = nil
        var numRefIdxL1ActiveMinus1: UInt? = nil
        numRefIdxActiveOverrideFlag = reader.readFlag()
        if numRefIdxActiveOverrideFlag == true {
            // num_ref_idx_l0_active_minus1 (UE)
            numRefIdxL0ActiveMinus1 = reader.readUE()
            numRefIdxL1ActiveMinus1 = reader.readUE()
        }
        print("[parseH265SliceHeader] numRefIdxActiveOverrideFlag: \(numRefIdxActiveOverrideFlag)")
        print("[parseH265SliceHeader] numRefIdxL0ActiveMinus1: \(numRefIdxL0ActiveMinus1)")
        print("[parseH265SliceHeader] numRefIdxL1ActiveMinus1: \(numRefIdxL1ActiveMinus1)")

        // 6.10 mvd_l1_zero_flag (if B-slice)
        var mvdL1ZeroFlag: Bool? = nil
        if sliceType == 1 {
            mvdL1ZeroFlag = reader.readFlag()
        }
        print("[parseH265SliceHeader] mvdL1ZeroFlag: \(mvdL1ZeroFlag)")
        
        // 6.11 cabac_init_flag (optional if pps.cabac_init_present_flag)
        var cabacInitFlag: Bool? = nil
        if pps.cabacInitPresentFlag {
            cabacInitFlag = reader.readFlag()
        }
        print("[parseH265SliceHeader] cabacInitFlag: \(cabacInitFlag)")
        
        // 6.12 collocated_from_l0_flag, collocated_ref_idx
        var collocatedFromL0Flag: Bool? = nil
        var collocatedRefIdx: UInt? = nil
        if sliceType == 1 || sliceType == 2 {
            collocatedFromL0Flag = reader.readFlag()
            collocatedRefIdx = reader.readUE()
        }
        print("[parseH265SliceHeader] collocatedFromL0Flag: \(collocatedFromL0Flag)")
        print("[parseH265SliceHeader] collocatedRefIdx: \(collocatedRefIdx)")

        // 6.13 five_minus_max_num_merge_cand (UE)
        let fiveMinusMaxNumMergeCand = reader.readUE()
        print("[parseH265SliceHeader] fiveMinusMaxNumMergeCand: \(fiveMinusMaxNumMergeCand)")
        
        // 6.14 slice_qp_delta (SE)
        let sliceQpDelta = reader.readSE()
        print("[parseH265SliceHeader] sliceQpDelta: \(sliceQpDelta)")

        // 6.15 slice_cb_qp_offset / slice_cr_qp_offset (optional if pps.pic_slice_level_chroma_qp_offsets_present_flag)
        var sliceCbQpOffset: Int? = nil
        var sliceCrQpOffset: Int? = nil
        if pps.ppsSliceChromaQpOffsetsPresentFlag {
            sliceCbQpOffset = reader.readSE()
            sliceCrQpOffset = reader.readSE()
        }
        //print("[parseH265SliceHeader] pps.ppsSliceChromaQpOffsetsPresentFlag: \(pps.ppsSliceChromaQpOffsetsPresentFlag)")
        print("[parseH265SliceHeader] sliceCbQpOffset: \(sliceCbQpOffset)")
        print("[parseH265SliceHeader] sliceCrQpOffset: \(sliceCrQpOffset)")
        
        // 6.15 slice_cb_qp_offset / slice_cr_qp_offset (optional if pps.pic_slice_level_chroma_qp_offsets_present_flag)
        var deblockingFilterOverrideFlag: Bool? = nil
        var sliceDeblockingFilterDisabledFlag: Bool? = nil
        var sliceBetaOffsetDiv2: Int? = nil
        var sliceTcOffsetDiv2: Int? = nil
        if pps.deblockingFilterControlPresentFlag {
            deblockingFilterOverrideFlag = reader.readFlag()
            if deblockingFilterOverrideFlag == true {
                sliceDeblockingFilterDisabledFlag = reader.readFlag()
                if sliceDeblockingFilterDisabledFlag == false {
                    sliceBetaOffsetDiv2 = reader.readSE()
                    sliceTcOffsetDiv2 = reader.readSE()
                }
            }
        }
        //print("[parseH265SliceHeader] pps.deblockingFilterControlPresentFlag: \(pps.deblockingFilterControlPresentFlag)")
        print("[parseH265SliceHeader] deblockingFilterOverrideFlag: \(deblockingFilterOverrideFlag)")
        print("[parseH265SliceHeader] sliceDeblockingFilterDisabledFlag: \(sliceDeblockingFilterDisabledFlag)")
        print("[parseH265SliceHeader] sliceBetaOffsetDiv2: \(sliceBetaOffsetDiv2)")
        print("[parseH265SliceHeader] sliceTcOffsetDiv2: \(sliceTcOffsetDiv2)")

        // 6.17 slice_loop_filter_across_slices_enabled_flag
        var sliceLoopFilterAcrossSlicesEnabledFlag: Bool? = nil
        if pps.ppsLoopFilterAcrossSlicesEnabledFlag {
            sliceLoopFilterAcrossSlicesEnabledFlag = reader.readFlag()
        }
        print("[parseH265SliceHeader] pps.ppsLoopFilterAcrossSlicesEnabledFlag: \(pps.ppsLoopFilterAcrossSlicesEnabledFlag)")
        print("[parseH265SliceHeader] sliceLoopFilterAcrossSlicesEnabledFlag: \(sliceLoopFilterAcrossSlicesEnabledFlag)")
        print("[parseH265SliceHeader] =============================================================================")

        return H265SliceHeader(
            firstSliceSegmentInPicFlag: firstSliceSegmentInPicFlag,
            noOutputOfPriorPicsFlag: noOutputOfPriorPicsFlag,
            slicePicParameterSetId: slicePicParameterSetId,
            dependentSliceSegmentFlag: dependentSliceSegmentFlag,
            sliceSegmentAddress: sliceSegmentAddress,
            sliceType: sliceType,
            picOutputFlag: picOutputFlag,
            colourPlaneId: colourPlaneId,
            slicePicOrderCntLsb: slicePicOrderCntLsb,
            shortTermRefPicSetSpsFlag: shortTermRefPicSetSpsFlag,
            shortTermRefPicSetIdx: shortTermRefPicSetIdx,
            sliceSaoLumaFlag: sliceSaoLumaFlag,
            sliceSaoChromaFlag: sliceSaoChromaFlag,
            numRefIdxActiveOverrideFlag: numRefIdxActiveOverrideFlag,
            numRefIdxL0ActiveMinus1: numRefIdxL0ActiveMinus1,
            numRefIdxL1ActiveMinus1: numRefIdxL1ActiveMinus1,
            mvdL1ZeroFlag: mvdL1ZeroFlag,
            cabacInitFlag: cabacInitFlag,
            collocatedFromL0Flag: collocatedFromL0Flag,
            collocatedRefIdx: collocatedRefIdx,
            fiveMinusMaxNumMergeCand: fiveMinusMaxNumMergeCand,
            sliceQpDelta: sliceQpDelta,
            sliceCbQpOffset: sliceCbQpOffset,
            sliceCrQpOffset: sliceCrQpOffset,
            deblockingFilterOverrideFlag: deblockingFilterOverrideFlag,
            sliceDeblockingFilterDisabledFlag: sliceDeblockingFilterDisabledFlag,
            sliceBetaOffsetDiv2: sliceBetaOffsetDiv2,
            sliceTcOffsetDiv2: sliceTcOffsetDiv2,
            sliceLoopFilterAcrossSlicesEnabledFlag: sliceLoopFilterAcrossSlicesEnabledFlag
        )
    }

}
/*
struct H265SPS {
    var videoParameterSetId: Int
    var maxSubLayersMinus1: Int
    var temporalIdNestingFlag: Bool
    var seqParameterSetId: Int
    var chromaFormatIdc: Int
    var separateColourPlaneFlag: Bool
    var picWidthInLumaSamples: Int
    var picHeightInLumaSamples: Int
    var conformanceWindowFlag: Bool
    var bitDepthLumaMinus8: Int
    var bitDepthChromaMinus8: Int
    var log2MaxPicOrderCntLsbMinus4: Int
    var log2MinLumaCodingBlockSizeMinus3: Int = 0
    var log2DiffMaxMinLumaCodingBlockSize: Int = 0
    var ctbLog2SizeY: Int {
        return log2MinLumaCodingBlockSizeMinus3 + 3 + log2DiffMaxMinLumaCodingBlockSize
    }
}

struct H265PPS {
    var picParameterSetId: Int
    var seqParameterSetId: Int
    var dependentSliceSegmentsEnabledFlag: Bool
    var outputFlagPresentFlag: Bool
}

struct H265SliceHeader {
    var firstSliceSegmentInPicFlag: Bool
    var noOutputOfPriorPicsFlag: Bool?
    var slicePicParameterSetId: Int
    var sliceType: Int
    var picOrderCntLsb: Int
    var shortTermRefPicSetSpsFlag: Bool?
    // 필요에 따라 더 추가
}

struct Frame {
    let poc: Int
    let nalType: Int
    let data: Data
}

class H265SliceHeaderParser {
    /// NAL Unit (start code 포함)에서 Picture Order Count (POC)를 추출
    static func parse(data: Data, log2MaxPicOrderCntLsb: Int, nalType: Int) -> H265SliceHeader? {

        //print("\(nalUnitData.hexString)")
        // Start code (0x00000001) 제거 후 NAL Unit payload만 추출
        guard let startCodeRange = findStartCode(in: data) else { return nil }
        let nalPayload = data[startCodeRange.upperBound...]

        //print("parsePOC hex nalPayload: \(nalPayload.hexString)")
        // 3-byte escape 제거 → RBSP 변환
        let rbsp = convertToRBSP(Data(nalPayload))
        print("H265SliceHeaderParser nalType: \(nalType)")
        
        // BitReader를 이용한 parsing
        let reader = BitReader(rbsp)
        guard let firstSliceSegmentInPicFlag = reader.readFlag() else { return nil }

        var noOutputOfPriorPicsFlag: Bool?
        if nalType == 19 || nalType == 20 {
            noOutputOfPriorPicsFlag = reader.readFlag()
        }

        let slicePicParameterSetId = reader.readUE()
        
        var spsList: [Int: H265SPS] = [:]
        var ppsList: [Int: H265PPS] = [:]
        guard let pps = ppsList[Int(slicePicParameterSetId)],
              let sps = spsList[pps.seqParameterSetId] else { print("check here"); return nil }

        if !firstSliceSegmentInPicFlag && pps.dependentSliceSegmentsEnabledFlag {
            _ = reader.readBits(sps.ctbLog2SizeY - 1) // slice_segment_address
        }

        if !pps.dependentSliceSegmentsEnabledFlag || (pps.dependentSliceSegmentsEnabledFlag && reader.readFlag() == false) {
            // Independent slice segment, parse slice header
            _ = reader.readUE() // slice_type
            if pps.outputFlagPresentFlag {
                _ = reader.readFlag() // pic_output_flag
            }

            if sps.separateColourPlaneFlag {
                _ = reader.readBits(2) // colour_plane_id
            }

            let picOrderCntLsb = reader.readBits(sps.log2MaxPicOrderCntLsbMinus4 + 4)
            return H265SliceHeader(
                firstSliceSegmentInPicFlag: firstSliceSegmentInPicFlag,
                noOutputOfPriorPicsFlag: noOutputOfPriorPicsFlag,
                slicePicParameterSetId: Int(slicePicParameterSetId),
                sliceType: 0, // 임시
                picOrderCntLsb: Int(picOrderCntLsb)
            )
        }

        return nil
        
        
        
        
        
//
//        _ = reader.readBits(1) // first_slice_segment_in_pic_flag
//        
//        let dependentSliceFlag = reader.readBit()
//        print("H265SliceHeaderParser dependentSliceFlag: \(dependentSliceFlag)")
//        if dependentSliceFlag == 1 {
//            return nil // not handling dependent slices
//        }
//
//        _ = reader.readUE() // slice_segment_address
//        let sliceType = reader.readUE() // slice_type
//        print("H265SliceHeaderParser sliceType: \(sliceType)")
//        print("H265SliceHeaderParser -------------------------------------")
//        let picOrderCntLsb = Int(reader.readBits(log2MaxPicOrderCntLsb))
//
//        return H265SliceHeader(picOrderCntLsb: picOrderCntLsb)
        
        
        
        
        
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
    
    func parseH265SPS(rbsp: Data) -> H265SPS? {
        let reader = BitReader(rbsp)
        
        let videoParameterSetId = reader.readBits(4)
        let maxSubLayersMinus1 = reader.readBits(3)
        guard let temporalIdNestingFlag = reader.readFlag() else { return nil }
        parseProfileTierLevel(reader: reader, maxSubLayersMinus1: Int(maxSubLayersMinus1))
        let seqParameterSetId = reader.readUE()
        
        let chromaFormatIdc = reader.readUE()
        var separateColourPlaneFlag = false
        if chromaFormatIdc == 3 {
        guard let flag = reader.readFlag() else { return nil }
            separateColourPlaneFlag = flag
        }

        let picWidthInLumaSamples = reader.readUE()
        let picHeightInLumaSamples = reader.readUE()
        guard let conformanceWindowFlag = reader.readFlag() else { return nil }

        if conformanceWindowFlag {
            _ = reader.readUE() // conf_win_left_offset
            _ = reader.readUE() // conf_win_right_offset
            _ = reader.readUE() // conf_win_top_offset
            _ = reader.readUE() // conf_win_bottom_offset
        }

        let bitDepthLumaMinus8 = reader.readUE()
        let bitDepthChromaMinus8 = reader.readUE()
        let log2MaxPicOrderCntLsbMinus4 = reader.readUE()
        
        return H265SPS(
            videoParameterSetId: Int(videoParameterSetId),
            maxSubLayersMinus1: Int(maxSubLayersMinus1),
            temporalIdNestingFlag: temporalIdNestingFlag,
            seqParameterSetId: Int(seqParameterSetId),
            chromaFormatIdc: Int(chromaFormatIdc),
            separateColourPlaneFlag: separateColourPlaneFlag,
            picWidthInLumaSamples: Int(picWidthInLumaSamples),
            picHeightInLumaSamples: Int(picHeightInLumaSamples),
            conformanceWindowFlag: conformanceWindowFlag,
            bitDepthLumaMinus8: Int(bitDepthLumaMinus8),
            bitDepthChromaMinus8: Int(bitDepthChromaMinus8),
            log2MaxPicOrderCntLsbMinus4: Int(log2MaxPicOrderCntLsbMinus4)
        )
    }
    
    func parseH265PPS(rbsp: Data) -> H265PPS? {
        let reader = BitReader(rbsp)

        let picParameterSetId = reader.readUE()
        let seqParameterSetId = reader.readUE()
        guard let dependentSliceSegmentsEnabledFlag = reader.readFlag() else { return nil }
        guard let outputFlagPresentFlag = reader.readFlag() else { return nil }
        

        return H265PPS(
            picParameterSetId: Int(picParameterSetId),
            seqParameterSetId: Int(seqParameterSetId),
            dependentSliceSegmentsEnabledFlag: dependentSliceSegmentsEnabledFlag,
            outputFlagPresentFlag: outputFlagPresentFlag
        )
    }
    
    func parseProfileTierLevel(reader: BitReader, maxSubLayersMinus1: Int) -> Bool {
        // general_profile_space: u(2)
        // general_tier_flag: u(1)
        // general_profile_idc: u(5)
        _ = reader.readBits(2 + 1 + 5)

        // general_profile_compatibility_flag[32]: u(32)
        _ = reader.readBits(32)

        // general_progressive_source_flag, general_interlaced_source_flag,
        // general_non_packed_constraint_flag, general_frame_only_constraint_flag: u(4)
        _ = reader.readBits(4)

        // general_reserved_zero_44bits: u(44)
        _ = reader.readBits(44)
        
        // general_level_idc: u(8)
        _ = reader.readBits(8)

        // sub_layer_profile_present_flag[ maxSubLayersMinus1 ]
        var subLayerProfilePresentFlag: [Bool] = []
        var subLayerLevelPresentFlag: [Bool] = []
        for _ in 0..<maxSubLayersMinus1 {
        guard let profilePresent = reader.readFlag(),
              let levelPresent = reader.readFlag() else {
            return false
        }
            subLayerProfilePresentFlag.append(profilePresent)
            subLayerLevelPresentFlag.append(levelPresent)
        }

        // padding if maxSubLayersMinus1 < 8
        if maxSubLayersMinus1 > 0 {
            for _ in maxSubLayersMinus1..<8 {
                // reserved_zero_2bits
                _ = reader.readBits(2)
            }
        }

        // sub_layer_profile_* and sub_layer_level_idc (optional, based on flags)
        for i in 0..<maxSubLayersMinus1 {
            if subLayerProfilePresentFlag[i] {
                _ = reader.readBits(2 + 1 + 5 + 32 + 4 + 44)
                // sub_layer_profile_space (2), sub_layer_tier_flag (1),
                // sub_layer_profile_idc (5), sub_layer_profile_compatibility_flags (32),
                // sub_layer_progressive/interlaced/non_packed/frame_only (4),
                // sub_layer_reserved_zero_44bits (44)
            }
            if subLayerLevelPresentFlag[i] {
                _ = reader.readBits(8)// sub_layer_level_idc
            }
        }

        return true
    }
}

//final class H265SPSParser {
//    static func parse(rbsp: Data) -> H265SPS? {
//        let reader = BitReader(rbsp)
//
//        _ = reader.readBits(4) // sps_video_parameter_set_id
//        _ = reader.readBits(3) // sps_max_sub_layers_minus1
//        _ = reader.readBit()   // sps_temporal_id_nesting_flag
//
//        // skip profile_tier_level
//        skipProfileTierLevel(reader: reader)
//
//        _ = reader.readUE() // sps_seq_parameter_set_id
//        _ = reader.readUE() // chroma_format_idc
//        _ = reader.readUE() // pic_width_in_luma_samples
//        _ = reader.readUE() // pic_height_in_luma_samples
//
//        let conformanceWindowFlag = reader.readBit()
//        if conformanceWindowFlag == 1 {
//            _ = reader.readUE() // left offset
//            _ = reader.readUE() // right offset
//            _ = reader.readUE() // top offset
//            _ = reader.readUE() // bottom offset
//        }
//
//        _ = reader.readUE() // bit_depth_luma_minus8
//        _ = reader.readUE() // bit_depth_chroma_minus8
//        let log2MaxPicOrderCntLsb = Int(reader.readUE() + 4)
//
//        return H265SPS(log2MaxPicOrderCntLsb: log2MaxPicOrderCntLsb)
//    }
//
//    private static func skipProfileTierLevel(reader: BitReader) {
//        _ = reader.readBits(2) // general_profile_space + general_tier_flag
//        _ = reader.readBits(5) // general_profile_idc
//        _ = reader.readBits(32) // profile_compatibility_flag
//        _ = reader.readBits(48) // constraint_indicator_flags
//        _ = reader.readBits(8)  // general_level_idc
//
//        // sps_max_sub_layers_minus1 is 0 in most cases
//        let subLayerCount = 0
//        for _ in 0..<subLayerCount {
//            _ = reader.readBit() // sub_layer_profile_present_flag
//            _ = reader.readBit() // sub_layer_level_present_flag
//        }
//    }
//}
 
 
 */




final class H265POCCalculator {
    private var prevPicOrderCntLsb: Int = 0
    private var prevPocMsb: Int = 0

    func calculatePOC(currentPocLsb: Int, log2MaxPicOrderCntLsb: Int, nalType: Int, lastPoc: Int) -> Int {
        // nalType이 6(SEI)라면 이전 POC를 그대로 반환
        if nalType == 6 {
            return lastPoc
        }

        // log2MaxPicOrderCntLsb: sps에 들어있는 poc 정보
        let maxPicOrderCntLsb = 1 << log2MaxPicOrderCntLsb // wraparound 기준을 결정
        var pocMsb: Int

        print("calculatePOC nalType: \(nalType)")
        print("calculatePOC maxPicOrderCntLsb: \(maxPicOrderCntLsb)")
        print("calculatePOC currentPocLsb: \(currentPocLsb)")
        print("calculatePOC log2MaxPicOrderCntLsb: \(log2MaxPicOrderCntLsb)")
        print("calculatePOC prevPicOrderCntLsb: \(prevPicOrderCntLsb)")
        print("calculatePOC prevPocMsb: \(prevPocMsb)")
        print("calculatePOC -------------------------------")
        
        /// prevPicOrderCntLsb: 직전 프레임의 LSB(Least Significant Bits). 프레임의 순서를 나타내는 작은 부분 값. wrap-around의 판단에 사용
        /// 현재 프레임의 LSB와 비교하여 MSB를 어떻게 수정할 지 결정하는 기준이 된다.
        ///
        /// prevPocMsb: 직전 프레임의 MSB(Most Significant Bits). MSB는 wrap-around를 처리할 때 증가하거나 감소하는 큰 단위 값
        /// 현재 프레임의 최종 POC를 계산할 때 기본으로 삼을 값.
        ///
        /// currentPocLsb: 현재 프레임에서 읽은 LSB 값.
        /// Slice Header에 있는 pic_order_cnt_lsb 필드를 파싱하여 구한 값. 이 값을 기반으로 현재 POC_를 계산 함.
        ///
        /// log2MaxPicOrderCntLsb: SPS에서 정해진 log2_max_pic_order_cnt_lsb_minus4 + 4의 값 LSB의 wrap-around 주기 계산에 사용
        /// 최대 LSB 범위를 구해서 warp-around를 감지하는데 사용
        ///
        ///
        
        if (currentPocLsb < prevPicOrderCntLsb) &&
            ((prevPicOrderCntLsb - currentPocLsb) >= maxPicOrderCntLsb / 2) {
            // LSB가 직전에 비해 작아졌고, 그 차이가 절반 이상인 경우 wrap-around가 앞으로 넘어갔다고 판단 -> MSB 증가
            pocMsb = prevPocMsb + maxPicOrderCntLsb
        } else if (currentPocLsb > prevPicOrderCntLsb) &&
                    ((currentPocLsb - prevPicOrderCntLsb) > maxPicOrderCntLsb / 2) {
            // LSB가 직전에 비해 커졌고, 그 차이가 절반 이상인 경우 wrap-around가 뒤로 넘어감 ->MSB 감소
            pocMsb = prevPocMsb - maxPicOrderCntLsb
        } else {
            // 그 외의 경우 -> MSB 유지
            pocMsb = prevPocMsb
        }

        let poc = pocMsb + currentPocLsb
        prevPicOrderCntLsb = currentPocLsb
        prevPocMsb = pocMsb

        return poc
    }
}
