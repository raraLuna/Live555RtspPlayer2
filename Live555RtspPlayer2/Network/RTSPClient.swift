//
//  RTSPClient.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 1/13/25.
//

import Foundation
import CoreMedia

struct Capablility {
    static let RTSP_CAPABILITY_NONE = 0
    static let RTSP_CAPABILITY_OPTIONS = 1 << 1 // 2
    static let RTSP_CAPABILITY_DESCRIBE = 1 << 2 // 4
    static let RTSP_CAPABILITY_ANNOUNCE = 1 << 3 // 8
    static let RTSP_CAPABILITY_SETUP = 1 << 4 // 16
    static let RTSP_CAPABILITY_PLAY = 1 << 5 // 32
    static let RTSP_CAPABILITY_RECORD = 1 << 6 // 64
    static let RTSP_CAPABILITY_PAUSE = 1 << 7 // 128
    static let RTSP_CAPABILITY_TEARDOWN = 1 << 8 // 256
    static let RTSP_CAPABILITY_SET_PARAMETER = 1 << 9 // 512
    static let RTSP_CAPABILITY_GET_PARAMETER = 1 << 10 // 1024
    static let RTSP_CAPABILITY_REDIRECT = 1 << 11 // 2048
}
// x << y : x의 비트열을 왼쪽으로 y만큼 이동시키며 이동에 따른 빈 공간은 0으로 채움
// x >> y: x의 비트열을 오른쪽으로 y만큼 이동시키며 이동에 따른 빈 공간은 처음 정수의 최상위 부호비트와 같은 값으로 채워진다

struct SdpInfo {
    var videoTrack: VideoTrack?
    var audioTrack: AudioTrack?
    var sessionName: String = ""
    var sessionDescription: String = ""
}

//  0                   1                   2                   3
//  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |V=2|P|X|  CC   |M|     PT      |       sequence number         |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                           timestamp                           |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |           synchronization source (SSRC) identifier            |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |            Contributing source (CSRC) identifiers             |
// |                             ....                              |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |  header eXtension profile id  |       length in 32bits        |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                          Extensions                           |
// |                             ....                              |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |                           Payload                             |
// |             ....              :  padding...                   |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |               padding         | Padding size  |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

struct RtpHeader {
    var version: Int = 0
    var padding: Int = 0
    var extensionBit: Int = 0
    var cc: Int = 0
    var marker: Int = 0
    var payloadType: Int = 0
    var sequenceNumber: UInt16 = 0
    var timeStamp: UInt32 = 0
    var ssrc: UInt32 = 0
    var payloadSize: Int = 0
}

struct videoDecodingInfo {
    static var codec: Int = 0
    static var sps: Data = Data()
    static var pps: Data = Data()
    static var vps: Data = Data()
}

class Track {
    var request: String = ""
    var payloadType: Int = -1
}

class VideoTrack: Track {
    var videoCodec: Int = 0
    var sps: Data?
    var pps: Data?
    var vps: Data? // H.265의 경우
}

class AudioTrack: Track {
    var audioCodec: Int = -1
    var sampleRateHz: Int = 0
    var channels: Int = 1
    var mode: String = ""
    var config: [UInt8] = []
}

enum Codec {
    static let VIDEO_CODEC_H264 = 0
    static let VIDEO_CODEC_H265 = 1
    static let AUDIO_CODEC_AAC = 0
    static let AUDIO_CODEC_UNKNOWN = -1
}

class RTSPClient {
    private var socket: Int32 = -1
    private var serverAddress: String
    private var serverPort: UInt16
    private var serverPath: String
    private var url: String
    private var session: String? = ""
    private let CRLF: String = "\r\n"
    private var cSeq: Int = 1
    private let MAX_LINE_SIZE = 4096
    private var accumulateBuffer = Data()
    private var checkDataBuffer: [UInt8] = []
    private var dataBuffer = [[UInt8]]() // safity buffer
    private var requisiteRtpBytes = 0
    private var rtpLength = 0
    private let dataQueue = DispatchQueue(label: "com.odc.dataQueue", attributes: .concurrent) // 동시성 제어용 Queue
    private let parsingDataQueue = DispatchQueue(label: "com.odc.parsingDataQueue", attributes: .concurrent)
    private let dataAvailable = DispatchSemaphore(value: 0) // 데이터 사용 신호
    
    private let video264Queue = ThreadSafeQueue<Data>()
    private let video265Queue = ThreadSafeQueue<(data: Data, rtpTimestamp: UInt32, nalType: UInt8)>()
    private let audioQueue = ThreadSafeQueue<Data>()
    //private let semaphore = DispatchSemaphore(value: 1)
    
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private var audioDumpData: [UInt8] = []
    
    private var audioMode: String = ""
    //private var sdpAudioPT: Int = 0
    //private var sdpVideoPT: Int = 0
    
    private let RTP_HEADER_SIZE = 12
    
    private var encodeType = ""
    private var videoHz = 0
    private var previousTimestamp: UInt32 = 0
    private var estimatedFPS: UInt32 = 0
    
    private var isRunning = false
    //private let audioDecoder = AudioDecoder(formatID: kAudioFormatMPEG4AAC, useHardwareDecode: false)
    //private let h264Decoder = H264Decoder()
    //private let pcmPlayer = PCMPlayer()
    private let convertYUVToRGB = YUVNV12toRGB()
    
    //private var pcmData: [UInt8] = []
    private var pcmData: [[UInt8]] = []
    private let audioDecodeQueue = DispatchQueue(label: "com.odc.audioDecodeQueue", attributes: .concurrent)
    
    init(serverAddress: String, serverPort: UInt16 = 554, serverPath: String, url: String) {
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.serverPath = serverPath
        self.url = url
    }
    
