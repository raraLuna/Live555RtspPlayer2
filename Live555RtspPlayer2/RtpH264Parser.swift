//
//  RtpH264Parser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/13/25.
//

import Foundation

class RtpH264Parser: RtpParser {
    private let TAG = "RtpH264Parser"
    
    override func processRtpPacketAndGetNalUnit(data: [UInt8], length: Int, marker: Bool) -> [UInt8] {
        print("processRtpPacketAndGetNalUnit(data.size=\(data.count), length=\(length), marker=\(marker))")
        
        let nalType = data[0] & 0x1F // FU_A Header
        let packFlag = Int(data[1] & 0xC0) // FU_A Indicator
        var nalUnit: [UInt8] = []
        
        print("NAL type: \(getH265NalUintTypeString(nalType)), pack flag: 0x\(String(format: "%02X", packFlag))")
        
        switch nalType {
        case VideoCodecUtils.NAL_STAP_A, VideoCodecUtils.NAL_STAP_B:
            break // not supported
        case VideoCodecUtils.NAL_MTAP16, VideoCodecUtils.NAL_MTAP24:
            break // not supported
        case VideoCodecUtils.NAL_FU_A:
            switch packFlag {
            case 0x80:
                addStartFragmentedPacket(data: data, length: length)
            case 0x00:
                if marker {
                    nalUnit = addEndFragmentedPacketAndCombine(data: data, length: length)
                } else {
                    addMiddleFragmentedPacket(data: data, length: length)
                }
            case 0x40:
                nalUnit = addEndFragmentedPacketAndCombine(data: data, length: length)
            default:
                break 
            }
        case VideoCodecUtils.NAL_FU_B:
            break
        default:
            nalUnit = processSingleFramePacket(data: data, length: length)
            clearFragmentedBuffer()
            print("Single NAL (\(nalUnit.count))")
        }
        
        return nalUnit
    }
    
    override func writeNalPrefix0001(to buffer: inout [UInt8]) {
        super.writeNalPrefix0001(to: &buffer)
        //buffer.replaceSubrange(0..<4, with: [0x00, 0x00, 0x00, 0x01])
    }
    
    override func processSingleFramePacket(data: [UInt8], length: Int) -> [UInt8] {
        super.processSingleFramePacket(data: data, length: length)
//        var nalUnit = [UInt8](repeating: 0, count: 4 + length)
//        writeNalPrefix0001(to: &nalUnit)
//        nalUnit.replaceSubrange(4..<nalUnit.count, with: data.prefix(length))
//        
//        return nalUnit
    }
    
    private func addStartFragmentedPacket(data: [UInt8], length: Int) {
        print("addStartFragmentedPacket(data.count=\(data.count), length=\(length))")
        
        RtpH264Parser.fragmentedPackets = 0
        RtpH264Parser.fragmentedBufferLength = length - 1
        //fragmentedBuffer[0] = Data(count: fragmentedBufferLength)
        RtpH264Parser.fragmentedBuffer[0] = [UInt8](repeating: 0, count: RtpH264Parser.fragmentedBufferLength)
        
        RtpH264Parser.fragmentedBuffer[0]?[0] = (data[0] & 0xE0) | (data[1] & 0x1F)
        RtpH264Parser.fragmentedBuffer[0]?.replaceSubrange(1..<(length - 1), with: data[2..<length])
    }
    
    private func addMiddleFragmentedPacket(data: [UInt8], length: Int) {
        print("addMiddleFragmentedPacket(data.count=\(data.count), length=\(length))")
        
        RtpH264Parser.fragmentedPackets += 1
        if RtpH264Parser.fragmentedPackets >= RtpH264Parser.fragmentedBuffer.count {
            print("Too many middle packets. No NAL FU_A end packet received. Skipped RTP Packet.")
            RtpH264Parser.fragmentedBuffer[0] = nil
        } else {
            RtpH264Parser.fragmentedBufferLength += length - 2
            RtpH264Parser.fragmentedBuffer[RtpH264Parser.fragmentedPackets] = [UInt8](Data(data[2..<length]))
        }
    }
    
    private func addEndFragmentedPacketAndCombine(data: [UInt8], length: Int) -> [UInt8] {
        print("addEndFragmentedPacketAndCombine(data.count=\(data.count), length=\(length)")
        
        guard RtpH264Parser.fragmentedBuffer[0] != nil else {
            print("No NAL FU_A start packet received. Skipped RTP packet.")
            return []
        }
        
        var nalUnit = [UInt8](Data(count:RtpH264Parser.fragmentedBufferLength + length + 2))
        writeNalPrefix0001(to: &nalUnit)
        
        var tmpLen = 4
        for i in 0..<RtpH264Parser.fragmentedPackets {
            if let fragment = RtpH264Parser.fragmentedBuffer[i] {
                nalUnit.replaceSubrange(tmpLen..<(tmpLen + fragment.count), with: fragment)
                tmpLen += fragment.count
            }
        }
        
        nalUnit.replaceSubrange(tmpLen..<(tmpLen + length - 2), with: data[2..<length])
        clearFragmentedBuffer()
        
        print("Fragmented NAL (\(nalUnit.count))")
        return nalUnit
    }
    
    private func clearFragmentedBuffer() {
        print("clearFragmentedBuffer()")
        for i in 0...RtpH264Parser.fragmentedPackets {
            RtpH264Parser.fragmentedBuffer[i] = nil
        }
    }
    
    private func getH265NalUintTypeString(_ type: UInt8) -> String {
        return "NAL_TYPE_\(type)"
    }
}
