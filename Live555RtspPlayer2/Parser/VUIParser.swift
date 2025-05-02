//
//  VUIParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/24/25.
//

import Foundation

// VUI: Video Usability Information
///HEVC 스트림이 디코딩 된 후 영상 출력 시 필요한 부가정보를 담고 있음
///영상의 비율, 색 공간, 프레임 레이트 계산에 사용할 시간 정보, 크로마 샘플 등.
///화면을 어떻게 정확하게 출력해야하는지에 대한 정보
struct H265VUIParameters {
    var aspectRatioInfoPresentFlag: Bool
    var aspectRatioIdc: UInt8?
    var sarWidth: UInt16?
    var sarHeight: UInt16?

    var overscanInfoPresentFlag: Bool
    var overscanAppropriateFlag: Bool?

    var videoSignalTypePresentFlag: Bool
    var videoFormat: UInt8?
    var videoFullRangeFlag: Bool?
    var colourDescriptionPresentFlag: Bool?
    var colourPrimaries: UInt8?
    var transferCharacteristics: UInt8?
    var matrixCoeffs: UInt8?

    var chromaLocInfoPresentFlag: Bool
    var chromaSampleLocTypeTopField: UInt?
    var chromaSampleLocTypeBottomField: UInt?

    var neutralChromaIndicationFlag: Bool
    var fieldSeqFlag: Bool
    var frameFieldInfoPresentFlag: Bool

    var defaultDisplayWindowFlag: Bool
    var defDispWinLeftOffset: UInt?
    var defDispWinRightOffset: UInt?
    var defDispWinTopOffset: UInt?
    var defDispWinBottomOffset: UInt?

    var vuiTimingInfoPresentFlag: Bool
    var numUnitsInTick: UInt32?
    var timeScale: UInt32?
    var pocProportionalToTimingFlag: Bool?
    var numTicksPocDiffOneMinus1: UInt?

    var hrdParametersPresentFlag: Bool
    // hrd_parameters 구조는 매우 복잡하므로 별도 정의 필요

    var bitstreamRestrictionFlag: Bool
    var tilesFixedStructureFlag: Bool?
    var motionVectorsOverPicBoundariesFlag: Bool?
    var restrictedRefPicListsFlag: Bool?
    var minSpatialSegmentationIdc: UInt?
    var maxBytesPerPicDenom: UInt?
    var maxBitsPerMinCuDenom: UInt?
    var log2MaxMvLengthHorizontal: UInt?
    var log2MaxMvLengthVertical: UInt?
}

