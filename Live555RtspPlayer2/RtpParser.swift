//
//  RtpParser.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/13/25.
//

import Foundation

class RtpParser {
    // RTP 패킷 처리하고 NAL Unit을 반환하는 추상 메서드
    func processRtpPacketAndGetNalUnit(data: [UInt8], length: Int, marker: Bool) -> [UInt8]? {
        fatalError("Subclasses must override this method")
    }
    
    // TODO: 미리 할당된 버퍼 사용 (RtpPacket.MAX_SIZE = 65507)
    // 단편화 된 패킷을 저장하는 버퍼
    var fragmentedBuffer: [[UInt8]?] = Array(repeating: nil, count: 1024)
    var fragmentedBufferLength: Int = 0
    var fragmentedPacket: Int = 0
    
    // NAL Unit 앞에 00 00 00 01 prefix를 추가하는 함수
    func writeNalPrefix0001(to buffer: inout [UInt8]) {
        guard buffer.count >= 4 else { return }
        buffer[0] = 0x00
        buffer[1] = 0x00
        buffer[2] = 0x00
        buffer[3] = 0x01
    }
    
    // 단일 프레임 RTP 패킷을 처리하여 NAL Unit으로 변환하는 함수
    func precessSingleFramePacket(data: [UInt8], length: Int) -> [UInt8] {
        var nalUnit = [UInt8](repeating: 0, count: 4 + length)
        writeNalPrefix0001(to: &nalUnit)
        nalUnit.replaceSubrange(4..<nalUnit.count, with: data.prefix(length))
        
        return nalUnit
    }
}
