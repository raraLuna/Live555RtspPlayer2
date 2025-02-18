//
//  RtpH264Parser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/13/25.
//

import Foundation

/*
 
 FU-A
+------------+------------+------------+---------------+
| FU Indicator (1B) | FU Header (1B) | FU Payload (nB) |
+------------+------------+------------+---------------+
 
  Fu Indicator(1Byte)
  +--------+---------+-------------+
  | F (1)  | NRI (2) | Type (5) (Always 28 for FU-A) |
  +--------+---------+-------------+
   F: Forbidden Bit (1이면 위반)
   NRI: 중요도 (nal_ref_idc, 00이면 reference picture를 재구성하는데 사용되지 않음을 나타냄
   Type: 항상 28
 
  Fu Header
  +-------------+--------------+----------+
  | Start (1)   | End (1)      | Reserved (1) | NAL Type (5) |
  +-------------+--------------+----------+
   Start(1bit): 첫번째 조각일 경우 1
   End(1bit): 마지막 조각일 경우 1
   NAL Type(5bit): 원래 NAL Unit Type
 
   SPS : 00 00 00 01 67
   PPS : 00 00 00 01 68
   IDR : 00 00 00 01 65
   
   H.264 데이터 스트림은 보통 SPS와 PPS로 시작하며, 그 이후에 IDR과 NON IDR 유닛들이 반복됨
   ** 보통 말하는 NAL Unit은 1-23이고, Single Packet이 따로 존재함.
      영상 스트리밍은 SPS가 온 뒤에 PPS가 오고, 그 뒤에 I프레임이 전송된다.
*/

class RtpH264Parser: RtpParser {
    override func processRtpPacketAndGetNalUnit(data: [UInt8], length: Int, marker: Bool) -> [UInt8] {
        print("processRtpPacketAndGetNalUnit(data.size=\(data.count), length=\(length), marker=\(marker))")
        //let fuIndicator = data[0]
        //let fuHeader = data[1]
        
        //print("fuIndicator: \(fuIndicator), fuHeader: \(fuHeader)")
        
        // & 연산 : 1 & 1 = 1. 그 외는 다 0
        let nalType = data[0] & 0x1F // Fu Indicator의 3~8 번째 bit (0x1F 0001 1111)
        let packFlag = Int(data[1] & 0xC0) // Fu header의 1, 2번째 bit (0xC0 1100 0000)
        var nalUnit: [UInt8] = []
        
        print("NAL type: \(getH264NalUintTypeString(nalType)), pack flag: 0x\(String(format: "%02X", packFlag))")
        
        switch nalType {
        case VideoCodecUtils.NAL_STAP_A, VideoCodecUtils.NAL_STAP_B:
            break // not supported
        case VideoCodecUtils.NAL_MTAP16, VideoCodecUtils.NAL_MTAP24:
            break // not supported
        case VideoCodecUtils.NAL_FU_A:
            switch packFlag {
            case 0x80: // 1000 0000, 첫 비트가 1이므로 start flag
                addStartFragmentedPacket(data: data, length: length)
            case 0x00: // 0000 0000
                if marker {
                    nalUnit = addEndFragmentedPacketAndCombine(data: data, length: length)
                } else {
                    addMiddleFragmentedPacket(data: data, length: length)
                }
            case 0x40: // 0100 0000, 두번째 비트가 1이므로 end flag
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
        print("writeNalPrefix0001()")
        super.writeNalPrefix0001(to: &buffer)
        //buffer.replaceSubrange(0..<4, with: [0x00, 0x00, 0x00, 0x01])
    }
    
    override func processSingleFramePacket(data: [UInt8], length: Int) -> [UInt8] {
        print("processSingleFramePacket()")
        return super.processSingleFramePacket(data: data, length: length)
//        var nalUnit = [UInt8](repeating: 0, count: 4 + length)
//        writeNalPrefix0001(to: &nalUnit)
//        nalUnit.replaceSubrange(4..<nalUnit.count, with: data.prefix(length))
//        
//        return nalUnit
    }
    
    private func addStartFragmentedPacket(data: [UInt8], length: Int) {
        print("addStartFragmentedPacket(data.count=\(data.count), length=\(length))")
        
        RtpParser.fragmentedPackets = 0
        RtpParser.fragmentedBufferLength = length - 1
        //fragmentedBuffer[0] = Data(count: fragmentedBufferLength)
        RtpParser.fragmentedBuffer[0] = [UInt8](repeating: 0, count: RtpParser.fragmentedBufferLength)
        
        // data[0] 은 NAL의 중요한 정보 포함 (NAL Type 포함)
        // data[1] 은 Fragmentation Indicator, 원래 NAL Unit 포함함
        // data[0] & 0xE0 -> 원래의 NAL Unit 헤더에서 상위 3bit(sps, pps 정보) 유지
        // data[1] & 0x1F -> FU-A 헤더에서 원래의 NAL 타입 복구
        // 0xE0 : 1110 0000, 0x1F: 0001 1111
        // ----> Fragmented NAL의 첫번째 패킷이 원래의 NAL 헤더를 포함하도록 복원함
        
        // | 연산: 0 | 0 = 0, 그 외는 모두 1
        RtpParser.fragmentedBuffer[0]?[0] = (data[0] & 0xE0) | (data[1] & 0x1F)
        // data[0]의 앞 3bit와 data[1]의 뒤 5bit를 하나로 합쳐서 하나의 byte로 만듦
        print("data[0] & 0xE0:\(data[0] & 0xE0) , data[1] & 0x1F: \(data[1] & 0x1F)")
        RtpParser.fragmentedBuffer[0]?.replaceSubrange(1..<(length - 1), with: data[2..<length])
    }
    
    private func addMiddleFragmentedPacket(data: [UInt8], length: Int) {
        print("addMiddleFragmentedPacket(data.count=\(data.count), length=\(length))")
        
        RtpParser.fragmentedPackets += 1
        if RtpParser.fragmentedPackets >= RtpParser.fragmentedBuffer.count {
            print("Too many middle packets. No NAL FU_A end packet received. Skipped RTP Packet.")
            RtpParser.fragmentedBuffer[0] = nil
        } else {
            RtpParser.fragmentedBufferLength += length - 2
            RtpParser.fragmentedBuffer[RtpParser.fragmentedPackets] = [UInt8](Data(data[2..<length]))
        }
    }
    
    private func addEndFragmentedPacketAndCombine(data: [UInt8], length: Int) -> [UInt8] {
        print("addEndFragmentedPacketAndCombine(data.count=\(data.count), length=\(length)")
        
        guard RtpParser.fragmentedBuffer[0] != nil else {
            print("No NAL FU_A start packet received. Skipped RTP packet.")
            return []
        }
        
        // 최종 NAL 크기 결정 (NAL prefix 0,0,0,1 포함)
        var nalUnit = [UInt8](Data(count:RtpParser.fragmentedBufferLength + length + 2))
        writeNalPrefix0001(to: &nalUnit)
        
        var tmpLen = 4 // prefix 길이
        
        // 모든 조각 모음
        for i in 0..<RtpParser.fragmentedPackets {
            if let fragment = RtpParser.fragmentedBuffer[i] {
                nalUnit.replaceSubrange(tmpLen..<(tmpLen + fragment.count), with: fragment)
                tmpLen += fragment.count
            }
        }
        
        // 마지막 packet의 payload 저장
        nalUnit.replaceSubrange(tmpLen..<(tmpLen + length - 2), with: data[2..<length])
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
    
    private func getH264NalUintTypeString(_ type: UInt8) -> String {
        return "NAL_TYPE_\(type)"
    }
}
