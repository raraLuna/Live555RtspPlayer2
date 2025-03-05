//
//  AacParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/14/25.
//

import Foundation

// https://tools.ietf.org/html/rfc3640
//          +---------+-----------+-----------+---------------+
//         | RTP     | AU Header | Auxiliary | Access Unit   |
//         | Header  | Section   | Section   | Data Section  |
//         +---------+-----------+-----------+---------------+
//
//                   <----------RTP Packet Payload----------->
class AacParser {
    private let aacMode: Int
    
    private static let MODE_LBR = 0
    private static let MODE_HBR = 1
    
    private static let NUM_BITS_AU_SIZES = [6, 13]
    private static let NUM_BITS_AU_INDEX = [2, 3]
    private static let FRAME_SIZES = [63, 8191]
    
    private var completFrameIndicator: Bool = true
    private var fragmentedAacFrame: FragmentedAacFrame?
    
    init(aacMode: String) {
        self.aacMode = aacMode.lowercased() == "aac-lbr" ? AacParser.MODE_LBR : AacParser.MODE_HBR
    }
    
    func processRtpPacketAndGetSample(data: [UInt8]) -> [UInt8] {
        print("processRtpPacketAndGetSample(length: \(data.count))")
        //      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+- .. -+-+-+-+-+-+-+-+-+-+
        //      |AU-headers-length|AU-header|AU-header|      |AU-header|padding|
        //      |                 |   (1)   |   (2)   |      |   (n)   | bits  |
        //      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+- .. -+-+-+-+-+-+-+-+-+-+
        
        print("data: \([UInt8](data))")
        var packet = ByteReader(data: data)
        
        // ((data[0] & 0xFF) << 8) | (data[1] & 0xFF);
        let auHeaderLength = packet.readShort()
        print("auHeaderLength: \(auHeaderLength)")
        
        let auHeaderLengthBytes = (auHeaderLength + 7) / 8
        print("auHeaderLengthBytes: \(auHeaderLengthBytes)")
        
        let headerData = packet.readBytes(length: auHeaderLengthBytes)
        print("headerData: \(headerData)")
        
        var headerBits = BitReader(data: headerData)
        
        let numBitsAuSize = AacParser.NUM_BITS_AU_SIZES[aacMode]
        let numBitsAuIndex = AacParser.NUM_BITS_AU_INDEX[aacMode]
        
        let bitsAvailable = auHeaderLength - (numBitsAuSize + numBitsAuIndex)
        var auHeaderCount = 1
        
        print("bitsAvailable: \(bitsAvailable)")
        
        if auHeaderCount == 1 {
            let auSize = headerBits.readBits(numBitsAuSize)
            let auIndex = headerBits.readBits(numBitsAuIndex)
            
            print("auSize: \(auSize)")
            print("auIndex: \(auIndex)")
            
            if completFrameIndicator {
                if auIndex == 0 {
                    if packet.bytesLeft() == auSize {
                        print("packet.bytesLeft(): \(packet.bytesLeft())")
                        return handleSingleAacFrame(packet: &packet)
                    } else {
                        handleFragmentationAacFrame(packet: packet, auSize: auSize)
                    }
                }
            } else {
                // handleFragmentationAacFrame(packet, auSize)
            }
        } else {
            if completFrameIndicator {
                // handleMultipleAacFrames(packet, auHeaderLength)
            }
        }
        return []
    }
    
    // 완전한 AACA frame 반환
    private func handleSingleAacFrame(packet: inout ByteReader) -> [UInt8] {
        return packet.readRemainingBytes()
    }
    
    // 단편화 된 AAC 프레임의 경우
    // 단편화 된 AU를 재구성하여 완성 여부 확인
    private func handleFragmentationAacFrame(packet: ByteReader, auSize: Int) {
        if fragmentedAacFrame == nil {
            fragmentedAacFrame = FragmentedAacFrame(frameSize: auSize)
        }
        
        fragmentedAacFrame?.appendFragment(fragment: packet.readRemainingBytes())
        
        if ((fragmentedAacFrame?.isComplete) != nil) {
            completFrameIndicator = true
        } else {
            completFrameIndicator = false
        }
    }
    
    // 여러 AU 헤더가 존재하는 패킷 처리
    private func handleMultiplexedAacFrame(packet: inout ByteReader, auHeadersLength: Int) -> [UInt8] {
        return packet.readRemainingBytes()
    }
}

class FragmentedAacFrame {
    private var auData: [UInt8]
    private var auSize: Int
    private var auLength: Int
    
    init(frameSize: Int) {
        self.auSize = frameSize
        self.auData = [UInt8](repeating: 0, count: frameSize)
        self.auLength = 0
    }
    
    func appendFragment(fragment: [UInt8]) {
        print("auData: \(auData)")
        auData.replaceSubrange(auLength..<auLength+fragment.count, with: fragment)
        auLength += fragment.count
    }
    
    func isComplete() -> Bool {
        return auLength == auSize
    }
}

class ByteReader {
    private var data: [UInt8]
    private var position: Int = 0
    
    init(data: [UInt8]) {
        self.data = data
    }
    
    // 2바이트 읽고 정수로 변환
    func readShort() -> Int {
        guard position + 2 <= data.count else {
            return 0
        }
        //let value = Int(data[position]) << 8 | Int(data[position + 1])
        let value = Int(data[position] & 0xFF) << 8 | Int(data[position + 1] & 0xFF)
        position += 2
        //print("readShort return value: \(value)")
        return value
    }
    
    // 지정된 길이만큼 데이터 가져옴
    func readBytes(length: Int) -> [UInt8] {
        guard position + length <= data.count else {
            return []
        }
        let result = Array(data[position..<(position + length)])
        position += length
        return result
    }
    
    // 남은 모든 데이터 반환
    func readRemainingBytes() -> [UInt8] {
        guard position < data.count else {
            return []
        }
        let result = Array(data[position..<data.count])
        position = data.count
        return result
    }
    
    func bytesLeft() -> Int {
        return data.count - position
    }
}

class BitReader {
    private var data: [UInt8]
    private var bitPosition: Int = 0
    
    init(data: [UInt8]) {
        self.data = data
    }
    
    // 주어진 수 만큼 비트 읽고 정수 값으로 반환
    func readBits(_ length: Int) -> Int {
        var value = 0
        for _ in 0..<length {
            let byteIndex = bitPosition / 8
            let bitIndex = 7 - (bitPosition % 8)
            if byteIndex < data.count  {
                let bit = (data[byteIndex] >> bitIndex) & 1
                value = (value << 1) | Int(bit)
            }
            bitPosition += 1
        }
        return value
    }
}
