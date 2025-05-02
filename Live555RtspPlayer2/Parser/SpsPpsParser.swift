//
//  SpsPpsParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/24/25.
//

import Foundation

struct H265SPS {
    var videoParameterSetId: UInt
    var maxSubLayersMinus1: UInt
    var temporalIdNestingFlag: Bool

    // profile_tier_level
    var generalProfileSpace: UInt
    var generalTierFlag: Bool
    var generalProfileIdc: UInt
    var generalProfileCompatibilityFlags: UInt32
    var generalConstraintIndicatorFlags: UInt64
    var generalLevelIdc: UInt

    // sps_seq_parameter_set
    var spsSeqParameterSetId: UInt
    var chromaFormatIdc: UInt
    var separateColourPlaneFlag: Bool
    var picWidthInLumaSamples: UInt
    var picHeightInLumaSamples: UInt
    var conformanceWindowFlag: Bool
    var confWinLeftOffset: UInt
    var confWinRightOffset: UInt
    var confWinTopOffset: UInt
    var confWinBottomOffset: UInt

    var bitDepthLumaMinus8: UInt
    var bitDepthChromaMinus8: UInt
    var log2MaxPicOrderCntLsbMinus4: UInt
    var spsSubLayerOrderingInfoPresentFlag: Bool
    var maxDecPicBufferingMinus1: [UInt]
    var maxNumReorderPics: [UInt]
    var maxLatencyIncreasePlus1: [UInt]

    var log2MinLumaCodingBlockSizeMinus3: UInt
    var log2DiffMaxMinLumaCodingBlockSize: UInt
    var log2MinLumaTransformBlockSizeMinus2: UInt
    var log2DiffMaxMinLumaTransformBlockSize: UInt
    var maxTransformHierarchyDepthInter: UInt
    var maxTransformHierarchyDepthIntra: UInt

    var scalingListEnabledFlag: Bool
    var spsScalingListDataPresentFlag: Bool

    var ampEnabledFlag: Bool
    var sampleAdaptiveOffsetEnabledFlag: Bool
    var pcmEnabledFlag: Bool

    var numShortTermRefPicSets: UInt
    var longTermRefPicsPresentFlag: Bool
    var spsTemporalMvpEnabledFlag: Bool
    var strongIntraSmoothingEnabledFlag: Bool

    var vuiParametersPresentFlag: Bool
    var vuiParameters: H265VUIParameters?
    
    // Derived
    var ctbLog2SizeY: UInt {
        return log2MinLumaCodingBlockSizeMinus3 + 3 + log2DiffMaxMinLumaCodingBlockSize
    }

    // pic_order_cnt_type is always 0 in HEVC
    var picOrderCntType: Int { return 0 }
}

struct H265PPS {
    var ppsPicParameterSetId: UInt
    var ppsSeqParameterSetId: UInt
    var dependentSliceSegmentsEnabledFlag: Bool
    var outputFlagPresentFlag: Bool
    var numExtraSliceHeaderBits: UInt
    var signDataHidingEnabledFlag: Bool
    var cabacInitPresentFlag: Bool
    var numRefIdxL0DefaultActiveMinus1: UInt
    var numRefIdxL1DefaultActiveMinus1: UInt
    var initQpMinus26: Int
    var constrainedIntraPredFlag: Bool
    var transformSkipEnabledFlag: Bool
    var cuQpDeltaEnabledFlag: Bool
    var diffCuQpDeltaDepth: UInt
    var ppsCbQpOffset: Int
    var ppsCrQpOffset: Int
    var ppsSliceChromaQpOffsetsPresentFlag: Bool
    var weightedPredFlag: Bool
    var weightedBipredFlag: Bool
    var transquantBypassEnabledFlag: Bool
    var tilesEnabledFlag: Bool
    var entropyCodingSyncEnabledFlag: Bool
    var numTileColumnsMinus1: UInt
    var numTileRowsMinus1: UInt
    var loopFilterAcrossTilesEnabledFlag: Bool
    var ppsLoopFilterAcrossSlicesEnabledFlag: Bool
    var deblockingFilterControlPresentFlag: Bool
    var deblockingFilterOverrideEnabledFlag: Bool
    var ppsDeblockingFilterDisabledFlag: Bool
    var ppsScalingListDataPresentFlag: Bool
    var listsModificationPresentFlag: Bool
    var log2ParallelMergeLevelMinus2: UInt
    var sliceSegmentHeaderExtensionPresentFlag: Bool
}

