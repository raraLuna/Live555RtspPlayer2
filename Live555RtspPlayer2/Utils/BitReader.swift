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
    var byteOffset: Int = 0
    var bitOffset: UInt8 = 0
    
    init(_ data: Data) {
        self.data = data
    }
    
    // count만큼 비트를 반복하여 읽고 누적하여 하나의 정수로 반환함
    func readBits(_ count: Int) -> UInt {
        var value: UInt = 0
        for _ in 0..<count {
            value = (value << 1) | UInt(readBit())
        }
        return value
    }
    
    func readBits32(_ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<count {
            value = (value << 1) | UInt32(readBit())
        }
        return value
    }
    
    // 현재 바이트의 현재 비트 위치에서 1비트를 추출
    // 비트 오프셋이 8에 도달하면 다음 바이트로 이동
    // MSB부터 읽는 방식으로 비트 순서가 중요하다
    // MSB: Most Significant Bit. 가장 높은 자리수의 비트. 즉, 가장 왼쪽의 비트
    // LSB: Lest Significant Bit. 가장 낮은 자리수의 비트. 즉, 가장 오른쪽의 비트
    func readBit() -> UInt {
        
        guard byteOffset < data.count else {
            print("byteOffset: \(byteOffset) >= data.count: \(data.count)")
            return 0
        }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return UInt(bit)
    }
    
    // Unsigned Exp-Golomb 파싱
    // 앞의 0 개수를 세고, 그 뒤 n개의 비트를 값으로 해석
    // 2^zeros - 1 + binary_bits
    /// n개의 0이 나열 된 후 1이 나왔다면
    /// (2의 n승 - 1) + (1뒤에 나오는 n개의 나열값)
    /// 1 -> 0
    /// 01x -> 1 + x
    /// 001xx -> 3 + xx
    /// 0001xxx -> 7 + xxx
    func readUE() -> UInt {
        var zeros = 0
        // 0을 읽으면서 몇 개가 연속으로 나오는지 확인
        while readBit() == 0 && byteOffset < data.count {
            zeros += 1
        }
        
        // 비트 값을 저장할 변수 (초기값을 0으로 설정)
        var value: UInt = 0
        // zeros만큼 비트를 읽어 value를 구성
        for _ in 0..<zeros {
            value = (value << 1) | readBit()
        }
        
        // Exp-Golomb 공식: (2^zeros - 1) + value
        return (1 << zeros) - 1 + value
        
        //        var zeros = 0
        //        while readBit() == 0 && byteOffset < data.count {
        //            zeros += 1
        //        }
        //
        //        var value: UInt = 1
        //        for _ in 0..<zeros {
        //            value = (value << 1) | readBit()
        //        }
        //
        //        return value - 1
    }
    
    // Signed Exp-Golobm 파싱
    // 부호있는 정수로 변환하는 방법
    func readSE() -> Int {
        let ueVal = readUE()
        if ueVal % 2 == 0 {
            return -Int(ueVal / 2)
        } else {
            return Int((ueVal + 1) / 2)
        }
    }
    
    func readFlag() -> Bool {
        let bit = readBit()
        return bit == 1
    }
    
    func alignToByte() {
        if bitOffset != 0 {
            _ = readBits(8 - Int(bitOffset))
        }
    }
    
    func peekBytes(_ count: Int) -> [UInt8] {
        // bitOffset이 0이 아닐 경우, peekBytes는 예측 불가능한 값을 줄 수 있음
        guard bitOffset == 0 else {
            print("⚠️ Warning: peekBytes called at non-byte-aligned offset")
            return []
        }
        let start = byteOffset
        let end = min(start + count, data.count)
        return Array(data[start..<end])
    }
    
}
