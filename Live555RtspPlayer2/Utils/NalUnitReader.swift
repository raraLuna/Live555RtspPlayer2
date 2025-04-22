//
//  NalUnitReader.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/25/25.
//

import Foundation
import CoreMedia

enum ESStreamType: UInt8 {
    case unspecific = 0x00
    case mpeg1Video = 0x01
    case mpeg2Video = 0x02
    case mpeg1Audio = 0x03
    case mpeg2Audio = 0x04
    case mpeg2TabledData = 0x05
    case mpeg2PacketizedData = 0x06

    case adtsAac = 0x0F
    case h263 = 0x10

    case h264 = 0x1B
    case h265 = 0x24

    var headerSize: Int {
        switch self {
        case .adtsAac:
            return 7
        default:
            return 0
        }
    }
}

enum AVCNALUnitType: UInt8, Equatable {
    case unspec = 0
    case slice = 1 // P frame
    case dpa = 2
    case dpb = 3
    case dpc = 4
    case idr = 5 // I frame
    case sei = 6
    case sps = 7
    case pps = 8
    case aud = 9
    case eoseq = 10
    case eostream = 11
    case fill = 12
}

// MARK: -
struct AVCNALUnit: NALUnit, Equatable {
    let refIdc: UInt8
    let type: AVCNALUnitType
    let payload: Data

    init(_ data: Data) {
        self.init(data, length: data.count)
    }

    init(_ data: Data, length: Int) {
        self.refIdc = data[0] >> 5
        self.type = AVCNALUnitType(rawValue: data[0] & 0x1f) ?? .unspec
        self.payload = data.subdata(in: 1..<length)
    }

    var data: Data {
        var result = Data()
        result.append(refIdc << 5 | self.type.rawValue)
        result.append(payload)
        return result
    }
}

protocol NALUnit  {
    init(_ data: Data)
}

final class NalUnitReader {
    static let defaultNALUnitHeaderLength: Int32 = 4
    var nalUnitHeaderLength: Int32 = NalUnitReader.defaultNALUnitHeaderLength
    
    func read<T: NALUnit>(_ data: inout Data, type: T.Type) -> [T] {
        var units: [T] = .init()
        var lastIndexOf = data.count - 1
        for i in (2..<data.count).reversed() {
            guard data[i] == 1 && data[i - 1] == 0 && data[i - 2] == 0 else {
                continue
            }
            let startCodeLength = 0 <= i - 3 && data[i - 3] == 0 ? 4 : 3
            units.append(T.init(data.subdata(in: ( i + 1)..<lastIndexOf + 1)))
            lastIndexOf = i - startCodeLength
        }
        return units
    }
    
    func makeFormatDescription(_ data: inout Data, type: ESStreamType) -> CMFormatDescription? {
        switch type {
        case .h264:
            let units = read(&data, type: AVCNALUnit.self)
            return units.makeFormatDescription(nalUnitHeaderLength)
        case .h265:
            print("h265 not yet supported")
            return nil
            //let units = read(&data, type: HEVCNALUnit.self)
            //return units.makeFormatDescription(nalUnitHeaderLength)
        default:
            return nil
        }
    }
}

extension [AVCNALUnit] {
    func makeFormatDescription(_ nalUnitHeaderLength: Int32 = 4) -> CMFormatDescription? {
        guard
            let pps = first(where: { $0.type == .pps }),
            let sps = first(where: { $0.type == .sps }) else {
            return nil
        }
        var formatDescription: CMFormatDescription?
        let status = pps.data.withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                return kCMFormatDescriptionBridgeError_InvalidParameter
            }
            return sps.data.withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> OSStatus in
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
        if status != noErr {
            print("makeFormatDescription error: \(status)")
        }
        return formatDescription
    }
}