struct H265VPS {
    var vpsVideoParameterSetId: UInt
    var vpsBaseLayerInternalFlag: Bool
    var vpsBaseLayerAvailableFlag: Bool
    var vpsMaxLayersMinus1: UInt
    var vpsMaxSubLayersMinus1: UInt
    var vpsTemporalIdNestingFlag: Bool

    // profile_tier_level (공통 구조이므로 reuse 가능)
    var profileTierLevel: H265ProfileTierLevel

    var vpsSubLayerOrderingInfoPresentFlag: Bool
    var maxDecPicBufferingMinus1: [UInt]
    var maxNumReorderPics: [UInt]
    var maxLatencyIncreasePlus1: [UInt]

    var vpsMaxLayerId: UInt
    var vpsNumLayerSetsMinus1: UInt
    var layerIdIncludedFlag: [[Bool]]

    var vpsTimingInfoPresentFlag: Bool
    var vpsNumUnitsInTick: UInt?
    var vpsTimeScale: UInt?
    var vpsPocProportionalToTimingFlag: Bool?
    var vpsNumTicksPocDiffOneMinus1: UInt?

    var vpsHrdParametersPresentFlag: Bool
    // hrd_parameters 생략 (필요시 추가 구현 가능)

    var vpsExtensionFlag: Bool
}


struct H265ProfileTierLevel {
    let generalProfileSpace: UInt
    let generalTierFlag: Bool
    let generalProfileIdc: UInt
    let generalProfileCompatibilityFlags: UInt32
    let generalConstraintIndicatorFlags: UInt64
    let generalLevelIdc: UInt
}

