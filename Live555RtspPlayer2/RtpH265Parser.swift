//
//  RtpH265Parser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/14/25.
//

import Foundation

class RtpH265Parser: RtpParser {
    private let RTP_PACKET_TYPE_AP: UInt8 = 48
    private let RTP_PACKET_TYPE_FU: UInt8 = 49
    
    override func processRtpPacketAndGetNalUnit(data: [UInt8], length: Int, marker: Bool) -> [UInt8] {
        print("processRtpPacketAndGetNalUnit(data.size=\(data.count), length=\(length), marker=\(marker))")
        
        let nalType = (data[0] >> 1) & 0x3F
        var nalUnit: [UInt8] = []
        
        if nalType < RTP_PACKET_TYPE_AP {
            nalUnit = processSingleFramePacket(data: data, length: length)
            clearFragmentedBuffer()
            print("Single NAL (\(nalUnit.count)")
        } else if nalType == RTP_PACKET_TYPE_AP {
            print("need to implement processAggregation Packet")
        } else if nalType == RTP_PACKET_TYPE_FU {
            nalUnit = processFragmentationUnitPacket(data: data, length: length, marker: marker)
        } else {
            print("RTP H265 payload type [\(nalType)] not supported")
        }
        
        return nalUnit
    }
    
    private func processFragmentationUnitPacket(data: [UInt8], length: Int, marker: Bool) -> [UInt8] {
        print("processFragmentationUnitPacket(length=\(length), marker=\(marker))")
        
        let fuHeader = data[2]
        let isFirstFuPacket = (fuHeader & 0x80) > 0
        let isLastFuPacket = (fuHeader & 0x40) > 0
        
        if isFirstFuPacket {
            addStartFragmentedPacket(data: data, length: length)
        } else if isLastFuPacket || marker {
            return addEndFragmentedPacketAndCombine(data: data, length: length)
        } else {
            addMiddleFragmentedPacket(data: data, length: length)
        }
        
        return []
    }
    
    private func addStartFragmentedPacket(data: [UInt8], length: Int) {
        print("addStartFragmentPacket(data.size=\(data.count), length=\(length))")
        
        RtpParser.fragmentedPackets = 0
        RtpParser.fragmentedBufferLength = length - 1
        RtpParser.fragmentedBuffer[0] = [UInt8](repeating: 0, count: RtpParser.fragmentedBufferLength)
        
        let tid = data[1] & 0x07
        let fuHeader = data[2]
        let nalUnitType = fuHeader & 0x3F
            
        // Convert RTP Header into HEVC NAL Unit header according to RFC7798 Section 1.1.4
        RtpParser.fragmentedBuffer[0]?[0] = (nalUnitType << 1) & 0x7F
        RtpParser.fragmentedBuffer[0]?[1] = tid
        
        RtpParser.fragmentedBuffer[0]?.replaceSubrange(2..., with: data[3..<length])
    }
    
    private func addMiddleFragmentedPacket(data: [UInt8], length: Int) {
        print("addMiddleFragmentedPacket(data.size=\(data.count), length=\(length)")
        
        RtpParser.fragmentedPackets += 1
        if RtpParser.fragmentedPackets >= RtpParser.fragmentedBuffer.count {
            print("Too many middle packckets. No RTP_PACKET_TYPE_FU end packet received. Skipped RTP packet.")
            RtpParser.fragmentedBuffer[0] = nil
        } else {
            RtpParser.fragmentedBufferLength += length - 3
            RtpParser.fragmentedBuffer[RtpParser.fragmentedPackets] = Array(data[3..<length])
        }
    }
    
    private func addEndFragmentedPacketAndCombine(data: [UInt8], length: Int) -> [UInt8] {
        print("addEndFragmentPacket(data.size=\(data.count), length=\(length))")
        
        guard RtpParser.fragmentedBuffer[0] != nil else {
            print("No NAL FU_A start packet received. Skipped RTP packet")
            return []
        }
        
        var nalUnit = [UInt8](repeating: 0, count: RtpParser.fragmentedBufferLength + length + 3)
        writeNalPrefix0001(to: &nalUnit)
        var tmpLen = 4
        
        // Write start and middle packets
        for i in 0...RtpParser.fragmentedPackets {
            if let packet = RtpParser.fragmentedBuffer[i] {
                nalUnit.replaceSubrange(tmpLen..<tmpLen + packet.count, with: packet)
                tmpLen += packet.count
            }
        }
        
        // Write and packet
        nalUnit.replaceSubrange(tmpLen..<tmpLen + (length - 3), with: data[3..<length])
        clearFragmentedBuffer()
        
        print("Fragmented NAL (\(nalUnit.count))")
        return nalUnit
    }
    
    private func clearFragmentedBuffer() {
        print("clearFragmentedBuffer()")
        for i in 0...RtpParser.fragmentedPackets {
            RtpParser.fragmentedBuffer[i] = nil
        }
    }
}
