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

    func readBits(_ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<count {
            value = (value << 1) | UInt32(readBit())
        }
        return value
    }

    func readBit() -> UInt8 {
        guard byteOffset < data.count else { return 0 }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return bit
    }

    func readUE() -> UInt32 {
        var zeros: Int = 0
        while readBit() == 0 {
            zeros += 1
        }
        let value = readBits(zeros)
        return (1 << zeros) - 1 + value
    }

    func skipBits(_ count: Int) {
        for _ in 0..<count {
            _ = readBit()
        }
    }
}