class SpsPpsParser {
    func parseSPS(reader: inout BitReader) -> H265SPS {
        let videoParameterSetId = reader.readBits(4)
        let maxSubLayersMinus1 = reader.readBits(3)
        let temporalIdNestingFlag = reader.readFlag()

        let profileTierLevel = parseProfileTierLevel(reader: reader, maxSubLayersMinus1: maxSubLayersMinus1)
        let generalProfileSpace = profileTierLevel.generalProfileSpace
        let generalTierFlag = profileTierLevel.generalTierFlag
        let generalProfileIdc = profileTierLevel.generalProfileIdc
        let generalProfileCompatibilityFlags = profileTierLevel.generalProfileCompatibilityFlags
        let generalConstraintIndicatorFlags = profileTierLevel.generalConstraintIndicatorFlags
        let generalLevelIdc = profileTierLevel.generalLevelIdc

//        // profile_tier_level
//        let generalProfileSpace = reader.readBits(2)
//        let generalTierFlag = reader.readFlag()
//        let generalProfileIdc = reader.readBits(5)
//        var generalProfileCompatibilityFlags: UInt32 = 0
//        for _ in 0..<4 {
//            generalProfileCompatibilityFlags = (generalProfileCompatibilityFlags << 8) | UInt32(reader.readBits(8))
//        }
//        var generalConstraintIndicatorFlags: UInt64 = 0
//        for _ in 0..<6 {
//            generalConstraintIndicatorFlags = (generalConstraintIndicatorFlags << 8) | UInt64(reader.readBits(8))
//        }
//        let generalLevelIdc = reader.readBits(8)

        let spsSeqParameterSetId = reader.readUE()
        let chromaFormatIdc = reader.readUE()
        let separateColourPlaneFlag = (chromaFormatIdc == 3) ? reader.readFlag() : false

        let picWidthInLumaSamples = reader.readUE()
        let picHeightInLumaSamples = reader.readUE()

        let conformanceWindowFlag = reader.readFlag()
        var confWinLeftOffset: UInt = 0, confWinRightOffset: UInt = 0, confWinTopOffset: UInt = 0, confWinBottomOffset: UInt = 0
        if conformanceWindowFlag {
            confWinLeftOffset = reader.readUE()
            confWinRightOffset = reader.readUE()
            confWinTopOffset = reader.readUE()
            confWinBottomOffset = reader.readUE()
        }

        let bitDepthLumaMinus8 = reader.readUE()
        let bitDepthChromaMinus8 = reader.readUE()
        let log2MaxPicOrderCntLsbMinus4 = reader.readUE()
        let spsSubLayerOrderingInfoPresentFlag = reader.readFlag()

        var maxDecPicBufferingMinus1: [UInt] = []
        var maxNumReorderPics: [UInt] = []
        var maxLatencyIncreasePlus1: [UInt] = []

        //let loopCount = spsSubLayerOrderingInfoPresentFlag ? maxSubLayersMinus1 + 1 : 1
        let loopCount = (spsSubLayerOrderingInfoPresentFlag ? (maxSubLayersMinus1 + 1) : 1)
        print("[parseSps] spsSubLayerOrderingInfoPresentFlag = \(spsSubLayerOrderingInfoPresentFlag)")
        print("[parseSps] maxSubLayersMinus1 = \(maxSubLayersMinus1)")
        for i in 0..<loopCount {
            let decPicBuf = reader.readUE()
            let reorderPics = reader.readUE()
            let latency = reader.readUE()
            print("[parseSps] Layer[\(i)]: dec_buf=\(decPicBuf), reorder=\(reorderPics), latency=\(latency)")
            maxDecPicBufferingMinus1.append(decPicBuf)
            maxNumReorderPics.append(reorderPics)
            maxLatencyIncreasePlus1.append(latency)
//            maxDecPicBufferingMinus1.append(reader.readUE())
//            maxNumReorderPics.append(reader.readUE())
//            maxLatencyIncreasePlus1.append(reader.readUE())
        }

        let log2MinLumaCodingBlockSizeMinus3 = reader.readUE()
        let log2DiffMaxMinLumaCodingBlockSize = reader.readUE()
        let log2MinLumaTransformBlockSizeMinus2 = reader.readUE()
        let log2DiffMaxMinLumaTransformBlockSize = reader.readUE()
        let maxTransformHierarchyDepthInter = reader.readUE()
        let maxTransformHierarchyDepthIntra = reader.readUE()

        let scalingListEnabledFlag = reader.readFlag()
        let spsScalingListDataPresentFlag = scalingListEnabledFlag ? reader.readFlag() : false

        let ampEnabledFlag = reader.readFlag()
        let sampleAdaptiveOffsetEnabledFlag = reader.readFlag()
        let pcmEnabledFlag = reader.readFlag()
        if pcmEnabledFlag {
            _ = reader.readBits(4) // pcm_sample_bit_depth_luma_minus1
            _ = reader.readBits(4) // pcm_sample_bit_depth_chroma_minus1
            _ = reader.readUE()    // log2_min_pcm_luma_coding_block_size_minus3
            _ = reader.readUE()    // log2_diff_max_min_pcm_luma_coding_block_size
            _ = reader.readFlag()  // pcm_loop_filter_disabled_flag
        }

        let numShortTermRefPicSets = reader.readUE()
        // ST RPS parsing 생략 가능 (보통 디코딩에는 직접 필요 없음)

        let longTermRefPicsPresentFlag = reader.readFlag()
        if longTermRefPicsPresentFlag {
            let numLongTermRefPicsSPS = reader.readUE()
            for _ in 0..<numLongTermRefPicsSPS {
                _ = reader.readBits(Int(log2(Double(1 << (log2MaxPicOrderCntLsbMinus4 + 4)))))
                _ = reader.readFlag() // used_by_curr_pic_lt_sps_flag
            }
        }

        let spsTemporalMvpEnabledFlag = reader.readFlag()
        let strongIntraSmoothingEnabledFlag = reader.readFlag()
        let vuiParametersPresentFlag = reader.readFlag()
        var vuiParameters: H265VUIParameters? = nil
        if vuiParametersPresentFlag {
            vuiParameters = VUIParser().parseVUIParameters(reader: &reader)
        }
        
        return H265SPS(
            videoParameterSetId: videoParameterSetId,
            maxSubLayersMinus1: maxSubLayersMinus1,
            temporalIdNestingFlag: temporalIdNestingFlag,
            generalProfileSpace: generalProfileSpace,
            generalTierFlag: generalTierFlag,
            generalProfileIdc: generalProfileIdc,
            generalProfileCompatibilityFlags: generalProfileCompatibilityFlags,
            generalConstraintIndicatorFlags: generalConstraintIndicatorFlags,
            generalLevelIdc: generalLevelIdc,
            spsSeqParameterSetId: spsSeqParameterSetId,
            chromaFormatIdc: chromaFormatIdc,
            separateColourPlaneFlag: separateColourPlaneFlag,
            picWidthInLumaSamples: picWidthInLumaSamples,
            picHeightInLumaSamples: picHeightInLumaSamples,
            conformanceWindowFlag: conformanceWindowFlag,
            confWinLeftOffset: confWinLeftOffset,
            confWinRightOffset: confWinRightOffset,
            confWinTopOffset: confWinTopOffset,
            confWinBottomOffset: confWinBottomOffset,
            bitDepthLumaMinus8: bitDepthLumaMinus8,
            bitDepthChromaMinus8: bitDepthChromaMinus8,
            log2MaxPicOrderCntLsbMinus4: log2MaxPicOrderCntLsbMinus4,
            spsSubLayerOrderingInfoPresentFlag: spsSubLayerOrderingInfoPresentFlag,
            maxDecPicBufferingMinus1: maxDecPicBufferingMinus1,
            maxNumReorderPics: maxNumReorderPics,
            maxLatencyIncreasePlus1: maxLatencyIncreasePlus1,
            log2MinLumaCodingBlockSizeMinus3: log2MinLumaCodingBlockSizeMinus3,
            log2DiffMaxMinLumaCodingBlockSize: log2DiffMaxMinLumaCodingBlockSize,
            log2MinLumaTransformBlockSizeMinus2: log2MinLumaTransformBlockSizeMinus2,
            log2DiffMaxMinLumaTransformBlockSize: log2DiffMaxMinLumaTransformBlockSize,
            maxTransformHierarchyDepthInter: maxTransformHierarchyDepthInter,
            maxTransformHierarchyDepthIntra: maxTransformHierarchyDepthIntra,
            scalingListEnabledFlag: scalingListEnabledFlag,
            spsScalingListDataPresentFlag: spsScalingListDataPresentFlag,
            ampEnabledFlag: ampEnabledFlag,
            sampleAdaptiveOffsetEnabledFlag: sampleAdaptiveOffsetEnabledFlag,
            pcmEnabledFlag: pcmEnabledFlag,
            numShortTermRefPicSets: numShortTermRefPicSets,
            longTermRefPicsPresentFlag: longTermRefPicsPresentFlag,
            spsTemporalMvpEnabledFlag: spsTemporalMvpEnabledFlag,
            strongIntraSmoothingEnabledFlag: strongIntraSmoothingEnabledFlag,
            vuiParametersPresentFlag: vuiParametersPresentFlag,
            vuiParameters: vuiParameters
        )
    }
    