class VUIParser {
    func parseVUIParameters(reader: inout BitReader) -> H265VUIParameters {
        var vui = H265VUIParameters(
            aspectRatioInfoPresentFlag: false,
            overscanInfoPresentFlag: false,
            videoSignalTypePresentFlag: false,
            chromaLocInfoPresentFlag: false,
            neutralChromaIndicationFlag: false,
            fieldSeqFlag: false,
            frameFieldInfoPresentFlag: false,
            defaultDisplayWindowFlag: false,
            vuiTimingInfoPresentFlag: false,
            hrdParametersPresentFlag: false,
            bitstreamRestrictionFlag: false
        )
        print("== VUI PARSE START == byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        vui.aspectRatioInfoPresentFlag = reader.readFlag()
        print("vui.aspectRatioInfoPresentFlag: \(vui.aspectRatioInfoPresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.aspectRatioInfoPresentFlag {
            vui.aspectRatioIdc = UInt8(reader.readBits(8))
            //print("vui.aspectRatioIdc: \(vui.aspectRatioIdc )")
            //print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            if vui.aspectRatioIdc == 255 {
                vui.sarWidth = UInt16(reader.readBits(16))
                vui.sarHeight = UInt16(reader.readBits(16))
            }
        }

        vui.overscanInfoPresentFlag = reader.readFlag()
        print("vui.overscanInfoPresentFlag: \(vui.overscanInfoPresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.overscanInfoPresentFlag {
            vui.overscanAppropriateFlag = reader.readFlag()
            //print("vui.overscanAppropriateFlag: \(vui.overscanAppropriateFlag)")
            //print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        }

        vui.videoSignalTypePresentFlag = reader.readFlag()
        print("vui.videoSignalTypePresentFlag: \(vui.videoSignalTypePresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.videoSignalTypePresentFlag {
            vui.videoFormat = UInt8(reader.readBits(3))
            print("vui.videoFormat: \(vui.videoFormat)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            vui.videoFullRangeFlag = reader.readFlag()
            print("vui.videoFullRangeFlag: \(vui.videoFullRangeFlag)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            vui.colourDescriptionPresentFlag = reader.readFlag()
            print("vui.colourDescriptionPresentFlag: \(vui.colourDescriptionPresentFlag)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            if vui.colourDescriptionPresentFlag == true {
                vui.colourPrimaries = UInt8(reader.readBits(8))
                vui.transferCharacteristics = UInt8(reader.readBits(8))
                vui.matrixCoeffs = UInt8(reader.readBits(8))
            }
        }

        vui.chromaLocInfoPresentFlag = reader.readFlag()
        print("vui.chromaLocInfoPresentFlag: \(vui.chromaLocInfoPresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.chromaLocInfoPresentFlag {
            vui.chromaSampleLocTypeTopField = reader.readUE()
            print("vui.chromaSampleLocTypeTopField: \(vui.chromaSampleLocTypeTopField)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            vui.chromaSampleLocTypeBottomField = reader.readUE()
            print("vui.chromaSampleLocTypeBottomField: \(vui.chromaSampleLocTypeBottomField)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        }

        vui.neutralChromaIndicationFlag = reader.readFlag()
        print("vui.neutralChromaIndicationFlag: \(vui.neutralChromaIndicationFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        vui.fieldSeqFlag = reader.readFlag()
        print("vui.fieldSeqFlag: \(vui.fieldSeqFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        vui.frameFieldInfoPresentFlag = reader.readFlag()
        print("vui.frameFieldInfoPresentFlag: \(vui.frameFieldInfoPresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")

        vui.defaultDisplayWindowFlag = reader.readFlag()
        print("vui.defaultDisplayWindowFlag: \(vui.defaultDisplayWindowFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.defaultDisplayWindowFlag {
            vui.defDispWinLeftOffset = reader.readUE()
            vui.defDispWinRightOffset = reader.readUE()
            vui.defDispWinTopOffset = reader.readUE()
            vui.defDispWinBottomOffset = reader.readUE()
        }

        vui.vuiTimingInfoPresentFlag = reader.readFlag()
        print("vui.vuiTimingInfoPresentFlag: \(vui.vuiTimingInfoPresentFlag)")
        print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
        if vui.vuiTimingInfoPresentFlag {
            //reader.alignToByte()
            //print("After alignToByte(): byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")

            //let peek = reader.peekBytes(8)
            //print("Aligned peek: \(peek.map { String(format: "%02X", $0) }.joined(separator: " "))")

//            vui.numUnitsInTick = UInt32(reader.readBits(32))
//            vui.timeScale = UInt32(reader.readBits(32))
            vui.numUnitsInTick = UInt32(reader.readBits(32))
            print("vui.numUnitsInTick: \(vui.numUnitsInTick)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            vui.timeScale = UInt32(reader.readBits(32))
            print("vui.timeScale: \(vui.timeScale)")
            print("byteOffset=\(reader.byteOffset), bitOffset=\(reader.bitOffset)")
            vui.pocProportionalToTimingFlag = reader.readFlag()
            if vui.pocProportionalToTimingFlag == true {
                vui.numTicksPocDiffOneMinus1 = reader.readUE()
            }
        }

        vui.hrdParametersPresentFlag = reader.readFlag()
        if vui.hrdParametersPresentFlag {
            // hrd_parameters(vui) 생략 또는 별도 구현 필요
            // skipHRDParameters(reader: &reader)
        }

        vui.bitstreamRestrictionFlag = reader.readFlag()
        if vui.bitstreamRestrictionFlag {
            vui.tilesFixedStructureFlag = reader.readFlag()
            vui.motionVectorsOverPicBoundariesFlag = reader.readFlag()
            vui.restrictedRefPicListsFlag = reader.readFlag()
            vui.minSpatialSegmentationIdc = reader.readUE()
            vui.maxBytesPerPicDenom = reader.readUE()
            vui.maxBitsPerMinCuDenom = reader.readUE()
            vui.log2MaxMvLengthHorizontal = reader.readUE()
            vui.log2MaxMvLengthVertical = reader.readUE()
        }

        return vui
    }

}