    func connect() -> Bool {
        //create socket
        self.socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard self.socket >= 0 else {
            print("Failed to create socket")
            return false
        }
        
        // Resolve server address
        var serverAddr = sockaddr_in()
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = in_port_t(self.serverPort).bigEndian
        serverAddr.sin_addr.s_addr = inet_addr(self.serverAddress)
        print("Server Address: \(serverAddr.sin_addr.s_addr)")
        print("Server Port: \(serverAddr.sin_port.bigEndian)")


        //print("serverAddr: \(serverAddr)")
        
        // Connect to server
        let result = withUnsafePointer(to: &serverAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(self.socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        print("result: \(result)")
        
        
        guard result >= 0 else {
            print("Failed to connect to server")
            if result == -1 {
                print("Connection failed. Error: \(String(describing: strerror(errno))) (\(errno))")
            }
            Darwin.close(self.socket)
            return false
        }
        
        print("Connected to \(self.serverAddress):\(self.serverPort)")
        return true
    }
    
    deinit {
        Darwin.close(self.socket)
    }
    
    func sendRequest(_ request: String) {
        print("\nSend request:\n\(request)")
        guard self.socket >= 0 else {
            print("Socket is not connected.")
            return
        }
        
        guard let data = request.data(using: .utf8) else {
            print("Failed to get request data.")
            return
        }
        data.withUnsafeBytes {
            _ = Darwin.send(socket, $0.baseAddress, data.count, 0)
        }
    }
    
    func readResponse() -> String {
        var buffer = [UInt8](repeating: 0, count: MAX_LINE_SIZE)
        let bytesRead = Darwin.recv(self.socket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            print("Failed to read response or connection closed.")
            return ""
        }
        print("\n--readResponse bytesRead: \(bytesRead)--")
        
        if buffer[0] >= 0x80 && buffer[0] <= 0xBF {
            print("Received RTP packet")
            return ""
        } else if let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            print("Received response:\n\(response)")
            return response
        } else {
            print("Unrecognize data received")
            return ""
        }
    }
    
    // consuming : 값을 복사하거나 참조를 전달하는 방식을 사용하지 않도록 하여 메모리 성능 최적화함
    consuming func closeConnection() {
        if socket >= 0 {
            Darwin.close(socket)
            print("Socket closed\n")
        }
    }
    
    func sendKeepAlive() {
        //guard let session = self.session else { return }
        var request = ""
        request += ""
    }
    
    func sendOption() {
        var request = ""
        request += "OPTIONS \(self.url) RTSP/1.0\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
    
    func sendDescribe() {
        var request = ""
        request += "DESCRIBE \(self.url) RTSP/1.0\(self.CRLF)"
        request += "Accept: application/sdp\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(self.CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
    
    func sendSetup(trackURL: String, interleaved: String) {
        var request = ""
        request += "SETUP \(trackURL) RTSP/1.0\(self.CRLF)"
        request += "Transport: RTP/AVP/TCP;unicast;interleaved=\(interleaved)\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(self.CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
    
    func sendPlay(session: String) {
        var request = ""
        request += "PLAY \(self.url) RTSP/1.0\(self.CRLF)"
        request += "Range: npt=0.000-\(self.CRLF)"
        request += "Session: \(session)\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(self.CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
    
    func sendGetParameter(session: String) {
        var request = ""
        request += "GET_PARAMETER \(self.url) RTSP/1.0\(self.CRLF)"
        request += "Session: \(session)\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
    
    func sendTearDown(session: String, userAgent: String) {
        var request = ""
        request += "TEARDOWN \(self.url) RTSP/1.0\(self.CRLF)"
        //request += "User-Agent: \(userAgent)\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "Session: \(session)\(self.CRLF)"
        request += "\(self.CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
}

extension RTSPClient {
    
    func stopReceivingData() {
        self.isRunning = false
        closeConnection()
    }
    
    func startReceivingData(sdpInfo: SdpInfo) {
        DispatchQueue.global(qos: .userInitiated).async {
            print("[Thread] startReceivingData thread: \(Thread.current)")
            self.isRunning = true
            
            while self.isRunning {
                let timestamp = DebugLog.currentTimeString()
                print("startReceivingData timestampt: \(timestamp)")
                // 1byte 만큼 데이터 읽기
                var oneByteBuffer = [UInt8](repeating: 0, count: 1)
                var threeByteBuffer = [UInt8](repeating: 0, count: 3)
                var saveBuffer: [UInt8] = []
                var bytesRead = Darwin.recv(self.socket, &oneByteBuffer, 1, 0)
                
                guard bytesRead > 0 else {
                    print("Connection closed or error occurred")
                    break
                }
                
                print("\nread 1byte: \(oneByteBuffer)")
                
                if oneByteBuffer[0] == 0x24 { // $ 도착
                    print("----$ START----")
                    bytesRead = Darwin.recv(self.socket, &threeByteBuffer, 3, 0)
                    let channel = threeByteBuffer[0]
                    let lengthBytes = Array(threeByteBuffer[1..<3])
                    let lengthInt = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
                    print("channel: \(channel)")
                    print("read rtp length byte: \(lengthBytes)")
                    print("length: \(lengthInt) bytes")
                    print(threeByteBuffer[0] == 0 ? "RTP Packet" : "RTCP Packet")
                    
                    var rtpBuffer = [UInt8](repeating: 0, count: lengthInt)
                    bytesRead = self.readData(socket: self.socket, buffer: &rtpBuffer, offset: 0, length: lengthInt)
                    if bytesRead > 0 {
                        print("Received Data: \(bytesRead) bytes")
                    } else {
                        print("Failed to read data")
                    }
                    
                    guard !rtpBuffer.isEmpty else {
                        print("RTP buffer is empty")
                        return
                    }
                    
                    let rtpHeader = self.readHeader(from: rtpBuffer, packetSize: lengthInt)
                    let rtpPacket = Array(rtpBuffer[12...])
                    
                    let payloadType = rtpHeader.payloadType
                    if payloadType >= 96 && payloadType <= 127 {
                        print("This is Dynamic payload type. Need SDP Information")
                        print("spdInfo.videoTrack.payloadType: \(String(describing: sdpInfo.videoTrack?.payloadType))")
                        print("spdInfo.audioTrack.payloadType: \(String(describing: sdpInfo.audioTrack?.payloadType))")
                        if rtpHeader.payloadType == sdpInfo.videoTrack?.payloadType {
                            self.parseVideo(rtpHeader: rtpHeader, rtpPacket: rtpPacket, sdpInfo: sdpInfo)
                        } else if rtpHeader.payloadType == sdpInfo.audioTrack?.payloadType {
                            self.parseAudio(rtpHeader: rtpHeader, rtpPacket: rtpPacket, sdpInfo: sdpInfo)
                        }
                    } else if payloadType == 0 || payloadType == 8  {
                        print("Audio RTP Packet detected")
                        self.parseAudio(rtpHeader: rtpHeader, rtpPacket: rtpPacket, sdpInfo: sdpInfo)
                    } else if payloadType == 96 || payloadType == 97 {
                        print("Video RTP Packet detected")
                        self.parseVideo(rtpHeader: rtpHeader, rtpPacket: rtpPacket, sdpInfo: sdpInfo)
                    } else {
                        print("Unknown RTP Packet detected")
                    }
                    
                    
                } else {
                    if oneByteBuffer[0] == 0x52 { //"R" 도착
                        saveBuffer.append(oneByteBuffer[0])
                        bytesRead = Darwin.recv(self.socket, &threeByteBuffer, 3, 0)
                        print("read next bytes: \(threeByteBuffer)")
                        if threeByteBuffer[0..<3] == [84, 83, 80]{
                            print("----RTSP response ----")
                            for i in 0..<threeByteBuffer.count {
                                saveBuffer.append(threeByteBuffer[i])
                            }
                            repeat {
                                bytesRead = Darwin.recv(self.socket, &oneByteBuffer, 1, 0)
                                saveBuffer.append(oneByteBuffer[0])
                            } while !saveBuffer.contains([13, 10, 13, 10])
                            print("\(String(describing: String(bytes: Array(saveBuffer), encoding: .utf8)))")
                           
                        }
                    }
                    continue
                }
            }
        }
    }
    
    func parseVideo(rtpHeader: RtpHeader, rtpPacket: [UInt8], sdpInfo: SdpInfo) {
        print("......Video RTP Parsing......")
        print("encodeType: \(self.encodeType)")
        if self.encodeType == "h264" {
            let rtpH264Parser = RtpH264Parser()
            if rtpPacket.count != 0 {
                let nalUnit = rtpH264Parser.processRtpPacketAndGetNalUnit(data: rtpPacket, length: rtpPacket.count, marker: rtpHeader.marker != 0)
                
                let offset = 0
                var spsIndex = 0
                var ppsIndex = 0
                var nalDataIndex = 0
                var prefixSize = 0
                
                if nalUnit.count != 0 {
                    var prefixCount = 0
                    var nalUnitStart = VideoCodecUtils.searchForNalUnitStart(data: nalUnit, offset: offset, length: nalUnit.count, prefixSize: &prefixSize)
                    prefixCount += 1
                    spsIndex = offset + prefixSize
                    print("nalUnitStart\(prefixCount): \(nalUnitStart), prefixSize: \(prefixSize), nalUnit[\(offset + prefixSize)]: \(nalUnit[offset + prefixSize])")
                    
                    
                    if nalUnit[spsIndex] == 103 { // SPS 발견
                        for i in spsIndex..<(nalUnit.count - spsIndex) {
                            if prefixCount == 3 {
                                break
                            }
                            print("nalUnit[i..<i+3]: \(Array(nalUnit[i..<i+4]))")
                            
                            if Array(nalUnit[i..<i+4]) == [0, 0, 0, 1] {
                                nalUnitStart = VideoCodecUtils.searchForNalUnitStart(data: Array(nalUnit[i...]), offset: offset, length: Array(nalUnit[i...]).count, prefixSize: &prefixSize)
                                prefixCount += 1
                                print("nalUnitStart\(prefixCount): \(nalUnitStart), prefixSize: \(prefixSize), nalUnit[\(i + prefixSize)]: \(nalUnit[i + prefixSize])")
                                
                                if nalUnit[i + prefixSize] == 104 { // PPS 발견
                                    ppsIndex = i + prefixSize
                                    if self.sps != Array(nalUnit[0..<(ppsIndex - 4)]) {
                                        self.sps = Array(nalUnit[0..<(ppsIndex - 4)])
                                    }
                                    
                                } else { // SPS, PPS 외의 0,0,0,1 발견 -> nalData
                                    nalDataIndex = i + prefixSize
                                    if self.pps != Array(nalUnit[self.sps.count..<(nalDataIndex - 4)]) {
                                        self.pps  = Array(nalUnit[self.sps.count..<(nalDataIndex - 4)])
                                    }
                                }
                            }
                        }
                    } else {
                        print("here check sdp")
                        self.sps = [UInt8](sdpInfo.videoTrack?.sps ?? Data())
                        self.pps = [UInt8](sdpInfo.videoTrack?.pps ?? Data())
                    }
                    
                    guard self.sps.count != 0 && self.pps.count != 0 else { return }
                    print("sps nalUnit: \(self.sps)")
                    print("pps nalUnit: \(self.pps)")
                    print("nalUnit count: \(nalUnit.count)")
                    print("nalDataIndex: \(nalDataIndex)")
                    videoDecodingInfo.sps = Data(self.sps.dropFirst(4))
                    videoDecodingInfo.pps = Data(self.pps.dropFirst(4))
                    
                    var unitData = Data()
                    if nalDataIndex != 0 {
                        unitData = Data(nalUnit[nalDataIndex - 4..<nalUnit.count])
                        self.video264Queue.enqueue(unitData)
                        print("videoQueue enqueue 1")
                    } else {
                        unitData = Data(nalUnit)
                        self.video264Queue.enqueue(unitData)
                        print("videoQueue enqueue 2")
                    }
                } else {
                }
                
            }
        } else if self.encodeType == "h265" {
            let rtpH265Parser = RtpH265Parser()
            var readyDecode = false
            
            if rtpPacket.count != 0 {
                let nalUnit = rtpH265Parser.processRtpPacketAndGetNalUnit(data: rtpPacket, length: rtpPacket.count, marker: rtpHeader.marker != 0)
                if nalUnit.count != 0 {
                    //print("rtpH265Parser result nalUnit: \(nalUnit)")
                    let header = nalUnit[4]
                    let nalUnitType = (header >> 1) & 0x3F
                    print("rtpH265 nalUnitType: \(nalUnitType)") // UInt8
                    
                    print("videoDecodingInfo.vps isEmpty?: \(videoDecodingInfo.vps.isEmpty)")
                    print("videoDecodingInfo.sps isEmpty?: \(videoDecodingInfo.sps.isEmpty)")
                    print("videoDecodingInfo.pps isEmpty?: \(videoDecodingInfo.pps.isEmpty)")
                    if !videoDecodingInfo.vps.isEmpty &&
                       !videoDecodingInfo.sps.isEmpty &&
                       !videoDecodingInfo.pps.isEmpty {
                        readyDecode = true
                    }
                    
                    switch nalUnitType {
                    case 32:
                        videoDecodingInfo.vps = Data(nalUnit.dropFirst(4))
                    case 33:
                        videoDecodingInfo.sps = Data(nalUnit.dropFirst(4))
                    case 34:
                        videoDecodingInfo.pps = Data(nalUnit.dropFirst(4))
                    case 19, 20:
                        if readyDecode == true {
                            let unitData = Data(nalUnit)
                            self.video265Queue.enqueuePacket(unitData, timestamp: rtpHeader.timeStamp, nalType: nalUnitType)
                            print("videoQueue enqueue 1")
                        } else {
                            break;
                        }
                    case 0, 1, 6:
                            let unitData = Data(nalUnit)
                        self.video265Queue.enqueuePacket(unitData, timestamp: rtpHeader.timeStamp, nalType: nalUnitType)
                            print("videoQueue enqueue 2")
                            break;
//                    case 6:
//                        print("SEI Frame nalType:\(nalUnitType) is skipped")
//                        break;
                    default:
                        break;
                    }
                }
            }
        }
    }
    

    func convertUInt8ToUInt16(_ data: [UInt8]) -> [UInt16] {
        var result: [UInt16] = []
        
        // UInt8 배열을 2바이트씩 묶어서 UInt16 배열로 변환
        for i in stride(from: 0, to: data.count, by: 2) {
            if i + 1 < data.count {
                let value = (UInt16(data[i]) << 8) | UInt16(data[i + 1]) // Big-Endian 변환
                result.append(value)
            }
        }
        
        return result
    }
    
    func parseAudio(rtpHeader: RtpHeader, rtpPacket: [UInt8], sdpInfo: SdpInfo) {
        print("......Audio RTP Parsing......")
        guard sdpInfo.audioTrack != nil else { return }
        
        let hexString = rtpPacket.map { String(format: "0x%02X", $0) }.joined(separator: " ")

        
        var payload = [UInt8]()
        // rtpPacket이 FF로 시작하면 2bytes를 제거하고
        // 그렇지 않으면 1byte를 제거한 뒤 adts header를 만들어 붙임

        if rtpPacket.starts(with: [255]) {
            if rtpPacket.starts(with: [255, 255, 255]) {
                //print("rtpPacket start with FF, FF, FF. remove 4byte")
                payload = Array(rtpPacket.dropFirst(4))
            } else if rtpPacket.starts(with: [255, 255]) {
                //print("rtpPacket start with FF, FF. remove 3byte")
                payload = Array(rtpPacket.dropFirst(3))
            } else {
                //print("rtpPacket start with FF. remove 2byte")
                payload = Array(rtpPacket.dropFirst(2))
            }
        } else {
            //print("rtpPacket start without FF. remove 1byte")
            payload = Array(rtpPacket.dropFirst(1))
        }
        var payloadData = Data()
        
        let sourceData: [UInt8] = payload
        
        payloadData = Data(payload)
        self.audioQueue.enqueue(payloadData)
        
    }
    
    func getVideo264Queue() -> ThreadSafeQueue<Data> {
        return video264Queue
    }
    
    func getVideo265Queue() -> ThreadSafeQueue<(data: Data, rtpTimestamp: UInt32, nalType: UInt8)> {
        return video265Queue
    }

    func getAudioQueue() -> ThreadSafeQueue<Data> {
        return audioQueue
    }
    
    
    
    // inout : 메모리 참조 변수
    //         상수 파라미터를 변수로 사용할 때 inout 사용. (copy in, copy out, 매개변수 복사하여 값 변경 후 다시 원본 변수에 재할당)
    // offset : 데이터를 저장할 버퍼의 시작 위치
    // length : 읽어야 하는 데이터 길이
    func readData(socket: Int32, buffer: inout [UInt8], offset: Int, length: Int) -> Int {
        var totalReadBytes = 0
        
        while totalReadBytes < length {
            let readBytes = Darwin.recv(socket, &buffer[offset + totalReadBytes], length - totalReadBytes, 0)
            if readBytes <= 0 {
                return totalReadBytes
            }
            
            totalReadBytes += readBytes
        }
        return totalReadBytes
    }
    
    func getUriForSetup(uriRtsp: String, track: Track) -> String {
        if track.request.isEmpty {
            return ""
        }
        
        var uriRtspSetup = uriRtsp
        if (track.request.starts(with: "rtsp://") || track.request.starts(with: "rtsps://")) {
            uriRtspSetup = track.request
        } else {
            if (!track.request.starts(with: "/")) {
                track.request = "/" + track.request
            }
            uriRtspSetup += track.request
        }
        
        return uriRtspSetup
    }
    
    func checkStatusCode(code: Int) {
        switch code {
        case 200:
            break
        case 401:
            print("Invalid status code: 401")
        default:
            print("Invalid status code: \(code)")
        }
    }
    
    func readResponseStatusCode(response: String) -> Int {
        let lines = response.split(separator: "\r\n")
        let rtspHeader = "RTSP/1.0 "
        var statusCode = -1
        
        for line in lines {
            if line.starts(with: rtspHeader) {
                statusCode = Int(line.split(separator: " ")[1]) ?? -1
                print("statusCode: \(statusCode)")
                return statusCode
            }
        }
        
        return statusCode
    }
    
    func readResponseHeaders(response: String) -> [(String, String)] {
        let lines = response.split(separator: "\r\n")
        var headers: [(String, String)] = []
        for line in lines {
            if line.contains(":") {
                let key = String(line.split(separator: ":")[0])
                var value = String(line.split(separator: ":")[1])
                if value.starts(with: " ") {
                    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                headers.append((key,value))
            }
        }
        //print("headers: \(headers)")
        return headers
    }
    
    func getSessionInfo(headers: [(String, String)]) -> [String] {
        var sessionInfoArr : [String] = []
        var sessionString = ""
        var sessionTimeout = ""
        
        for i in 0...headers.count-1 {
            if headers[i].0 == "Session" {
                if headers[i].1.contains(";") {
                    let sessionInfo = headers[i].1.split(separator: ";")
                    sessionString = String(sessionInfo[0])
                    sessionTimeout = String(sessionInfo[1].split(separator: "=")[1])
                    sessionInfoArr.append(sessionString)
                    sessionInfoArr.append(sessionTimeout)
                } else {
                    let sessionInfo = headers[i].1.split(separator: " ")
                    sessionString = String(sessionInfo[0])
                    sessionTimeout = String(sessionInfo[1].split(separator: "=")[1])
                    sessionInfoArr.append(sessionString)
                    sessionInfoArr.append(sessionTimeout)
                }
            }
        }
        
        return sessionInfoArr
    }
    
    // parse sdp as key-value
    func getDescribeParams(response: String) -> [(String, String)] {
        var list: [(String, String)] = []
        let params = response.split(separator: "\r\n")
        
        for param in params {
            if let separatorIndex = param.firstIndex(of: "=") {
                let key = String(param[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(param[param.index(after: separatorIndex)...])
                list.append((key, value))
            }
        }
        return list
    }
    
    // parse video track and audio track from sdp
    func getTrackFromDescribeParams(params: [(String, String)]) -> [Track] {
        var tracks = [Track(), Track()]
        var currentTrack = Track()
        
        for param in params {
            switch param.0 {
            case "m":
                if param.1.starts(with: "video") {
                    currentTrack = VideoTrack()
                    tracks[0] = currentTrack
                } else if param.1.starts(with: "audio") {
                    currentTrack = AudioTrack()
                    tracks[1] = currentTrack
                } else {
                    currentTrack = Track()
                }
                let track = currentTrack
                let values = param.1.split(separator: " ")
                track.payloadType = values.count > 3 ? Int(values[3]) ?? -1 : -1
                if track.payloadType == -1 {
                    print("Failed to get payload type from \(param.1)")
                    
                }
            case "a":
                let track = currentTrack
                if param.1.starts(with: "control:") {
                    track.request = String(param.1.dropFirst(8))
                } else if param.1.starts(with: "fmtp:") {
                    if let videoTrack = track as? VideoTrack {
                        updateVideoTrackFromDescribeParam(videoTrack: videoTrack, param: param)
                    } else if let audioTrack = track as? AudioTrack {
                        updateAudioTrackFromDescribeParam(audioTrack: audioTrack, param: param)
                    }
                } else if param.1.starts(with: "rtpmap:") {
                    let values = param.1.split(separator: " ")
                    print("rtpmap values: \(values)")
                    if values.count > 1 {
                        let codecDetails = values[1].split(separator: "/")
                        if let videoTrack = track as? VideoTrack {
                            switch codecDetails[0].lowercased() {
                            case "h264":
                                videoTrack.videoCodec = Codec.VIDEO_CODEC_H264
                                videoDecodingInfo.codec = Codec.VIDEO_CODEC_H264
                            case "h265":
                                videoTrack.videoCodec = Codec.VIDEO_CODEC_H265
                                videoDecodingInfo.codec = Codec.VIDEO_CODEC_H265
                            default:
                                print("Unknown video codec \(codecDetails[0])")
                            }
                            
                            let type = videoTrack.videoCodec == 0 ? "h264" : "h265"
                            self.encodeType = type
                            
                            let payloadType = Int(values[0].split(separator: ":")[1])
                            
                        } else if let audioTrack = track as? AudioTrack {
                            switch codecDetails[0].lowercased() {
                            case "mpeg4-generic", "mp4a-latm":
                                audioTrack.audioCodec = Codec.AUDIO_CODEC_AAC
                            default:
                                print("Unknown audio codec \(codecDetails[0])")
                                audioTrack.audioCodec = Codec.AUDIO_CODEC_UNKNOWN
                            }
                            audioTrack.sampleRateHz = Int(codecDetails[1]) ?? 0
                            audioTrack.channels = codecDetails.count > 2 ? Int(codecDetails[2]) ?? 1 : 1
                            let payloadType = Int(values[0].split(separator: ":")[1])
                            
                            print("Audio: \(audioTrack.audioCodec), sample rate: \(audioTrack.sampleRateHz) Hz, channels: \(audioTrack.channels)")
                            
                        }
                    }
                }
            default:
                break
            }
        }
        return tracks
    }
    
    func updateVideoTrackFromDescribeParam(videoTrack: VideoTrack, param: (String, String)) {
        guard let params = getSdpParams(param: param) else {
            return
        }
        print("sdp params: \(params)")
        print("videoTrack format: \(videoTrack.videoCodec)")
        let videoCodec = videoTrack.videoCodec
        if videoCodec == 0 {
            for param in params {
                if param.0.lowercased() == "sprop-parameter-sets" {
                    let paramsSpsPps = param.1.split(separator: ",")
                    if paramsSpsPps.count > 1 {
                        // Decoding Base64
                        guard let sps = Data(base64Encoded: String(paramsSpsPps[0])),
                              let pps = Data(base64Encoded: String(paramsSpsPps[1])) else {
                            print("Failed to decode Base64 for SPS/PPS")
                            return
                        }
                        
                        // Add NAL Unit header
                        var nalSps = Data([0x00, 0x00, 0x00, 0x01]) // 00 00 00 01
                        //var nalSps = Data()
                        nalSps.append(sps)
                        
                        var nalPps = Data([0x00, 0x00, 0x00, 0x01]) // 00 00 00 01
                        //var nalPps = Data()
                        nalPps.append(pps)
                        
                        // Setting VideoTrack
                        videoTrack.sps = nalSps
                        videoTrack.pps = nalPps
                    }
                }
            }
        } else if videoCodec == 1 {
            for param in params {
                if param.0.lowercased() == "sprop-vps" {
                    let paramsVps = param.1
                    guard let vps = Data(base64Encoded: String(paramsVps)) else {
                        print("Failed to decode Base64 for VPS")
                        return
                    }
                    var nalVps = Data([0x00, 0x00, 0x00, 0x01])
                    nalVps.append(vps)
                    videoTrack.vps = nalVps
                } else if param.0.lowercased() == "sprop-sps" {
                    let paramsSps = param.1
                    guard let sps = Data(base64Encoded: String(paramsSps)) else {
                        print("Failed to decode Base64 for VPS")
                        return
                    }
                    var nalSps = Data([0x00, 0x00, 0x00, 0x01])
                    nalSps.append(sps)
                    videoTrack.sps = nalSps
                } else if param.0.lowercased() == "sprop-pps" {
                    let paramsPps = param.1
                    guard let pps = Data(base64Encoded: String(paramsPps)) else {
                        print("Failed to decode Base64 for VPS")
                        return
                    }
                    var nalPps = Data([0x00, 0x00, 0x00, 0x01])
                    nalPps.append(pps)
                    videoTrack.pps = nalPps
                }
            }
        }
    }
    
    func updateAudioTrackFromDescribeParam(audioTrack: AudioTrack, param: (String, String)) {
        guard let params = getSdpParams(param: param) else {
            return
        }
        print("audio params: \(params)")
        for param in params {
            switch param.0.lowercased() {
            case "mode":
                audioTrack.mode = param.1
                self.audioMode = audioTrack.mode
                
            case "config":
                audioTrack.config = getBytesFromHexString(hexString: param.1)
                print("audioTrack.config: \(audioTrack.config)")
            default:
                break
            }
        }
    }
    
    func getBytesFromHexString(hexString: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var hex = hexString
        
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        
        for i in stride(from: 0, to: hex.count, by: 2) {
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 2)
            let byteString = String(hex[start..<end])
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }
        }
        return bytes
    }
    
    //make SdpInfo object from sdp information
    func getSdpInfoFromDescribeParams(params: [(String, String)]) -> SdpInfo {
        var sdpInfo = SdpInfo()
        let tracks = getTrackFromDescribeParams(params: params)
        
        sdpInfo.videoTrack = tracks[0] as? VideoTrack
        sdpInfo.audioTrack = tracks[1] as? AudioTrack
        
        for param in params {
            switch param.0 {
            case "s":
                sdpInfo.sessionName = param.1
                break
            case "i":
                sdpInfo.sessionDescription = param.1
                break
            default:
                break
            }
        }
        return sdpInfo
    }
    
    func getSdpParams(param: (String, String)) -> [(String, String)]? {
        guard param.0 == "a", param.1.starts(with: "fmtp:"), param.1.count > 8 else {
            print("Not a valid fmtp")
            return nil
        }
        
        let value = param.1.dropFirst(8).trimmingCharacters(in: .whitespaces)
        let paramsA = value.split(separator: ";")
        
        return paramsA.map { paramA in
            let parts = paramA.split(separator: "=", maxSplits: 1)
            return (String(parts[0].trimmingCharacters(in: .whitespaces)), parts.count > 1 ? String(parts[1]) : "")
        }
    }
    
    func extractSessionID(from response: String) -> String? {
        let lines = response.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines {
            if line.hasPrefix("Session") {
                //Session: <ID> 형식에서 ID 추출
                let sessionID = line.replacingOccurrences(of: "Session:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return sessionID
            }
        }
        print("Failed extractSessionID from response.")
        return nil
    }
    
    func readUntilBytesFound(inputStream: InputStream, data: [UInt8]) -> Bool {
        var buffer = [UInt8](repeating: 0, count: data.count)
        
        // buffer 채움
        guard readData(inputStream: inputStream, buffer: &buffer, offset: 0, length: buffer.count) == buffer.count else {
            return false
        }
        
        while true {
            // buffer가 동일한지 확인
            if memcmp(source1: buffer, offsetSource1: 0, source2: data, offsetSource2: 0, num: buffer.count) {
                return true
            }
            
            // ABCDEF -> FEDCBA
            shiftLeftArray(&buffer, num: buffer.count)
            
            // 마지막 버퍼 항목에 1바이트 읽기
            guard readData(inputStream: inputStream, buffer: &buffer, offset: -1, length: 1) == 1 else {
                return false // EOF
            }
        }
        return false
    }
    
    func getHeaderContentLength(headers: [(String, String)]) -> Int {
        let length = getHeader(headers: headers, header: "content-length")
        
        if !length.isEmpty {
            return Int(length) ?? -1
        } else {
            print("header content length is empty")
        }
        return -1
    }
    
    func readContentAsText(inputStream: InputStream, length: Int) -> String {
        guard length > 0 else { return "" }
        
        var buffer = [UInt8](repeating: 0, count: length)
        let bytesRead = readData(inputStream: inputStream, buffer: &buffer, offset: 0, length: length)
        
        return String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
    }
    
    func memcmp(source1: [UInt8], offsetSource1: Int, source2: [UInt8], offsetSource2: Int, num: Int) -> Bool {
        guard source1.count - offsetSource1 >= num else { return false }
        guard source2.count - offsetSource2 >= num else { return false }
        
        for i in 0..<num {
            if source1[offsetSource1 + i] != source2[offsetSource2 + i] {
                return false
            }
        }
        return true
    }
    
    func shiftLeftArray(_ array: inout [UInt8], num: Int) {
        guard num - 1 >= 0 else { return }
        array.replaceSubrange(0..<(num - 1), with: array[1..<num])
    }
    
    func readLine(inputStream: InputStream) -> String {
        var bufferLine = [UInt8](repeating: 0, count: self.MAX_LINE_SIZE)
        var offset = 0
        // offset 이란: 일반적으로 동일한 오브젝트 안에서 오브젝트 처음부터 주어진 요소나 지점까지의 변위차를 나타내는 정수형
        // 예를 들어 abcdef 의 배열A가 있다면 'c'는 A 시작전에서 2의 오프셋을 지닌다. (A[2])
        
        while true {
            // 최대 크기 초과한 경우
            if (offset >= self.MAX_LINE_SIZE) {
                print("No response Header")
            }
            
            // 1바이트 읽기
            let bytesRead = inputStream.read(&bufferLine[offset], maxLength: 1)
            
            if bytesRead == 1 {
                // EOL 확인
                if offset > 0, /* bufferLine[offset - 1] == UInt8(ascii: "\r") && */ bufferLine[offset] == UInt8(ascii: "\n") {
                    //빈 EOL, 헤더 섹션 끝
                    if offset == 1 {
                        return ""
                    }
                    
                    // EOL 발견, 배열로 추가
                    return String(bytes: bufferLine[0..<offset], encoding: .utf8) ?? ""
                } else {
                    offset += 1
                }
            } else if bytesRead <= 0 {
                return ""
            }
        }
    }
    
    func readData(inputStream: InputStream, buffer: inout [UInt8], offset: Int, length: Int) -> Int {
        var totalReadBytes = 0
        
        while totalReadBytes < length {
            let bytesRead = inputStream.read(&buffer[offset + totalReadBytes], maxLength: length - totalReadBytes)
            
            if bytesRead > 0 {
                totalReadBytes += bytesRead
            } else if bytesRead < 0 {
                print("Failed to read Data")
            } else {
                // EOL reached
                break
            }
        }
        return totalReadBytes
    }
    
    func getHeader(headers: [(String, String)], header: String) -> String {
        for head in headers {
            let h: String = head.0.lowercased()
            if header.lowercased() == h {
                return head.1
            }
        }
        return ""
    }
    
    func getSupportedCapabilities(headers: [(String, String)]) -> Int {
        var mask = 0
        for header in headers {
            let h: String = header.0.lowercased()
            if h == "public" {
                let tokens = header.1.lowercased().split(separator: ",")
                for token in tokens {
                    switch token.trimmingCharacters(in: .whitespaces) {
                    case "options":
                        mask = Capablility.RTSP_CAPABILITY_OPTIONS
                        
                    case "describe":
                        mask = Capablility.RTSP_CAPABILITY_DESCRIBE
                        
                    case "announce":
                        mask = Capablility.RTSP_CAPABILITY_ANNOUNCE
                        
                    case "setup":
                        mask = Capablility.RTSP_CAPABILITY_SETUP
                        
                    case "play":
                        mask = Capablility.RTSP_CAPABILITY_PLAY
                        
                    case "record":
                        mask = Capablility.RTSP_CAPABILITY_RECORD
                        
                    case "pause":
                        mask = Capablility.RTSP_CAPABILITY_PAUSE
                        
                    case "teardown":
                        mask = Capablility.RTSP_CAPABILITY_TEARDOWN
                        
                    case "set_parameter":
                        mask = Capablility.RTSP_CAPABILITY_SET_PARAMETER
                        
                    case "get_parameter":
                        mask = Capablility.RTSP_CAPABILITY_GET_PARAMETER;
                        
                    case "redirect":
                        mask = Capablility.RTSP_CAPABILITY_REDIRECT
                        
                    default:
                        mask = 0
                    }
                }
                return mask
            }
        }
        return Capablility.RTSP_CAPABILITY_NONE
    }
    
    func hasCapability(capability: Int, capabilityMask: Int) -> Bool {
        // &: 해당 숫자들의 이진값을 and 연산함
        // 1 and 0 >= 0
        // 0 and 1 >= 0
        // 1 and 1 >= 1
        // 0 and 0 >= 0
        
        // 1 & 1 제외한 모든 and 연산의 결과는 0이므로
        // return 값이 0이 아니도록 나오게 하기 위해서는 1 & 1 연산 즉, 같은 capability의 and 연산이 발생해야함
        // 이 함수는 capabilityMask 와 capalitilty가 같은 값인지 비교하는 함수이다
        return (capabilityMask & capability) != 0
    }
    
    // MARK: read RTP DATA
    
    
    // MARK: Header parsing
    func searchForNextRtpHeader(in header: inout [UInt8]) -> Bool {
        guard header.count >= 4 else { return false }
        
        var bytesRemaining = 100_000 // 최대 100KB search
        var foundFirstByte = false
        var foundSecondByte = false
        var oneByte = [UInt8](repeating: 0, count: 1)
        
        repeat {
            if bytesRemaining <= 0 { return false }
            bytesRemaining -= 1
            
            if readData(socket: self.socket, buffer: &oneByte, offset: 0, length: 1) == 0 {
                return false
            }
            
            if foundFirstByte {
                if oneByte[0] == 0x00 { // 0000 0000 (64)
                    foundSecondByte = true
                } else {
                    foundFirstByte = false
                }
            }
            
            if !foundFirstByte && oneByte[0] == 0x24 {
                foundFirstByte = true
            }
        } while !foundSecondByte
        
        header[0] = 0x24
        header[1] = oneByte[0]
        
        _ = readData(socket: self.socket, buffer: &header, offset: 2, length: 2)
        
        return true
    }
    
    func parseHeaderData(header: [UInt8], packetSize: Int) -> RtpHeader {
        guard header.count >= RTP_HEADER_SIZE else { return RtpHeader() }
        
        // 각 요소의 길이만큼 bit 계산을 하기 위한 비트 연산 과정
        // 예를 들면 1000 0000 (128, 0x80)의 첫 2비트인 10을 계산하기 위해
        //     AND 1100 0000 (192, 0xC0)
        //     ---------------------------
        //         1000 0000
        //              >> 6 shift 연산 하면 오른쪽으로 6칸 이동하고 빈칸 0으로 채움
        //         0000 0010 (2, 0x02) 가 결과로 나온다. version 값
        let version = Int((header[0] & 0xC0) >> 6)
        if version != 2 {
            print("Not an RTP packet version:\(version)")
            return RtpHeader()
        }
        
        let padding = Int((header[0] & 0x20) >> 5)
        let extensionBit = Int((header[0] & 0x10) >> 4)
        let marker = Int((header[1] & 0x80) >> 7)
        let payloadType = Int(header[1] & 0x7F)
        let sequenceNumber = UInt16(header[2]) << 8 | UInt16(header[3])
        
        //        let timeStamp = UInt32(header[4]) << 24 | UInt32(header[5]) << 16 | UInt32(header[6]) << 8 | UInt32(header[7])
        //        let ssrc = UInt32(header[8]) << 24 | UInt32(header[9]) << 16 | UInt32(header[10]) << 8 | UInt32(header[11])
        let timeStamp = (UInt32(header[4]) << 24) | (UInt32(header[5]) << 16) | (UInt32(header[6]) << 8) | UInt32(header[7])
        let ssrc = (UInt32(header[8]) << 24) | (UInt32(header[9]) << 16) | (UInt32(header[10]) << 8) | UInt32(header[11])
        
        let payloadSize = packetSize - RTP_HEADER_SIZE
        
        print("RTP Header:\nversion: \(version)\npadding: \(padding)\nextensionBit: \(extensionBit)\ncc: 0\nmarker: \(marker)\npayloadType: \(payloadType)\nsequenceNumber: \(sequenceNumber)\ntimeStamp: \(timeStamp)\nssrc: \(ssrc)\npayloadSize: \(payloadSize)")
        
        self.calculateFPS(currentTimestamp: timeStamp)
        
        return RtpHeader(
            version: version,
            padding: padding,
            extensionBit: extensionBit,
            cc: 0,
            marker: marker,
            payloadType: payloadType,
            sequenceNumber: sequenceNumber,
            timeStamp: timeStamp,
            ssrc: ssrc,
            payloadSize: payloadSize
        )
    }
    
    func getPacketSize(header: [UInt8]) -> Int {
        // header[2], [3]이 Length
        return (Int(header[2]) << 8) | Int(header[3])
    }
    
    func readHeader(from buffer: [UInt8], packetSize: Int) -> RtpHeader {
        //ex) [128, 96, 182, 130, 128, 143, 149, 35, 198, 217, 29, 15]
        var header = [UInt8](repeating: 0, count: RTP_HEADER_SIZE)
        
        // TCP 에서는 처음 4바이트를 건너뛰고 읽어야함 (처음 4byte rtp header이므로..??)
        //_ = readData(socket: self.socket, buffer: &header, offset: 0, length: 4)
        guard buffer.count >= RTP_HEADER_SIZE else {
            print("buffer is too short to read RTP header")
            return RtpHeader()
        }
        header = Array(buffer[0 ..< RTP_HEADER_SIZE])
        print("RTP Packet Header: \(header)")
        print("packetSize: \(packetSize)")
        
        //        if readData(socket: self.socket, buffer: &header, offset: 0, length: RTP_HEADER_SIZE) == RTP_HEADER_SIZE {
        let rtpHeader = parseHeaderData(header: header, packetSize: packetSize)
        return rtpHeader
        //        }
        //
        //        // 만약 헤더가 존재하지 않으면 Keep-Alive 응답일 가능성 있음 -> 새 RTP 헤더 탐색
        //        if searchForNextRtpHeader(in: &header) {
        //            let newPacketSize = getPacketSize(header: header)
        //            if readData(socket: self.socket, buffer: &header, offset: 0, length: RTP_HEADER_SIZE) == RTP_HEADER_SIZE {
        //                let rtpHeader = parseHeaderData(header: header, packetSize: newPacketSize)
        //                return rtpHeader
        //            }
        //        }
        //return RtpHeader()
    }
    
    func calculateFPS(currentTimestamp: UInt32) {
        let previous = previousTimestamp
        let timestampDiff = currentTimestamp &- previous // &-: overflow 방지 연산자
        print("timestampDiff: \(timestampDiff)")
        if timestampDiff > 0 {
            estimatedFPS = UInt32(90000.0) / timestampDiff
            print("Estimated FPS: \(String(describing: estimatedFPS))")
        }
        
        self.previousTimestamp = currentTimestamp
    }
    
    func processH264RtpPacket(_ rtpPacket: [UInt8]) -> [UInt8] {
        guard rtpPacket.count > 12 else { return [] }
        
        let payload = Array(rtpPacket[12...]) // RTP 헤더(12바이트) 제거
        let nalUnitType = payload[0] & 0x1F // 첫 바이트에서 NAL 유형 추출
        print("nalUnitType: \(nalUnitType)")
        switch nalUnitType {
        case 1...23:
            // 단일 NAL 단위 (Single NALU)
            //return [0x00, 0x00, 0x00, 0x01] + payload
            return payload
        case 24:
            // STAP-A (Single-time Aggregation Packet
            return handleStapA(payload)
        case 28:
            // FU-A (Fragmentation Unit-A
            return handleFuA(payload)
        default:
            return []
        }
    }
    
    // SPS (Sequenese Parameter Set) & PPS(Picture Parameter Set) 같이
    // 작은 데이터 여러 개를 하나의 패킷으로 묶어서 전송하는 경우
    func handleStapA(_ payload: [UInt8]) -> [UInt8] {
        var nalUnits: [UInt8] = []
        var offset = 1 // STAP-A 헤더 건너뛰기
        
        while offset + 2 < payload.count {
            let nalSize = Int(payload[offset]) << 8 | Int(payload[offset + 1]) // NAL 크기
            offset += 2
            if offset + nalSize > payload.count { break }
            //nalUnits.append(contentsOf: [0x00, 0x00, 0x00, 0x01] + payload[offset..<offset+nalSize])
            nalUnits.append(contentsOf: payload[offset..<offset+nalSize])
            offset += nalSize
        }
        
        return nalUnits
    }
    
    // 큰 크기의 NAL Unit(예: Key Frame)을 여러 개의 RTP 패킷으로 쪼개어 전송하는 경우
    func handleFuA(_ payload: [UInt8]) -> [UInt8] {
        let fuIndicator = payload[0] // FU Indicator
        let fuHeader = payload[1] // FU Header
        let startBit = (fuHeader & 0x80) != 0
        //let endBit = (fuHeader & 0x40) != 0
        let nalType = fuHeader & 0x1F
        let nalUnitHeader = (fuIndicator & 0xE0) | nalType
        
        let nalData = Array(payload[2...]) // FU payload
        
        if startBit {
            //return [0x00, 0x00, 0x00, 0x01, nalUnitHeader] + nalData
            return [nalUnitHeader] + nalData
        } else {
            return nalData
        }
    }
    
    func processAacRtpPacket(_ rtpPacket: [UInt8]) -> [UInt8] {
        //guard rtpPacket.count > 12 else { return [] } // RTP 크기 확인
        guard rtpPacket.count > 0 else { return [] } // RTP 크기 확인
        
        //let payload = Array(rtpPacket[12...]) // RTP 헤더 제거
        //let adtsHeader = createAdtsHeader(for: payload.count)
        
        let adtsHeader = createAdtsHeader16000Mono(for: rtpPacket.count)
        
        var adtsHeaderRtpAcc = [UInt8]()
        adtsHeaderRtpAcc.append(contentsOf: adtsHeader)
        adtsHeaderRtpAcc.append(contentsOf: rtpPacket)
        
        // return adtsHeader + rtpPacket
        return adtsHeaderRtpAcc
    }
    
    // https://wiki.multimedia.cx/index.php?title=ADTS
    // https://stackoverflow.com/questions/18862715/how-to-generate-the-aac-adts-elementary-stream-with-android-mediacodec
    // ADTS header
    //        Byte  | Bits               | Description
    //        ------|--------------------|-----------------------------------
    //        0     | 1111 1111         | Syncword (always 0xFFF)
    //        1     | 1111 x xxx        | Syncword + ID + Layer
    //        2     | xx xx x xxx       | Profile + Sampling Frequency Index + Private Bit
    //        3     | x xxx xxxx        | Channel Configuration + Original/Copy + Home
    //        4     | xxxx xxxx         | Frame Length (High)
    //        5     | xxxx xxxx         | Frame Length (Middle) + Buffer Fullness (High)
    //        6     | xxxx xx xx        | Buffer Fullness (Low) + Number of Raw Data Blocks
    
    func createAdtsHeader16000Mono(for aacFrameSize: Int) -> [UInt8] {
        let profile: UInt8 = 2 // AAC Main (0), AAC LC (1), AAC SSR (2), AAC LTP (3)
        let samplingFreqIndex: UInt8 = 0x08 // 16,000 Hz (Table 기준)
        let channelConfig: UInt8 = 0x01 // Mono (1채널)
        
        let fullLength = aacFrameSize + 7 // ADTS + packet 전체 프레임 크기
        
        var adtsHeader = [UInt8](repeating: 0, count: 7)
        
        adtsHeader[0] = 0xFF // Sync word
        adtsHeader[1] = 0xF1 // Sync word
        adtsHeader[2] = ((profile - 1) << 6) | (samplingFreqIndex << 2) | (channelConfig >> 2) // Profile (AAC-LC), (Sampling Freq Index (44.1kHz), Private Bit
        adtsHeader[3] = ((channelConfig & 3) << 6) | UInt8(fullLength >> 11) // Channel config (streo)
        adtsHeader[4] = UInt8((fullLength & 0x7FF) >> 3) // Frame Length (high)
        adtsHeader[5] = ((UInt8(fullLength & 7) << 5) | 0x1F) // Frame Length (low)
        adtsHeader[6] = 0xFC // CRC disabled
        
        print("adtsHeader created: \(adtsHeader)")
        print("ADTS Header: \(adtsHeader.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        
        //parseAdtsHeader(from: Data(adtsHeader))
        return adtsHeader
        
        func getPayloadType(from rtpPacket: [UInt8]) -> Int {
            return Int(rtpPacket[1] & 0x7F) // 2번째 바이트에서 7비트 추출함
        }
        
        func parseAdtsHeader(from data: Data) {
            guard data.count >= 7 else {
                print("❌ 데이터가 ADTS 헤더 크기(7바이트)보다 작음")
                return
            }
            
            let hdr = [UInt8](data.prefix(7))  // ADTS 헤더 (7바이트)
            
            // Syncword 확인 (0xFFF)
            let syncword = (UInt16(hdr[0]) << 4) | (UInt16(hdr[1]) >> 4)
            guard syncword == 0xFFF else {
                print("❌ 잘못된 ADTS 헤더 (Syncword 오류)")
                return
            }
            
            let id = (hdr[1] >> 3) & 0b1  // MPEG Version (0: MPEG-4, 1: MPEG-2)
            let layer = (hdr[1] >> 1) & 0b11  // Layer (항상 0)
            let protectionAbsent = hdr[1] & 0b1  // 1: CRC 없음, 0: CRC 있음
            let profile = (hdr[2] >> 6) & 0b11  // AAC Profile (0: Main, 1: LC, 2: SSR, 3: LTP)
            let samplingFreqIdx = (hdr[2] >> 2) & 0b1111  // 샘플링 주파수 인덱스
            let privateBit = (hdr[2] >> 1) & 0b1  // Private Bit
            let channelConfig = ((hdr[2] & 0b1) << 2) | (hdr[3] >> 6)  // 채널 설정 (1~7)
            let originalCopy = (hdr[3] >> 5) & 0b1  // 원본 여부
            let home = (hdr[3] >> 4) & 0b1  // Home
            
            // 프레임 길이 계산 (13비트)
            let frameLength = ((UInt16(hdr[3] & 0b11) << 11) | (UInt16(hdr[4]) << 3) | (UInt16(hdr[5]) >> 5))
            
            // ADTS 버퍼 충만도 (11비트)
            let adtsBufferFullness = ((UInt16(hdr[5] & 0b1_1111) << 6) | (UInt16(hdr[6]) >> 2))
            
            // Raw Data Blocks 개수 (2비트)
            let numRawDataBlocks = hdr[6] & 0b11
            
            // 로그 출력
            print("🔍 **ADTS Header Parsing**")
            print("🔹 ID: \(id) (\(id == 0 ? "MPEG-4" : "MPEG-2"))")
            print("🔹 Layer: \(layer) (항상 0)")
            print("🔹 Protection Absent: \(protectionAbsent) (\(protectionAbsent == 1 ? "No CRC" : "CRC Present"))")
            print("🔹 Profile: \(profile) (\(aacProfileDescription(Int(profile))))")
            print("🔹 Sampling Frequency Index: 0x\(String(samplingFreqIdx, radix: 16)) (\(samplingFreqHz(Int(samplingFreqIdx))) Hz)")
            print("🔹 Channel Configuration: \(channelConfig) (\(channelConfigDescription(Int(channelConfig))))")
            print("🔹 Frame Length: \(frameLength) bytes")
            print("🔹 ADTS Buffer Fullness: \(adtsBufferFullness)")
            print("🔹 Number of Raw Data Blocks: \(numRawDataBlocks)")
        }
        
        // AAC Profile 설명 함수
        func aacProfileDescription(_ profile: Int) -> String {
            switch profile {
            case 0: return "AAC Main"
            case 1: return "AAC LC (Low Complexity)"
            case 2: return "AAC SSR (Scalable Sample Rate)"
            case 3: return "AAC LTP (Long Term Prediction)"
            default: return "Unknown"
            }
        }
        
        // 샘플링 주파수 인덱스 매핑
        func samplingFreqHz(_ index: Int) -> Int {
            let freqTable = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
            return (index < freqTable.count) ? freqTable[index] : -1
        }
        
        // 채널 설정 설명 함수
        func channelConfigDescription(_ config: Int) -> String {
            let configTable = [
                "Defined in AOT Spec", "Mono", "Stereo", "3.0", "4.0", "5.0", "5.1", "7.1"
            ]
            return (config > 0 && config < configTable.count) ? configTable[config] : "Unknown"
        }
        
    }
}


/*

 RTP header format: https://tools.ietf.org/html/rfc3550#section-5

 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |V=2|P|X|  CC   |M|     PT      |       sequence number         |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                           timestamp                           |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |           synchronization source (SSRC) identifier            |
 +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
 |            contributing source (CSRC) identifiers             |
 |                             ....                              |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

 Header extension: https://tools.ietf.org/html/rfc3550#section-5.3.1

 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |      defined by profile       |           length              |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                        header extension                       |
 |                             ....                              |

 */
    
    