    func parseProfileTierLevel(reader: BitReader, maxSubLayersMinus1: UInt) -> H265ProfileTierLevel {
        let generalProfileSpace = reader.readBits(2)
        let generalTierFlag = reader.readFlag()
        let generalProfileIdc = reader.readBits(5)
        let generalProfileCompatibilityFlags = UInt32(reader.readBits(32))
        let generalConstraintIndicatorFlags_hight = reader.readBits(16)
        let generalConstraintIndicatorFlags_row = reader.readBits(32)
        let generalConstraintIndicatorFlags = (UInt64(generalConstraintIndicatorFlags_hight << 32) | UInt64(generalConstraintIndicatorFlags_row))
//        var generalProfileCompatibilityFlags: UInt32 = 0
//        for _ in 0..<4 {
//            generalProfileCompatibilityFlags = (generalProfileCompatibilityFlags << 8) | UInt32(reader.readBits(8))
//        }
//        
//        var generalConstraintIndicatorFlags: UInt64 = 0
//        for _ in 0..<6 {
//            generalConstraintIndicatorFlags = (generalConstraintIndicatorFlags << 8) | UInt64(reader.readBits(8))
//        }
        
        let generalLevelIdc = reader.readBits(8)

        // profile_tier_level 에는 maxSubLayersMinus1 개의 sub_layer 정보가 있을 수 있지만
        // SPS에서 사용하는 경우 대부분 생략됨 (sub_layer_profile_present_flag 등)
        // 필요 시 여기에 추가 가능

        return H265ProfileTierLevel(
            generalProfileSpace: generalProfileSpace,
            generalTierFlag: generalTierFlag,
            generalProfileIdc: generalProfileIdc,
            generalProfileCompatibilityFlags: generalProfileCompatibilityFlags,
            generalConstraintIndicatorFlags: generalConstraintIndicatorFlags,
            generalLevelIdc: generalLevelIdc
        )
    }

    
    func parsePPS(reader: BitReader) -> H265PPS {
        let ppsPicParameterSetId = reader.readUE()
        let ppsSeqParameterSetId = reader.readUE()
        let dependentSliceSegmentsEnabledFlag = reader.readFlag()
        let outputFlagPresentFlag = reader.readFlag()
        let numExtraSliceHeaderBits = reader.readBits(3)
        let signDataHidingEnabledFlag = reader.readFlag()
        let cabacInitPresentFlag = reader.readFlag()
        let numRefIdxL0DefaultActiveMinus1 = reader.readUE()
        let numRefIdxL1DefaultActiveMinus1 = reader.readUE()
        let initQpMinus26 = reader.readSE()
        let constrainedIntraPredFlag = reader.readFlag()
        let transformSkipEnabledFlag = reader.readFlag()
        let cuQpDeltaEnabledFlag = reader.readFlag()
        let diffCuQpDeltaDepth = cuQpDeltaEnabledFlag ? reader.readUE() : 0
        let ppsCbQpOffset = reader.readSE()
        let ppsCrQpOffset = reader.readSE()
        let ppsSliceChromaQpOffsetsPresentFlag = reader.readFlag()
        let weightedPredFlag = reader.readFlag()
        let weightedBipredFlag = reader.readFlag()
        let transquantBypassEnabledFlag = reader.readFlag()
        let tilesEnabledFlag = reader.readFlag()
        let entropyCodingSyncEnabledFlag = reader.readFlag()
        var numTileColumnsMinus1: UInt = 0
        var numTileRowsMinus1: UInt = 0
        var loopFilterAcrossTilesEnabledFlag = false

        if tilesEnabledFlag {
            numTileColumnsMinus1 = reader.readUE()
            numTileRowsMinus1 = reader.readUE()
            loopFilterAcrossTilesEnabledFlag = reader.readFlag()
        }

        let ppsLoopFilterAcrossSlicesEnabledFlag = reader.readFlag()
        let deblockingFilterControlPresentFlag = reader.readFlag()
        let deblockingFilterOverrideEnabledFlag = deblockingFilterControlPresentFlag ? reader.readFlag() : false
        let ppsDeblockingFilterDisabledFlag = deblockingFilterControlPresentFlag ? reader.readFlag() : false
        let ppsScalingListDataPresentFlag = reader.readFlag()
        let listsModificationPresentFlag = reader.readFlag()
        let log2ParallelMergeLevelMinus2 = reader.readUE()
        let sliceSegmentHeaderExtensionPresentFlag = reader.readFlag()

        return H265PPS(
            ppsPicParameterSetId: ppsPicParameterSetId,
            ppsSeqParameterSetId: ppsSeqParameterSetId,
            dependentSliceSegmentsEnabledFlag: dependentSliceSegmentsEnabledFlag,
            outputFlagPresentFlag: outputFlagPresentFlag,
            numExtraSliceHeaderBits: numExtraSliceHeaderBits,
            signDataHidingEnabledFlag: signDataHidingEnabledFlag,
            cabacInitPresentFlag: cabacInitPresentFlag,
            numRefIdxL0DefaultActiveMinus1: numRefIdxL0DefaultActiveMinus1,
            numRefIdxL1DefaultActiveMinus1: numRefIdxL1DefaultActiveMinus1,
            initQpMinus26: initQpMinus26,
            constrainedIntraPredFlag: constrainedIntraPredFlag,
            transformSkipEnabledFlag: transformSkipEnabledFlag,
            cuQpDeltaEnabledFlag: cuQpDeltaEnabledFlag,
            diffCuQpDeltaDepth: diffCuQpDeltaDepth,
            ppsCbQpOffset: ppsCbQpOffset,
            ppsCrQpOffset: ppsCrQpOffset,
            ppsSliceChromaQpOffsetsPresentFlag: ppsSliceChromaQpOffsetsPresentFlag,
            weightedPredFlag: weightedPredFlag,
            weightedBipredFlag: weightedBipredFlag,
            transquantBypassEnabledFlag: transquantBypassEnabledFlag,
            tilesEnabledFlag: tilesEnabledFlag,
            entropyCodingSyncEnabledFlag: entropyCodingSyncEnabledFlag,
            numTileColumnsMinus1: numTileColumnsMinus1,
            numTileRowsMinus1: numTileRowsMinus1,
            loopFilterAcrossTilesEnabledFlag: loopFilterAcrossTilesEnabledFlag,
            ppsLoopFilterAcrossSlicesEnabledFlag: ppsLoopFilterAcrossSlicesEnabledFlag,
            deblockingFilterControlPresentFlag: deblockingFilterControlPresentFlag,
            deblockingFilterOverrideEnabledFlag: deblockingFilterOverrideEnabledFlag,
            ppsDeblockingFilterDisabledFlag: ppsDeblockingFilterDisabledFlag,
            ppsScalingListDataPresentFlag: ppsScalingListDataPresentFlag,
            listsModificationPresentFlag: listsModificationPresentFlag,
            log2ParallelMergeLevelMinus2: log2ParallelMergeLevelMinus2,
            sliceSegmentHeaderExtensionPresentFlag: sliceSegmentHeaderExtensionPresentFlag
        )
    }

