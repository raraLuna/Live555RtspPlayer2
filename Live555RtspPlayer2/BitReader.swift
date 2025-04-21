//
//  BitReader.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/15/25.
//

import Foundation

enum BitReaderError: Error {
    case outOfBounds
    case invalidExpGolomb
}

class BitReader {
    private let data: Data
    private var byteOffset: Int = 0
    private var bitOffset: UInt8 = 0

    init(_ data: Data) {
        self.data = data
    }

    func readBits(_ count: Int) -> UInt {
        var value: UInt = 0
        for _ in 0..<count {
            value = (value << 1) | UInt(readBit())
        }
        return value
    }

    func readBit() -> UInt {
        guard byteOffset < data.count else { return 0 }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return UInt(bit)
    }
    
//    func readUE() -> Int {
//            var zeroBits = 0
//            while readBits(1) == 0 && byteOffset < data.count {
//                zeroBits += 1
//            }
//            let rest = readBits(zeroBits)
//        return Int((1 << zeroBits) - 1 + rest)
//        }
    
    func readUE() -> UInt {
        var zeros = 0
        while readBit() == 0 && byteOffset < data.count {
            zeros += 1
        }

        var value: UInt = 1
        for _ in 0..<zeros {
            value = (value << 1) | readBit()
        }

        return value - 1
    }

    func readSE() -> Int {
        let ueVal = readUE()
        if ueVal % 2 == 0 {
            return -Int(ueVal / 2)
        } else {
            return Int((ueVal + 1) / 2)
        }
    }
}