    func parseVPS(reader: BitReader) -> H265VPS {
        let vpsVideoParameterSetId = reader.readBits(4)
        let vpsBaseLayerInternalFlag = reader.readFlag()
        let vpsBaseLayerAvailableFlag = reader.readFlag()
        let vpsMaxLayersMinus1 = reader.readBits(6)
        let vpsMaxSubLayersMinus1 = reader.readBits(3)
        let vpsTemporalIdNestingFlag = reader.readFlag()

        let profileTierLevel = parseProfileTierLevel(reader: reader, maxSubLayersMinus1: vpsMaxSubLayersMinus1)

        let vpsSubLayerOrderingInfoPresentFlag = reader.readFlag()
        var maxDecPicBufferingMinus1: [UInt] = []
        var maxNumReorderPics: [UInt] = []
        var maxLatencyIncreasePlus1: [UInt] = []
        let loopCount = vpsSubLayerOrderingInfoPresentFlag ? Int(vpsMaxSubLayersMinus1 + 1) : 1

        for i in 0..<Int(vpsMaxSubLayersMinus1 + 1) {
            if i < loopCount {
                maxDecPicBufferingMinus1.append(reader.readUE())
                maxNumReorderPics.append(reader.readUE())
                maxLatencyIncreasePlus1.append(reader.readUE())
            } else {
                maxDecPicBufferingMinus1.append(maxDecPicBufferingMinus1[i - 1])
                maxNumReorderPics.append(maxNumReorderPics[i - 1])
                maxLatencyIncreasePlus1.append(maxLatencyIncreasePlus1[i - 1])
            }
        }

        let vpsMaxLayerId = reader.readBits(6)
        let vpsNumLayerSetsMinus1 = reader.readUE()

        var layerIdIncludedFlag: [[Bool]] = []
        print("vpsNumLayerSetsMinus1: \(vpsNumLayerSetsMinus1)")
        for _ in 1...vpsNumLayerSetsMinus1 {
            var flags: [Bool] = []
            for _ in 0..<vpsMaxLayerId {
                flags.append(reader.readFlag())
            }
            layerIdIncludedFlag.append(flags)
        }

        let vpsTimingInfoPresentFlag = reader.readFlag()
        var vpsNumUnitsInTick: UInt? = nil
        var vpsTimeScale: UInt? = nil
        var vpsPocProportionalToTimingFlag: Bool? = nil
        var vpsNumTicksPocDiffOneMinus1: UInt? = nil

        if vpsTimingInfoPresentFlag {
            vpsNumUnitsInTick = reader.readBits(32)
            vpsTimeScale = reader.readBits(32)
            vpsPocProportionalToTimingFlag = reader.readFlag()
            if vpsPocProportionalToTimingFlag! {
                vpsNumTicksPocDiffOneMinus1 = reader.readUE()
            }
        }

        let vpsHrdParametersPresentFlag = reader.readFlag()
        // HRD parameters 생략

        let vpsExtensionFlag = reader.readFlag()

        return H265VPS(
            vpsVideoParameterSetId: vpsVideoParameterSetId,
            vpsBaseLayerInternalFlag: vpsBaseLayerInternalFlag,
            vpsBaseLayerAvailableFlag: vpsBaseLayerAvailableFlag,
            vpsMaxLayersMinus1: vpsMaxLayersMinus1,
            vpsMaxSubLayersMinus1: vpsMaxSubLayersMinus1,
            vpsTemporalIdNestingFlag: vpsTemporalIdNestingFlag,
            profileTierLevel: profileTierLevel,
            vpsSubLayerOrderingInfoPresentFlag: vpsSubLayerOrderingInfoPresentFlag,
            maxDecPicBufferingMinus1: maxDecPicBufferingMinus1,
            maxNumReorderPics: maxNumReorderPics,
            maxLatencyIncreasePlus1: maxLatencyIncreasePlus1,
            vpsMaxLayerId: vpsMaxLayerId,
            vpsNumLayerSetsMinus1: vpsNumLayerSetsMinus1,
            layerIdIncludedFlag: layerIdIncludedFlag,
            vpsTimingInfoPresentFlag: vpsTimingInfoPresentFlag,
            vpsNumUnitsInTick: vpsNumUnitsInTick,
            vpsTimeScale: vpsTimeScale,
            vpsPocProportionalToTimingFlag: vpsPocProportionalToTimingFlag,
            vpsNumTicksPocDiffOneMinus1: vpsNumTicksPocDiffOneMinus1,
            vpsHrdParametersPresentFlag: vpsHrdParametersPresentFlag,
            vpsExtensionFlag: vpsExtensionFlag
        )
    }


}
