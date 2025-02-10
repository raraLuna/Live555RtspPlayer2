//
//  RTSPClient.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 1/13/25.
//

import Foundation

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

class Track {
    var request: String = ""
    var payloadType: Int = -1
}

class VideoTrack: Track {
    var videoCodec: Int = 0
    var sps: Data?
    var pps: Data?
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
    static let VIEEO_CODEC_H265 = 1
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
            //print("Unrecognize data received")
            print("...")
            return ""
        }
    }
    
    /*
    func check4byteOfBuffer(buffer: [UInt8]) -> ([UInt8], [UInt8]) {
        print("\ncheck4byteOfBuffer START")
        print("buffer: \(buffer)")
        print("buffer.count: \(buffer.count)")
        print("rtpLength: \(self.rtpLength)")
        print("remainedRtpBytes: \(self.requisiteRtpBytes)")
        var bytesForParsing: [UInt8] = []
        var remainedBytes: [UInt8] = []
        var accumulateBufferBytes: [UInt8] = []

        //print("check4byteOfBuffer buffer: \(buffer)")
        //print("check4byteOfBuffer buffer.count: \(buffer.count)")
        for i in 0...buffer.count {
            let readByte = buffer[i]
            
            if readByte == 0x24 { // $로 시작하는 경우
                print("----$ START----")
                let firstByteString = String(bytes: [readByte], encoding: .utf8)
                print("buffer[i]: \(String(describing: firstByteString))") // 36 ($)
                let channel = buffer[i+1]
                print("channel: \(channel)")
                let lengthBytes = Array(buffer[i+2..<i+4])
                print("lengthBytes: \(lengthBytes)")
                let lengthInt = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
                self.rtpLength = lengthInt
                print("length: \(lengthInt) bytes")
                print("Received RTP packet")
                
                if buffer.count >= lengthInt+4 { // buffer의 길이가 추출할 Length보다 긴 경우
                    print("check 1")
                    if checkDidReceivedAllRTPData(buffer: Array(buffer[i+4..<lengthInt+4]), length: lengthInt) {
                        let dataArray = buffer[i+4..<lengthInt+4]
                        let remainArray = buffer[lengthInt+4..<buffer.count]
                        bytesForParsing = Array(dataArray)
                        remainedBytes = Array(remainArray)
                        
                        print("dataArray: \(dataArray)")
                        print("dataArray.count: \(dataArray.count)")
                        return (bytesForParsing, remainedBytes)
                    } else {
                        print("data check: \(Array(buffer[i+4..<lengthInt+4]))")
                        return (bytesForParsing, remainedBytes)
                    }
                } else { // buffer 길이가 추출해야할 length 보다 짧은 경우 (RTP 데이터 짤림)
                    print("check 2")
                    let dataArray = buffer[i+4..<buffer.count]
                    bytesForParsing = Array(dataArray)
                    print("dataArray: \(dataArray)")
                    print("dataArray.count: \(dataArray.count)")
                    guard self.isZeroBuffer(buffer: Array(dataArray)) == false else {
                        print("dataArray is fill with zero")
                        return (bytesForParsing, remainedBytes)
                    }
                    self.requisiteRtpBytes = self.rtpLength - dataArray.count
                    print("remainedRtpBytes: \(self.requisiteRtpBytes)")
                    self.accumulateBuffer.append(contentsOf: dataArray)
                    accumulateBufferBytes = [UInt8](self.accumulateBuffer)
                    return (bytesForParsing, remainedBytes)
                }
                
            } else {
                print("----NO $ START----")
                if buffer[i..<i + 4] == [82, 84, 83, 80] { // RTSP Data인 경우
                    print("check 3")
                    guard let dataArray = self.extractUntilCRLF(buffer: buffer) else {
                        return (bytesForParsing, remainedBytes)
                    }
                    let remainArray = buffer[dataArray.count..<buffer.count]
                    bytesForParsing = Array(dataArray)
                    remainedBytes = Array(remainArray)
                    let dataString = String(bytes: bytesForParsing, encoding: .utf8)
                    print("bytesForParsing:\n\(String(describing: dataString))")
                    return (bytesForParsing, remainedBytes)
                } else { // RTSP 규격이 아니고 RTP header도 아닌 숫자 값이 도착함
                     // 그 외의 경우 (아주 희박한 확률로 발생해야함)
                    if self.requisiteRtpBytes != 0 {
                        print("check 4")
                        print("rtpLength: \(self.rtpLength)")
                        print("remainedRtpBytes: \(self.requisiteRtpBytes)")
                        self.accumulateBuffer.append(contentsOf: buffer[i..<self.requisiteRtpBytes])
                        print("read rtp bytes : \(self.accumulateBuffer)")
                        print("is read all rtp data?: \(self.accumulateBuffer.count == self.rtpLength)")
                        accumulateBufferBytes = [UInt8](self.accumulateBuffer)
                        print("accumulateBufferBytes: \(accumulateBufferBytes)")
                        remainedBytes = Array(buffer[self.requisiteRtpBytes..<buffer.count])
                        print("remainedBytes: \(remainedBytes)")
                        self.accumulateBuffer = Data()
                        self.requisiteRtpBytes = 0
                        self.rtpLength = 0
                        return (bytesForParsing, remainedBytes)
                    } else {
                        print("check 5")
                        print(" here !!!")
                        print("rtpLength: \(self.rtpLength)")
                        print("remainedRtpBytes: \(self.requisiteRtpBytes)")
                        
                        guard self.isZeroBuffer(buffer: buffer) == false else {
                            print("This is zero Buffer.")
                            break
                        }
                        remainedBytes = self.findDollarInBufer(buffer: buffer)
                        return (bytesForParsing, remainedBytes)
                    }
                    
                    
//                    let remainArray = buffer[i + 1..<buffer.count]
//                    remainedBytes = Array(remainArray)
//                    if remainArray.allSatisfy( { $0 == 0 }) {
//                        remainedBytes = []
//                    }
                    
                    return (bytesForParsing, remainedBytes)
                }
            }
        }
        print("check 6")
        return (bytesForParsing, remainedBytes)
    }
     */
    
    func checkIsResponseOrRtp(buffer: [UInt8]) -> [UInt8]{
        print("\ncheckIsResponseOrRtp START")
        print("checkIsResponseOrRtp Buffer: \n\(buffer)")
        print("buffer.count: \(buffer.count)")
        //print("rtpLength: \(self.rtpLength)")
        print("requisiteRtpBytes: \(self.requisiteRtpBytes)")
        var remainingBytes: [UInt8] = []
        for i in 0...buffer.count {
            let readByte = buffer[i]
            
            if readByte == 0x24 { // $인 경우
                print("----$ START----")
                let headerBytes = Array(buffer[i..<i+4])
                print("Header byte: \(headerBytes)")
                let lengthBytes = Array(buffer[i+2..<i+4])
                print("lengthBytes: \(lengthBytes)")
                let lengthInt = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
                self.rtpLength = lengthInt
                print("length: \(lengthInt) bytes")
                print("Received RTP packet")
                
                if buffer.count >= lengthInt+4 { // buffer의 길이가 추출할 Length보다 긴 경우
                    print("check 1: received RTP data all")
                    guard self.checkDidReceivedAllRTPData(buffer: Array(buffer[i+4..<lengthInt+4]), length: lengthInt) else
                    {
                        print("checkDidReceivedAllRTPData() return false")
                        return []
                        
                    }
                    //let dataArray = Array(buffer[i+4..<lengthInt+4])
                    //print("dataArray: \n\(dataArray)")
                    self.requisiteRtpBytes = 0
                    
                    remainingBytes = Array(buffer[lengthInt+4..<buffer.count])
                    return remainingBytes
                    
                } else { // buffer 길이가 추출해야할 length 보다 짧은 경우 (RTP 데이터 짤림)
                    print("check 2: received RTP data slice")
                    let dataArray = Array(buffer[i..<buffer.count])
                    print("dataArray: \n\(dataArray)")
                    guard self.isZeroBuffer(buffer: Array(dataArray)) == false else {
                        print("dataArray is fill with zero")
                        return []
                    }
                    
                    print("self.rtpLength: \(self.rtpLength)")
                    print("dataArray.count - 4: \(dataArray.count - 4)")
                    //self.checkDataBuffer.append(contentsOf: dataArray)
                    self.requisiteRtpBytes = self.rtpLength - (dataArray.count - 4)
                    print("requisiteRtpBytes: \(self.requisiteRtpBytes)")
                    return dataArray
                }
            } else { // $가 아닌 경우
                print("----NO $ START----")
                if buffer[i..<i + 4] == [82, 84, 83, 80] { // RTSP Data인 경우
                    print("check 3: RTSP Response received")
                    guard let dataArray = self.extractUntilCRLF(buffer: buffer) else {
                        print("Failed to find [13, 10, 13, 10]")
                        return []
                    }
                    let rtspResponseString = String(bytes: Array(dataArray), encoding: .utf8)
                    print("RTSP Response: \n\(String(describing: rtspResponseString))")
                    
                    remainingBytes = Array(buffer[dataArray.count..<buffer.count])
                    self.rtpLength = 0
                    return remainingBytes
                    
                } else { // RTSP 규격이 아니고 RTP header도 아닌 숫자 값이 도착함
                    guard self.requisiteRtpBytes != 0 else {
                        print("check 5: CHECK WHAT HAPPEN IN BUFFER")
                        guard self.isZeroBuffer(buffer: buffer) == false else {
                            print("This is zero Buffer.")
                            return []
                        }
                        print("rtpLength: \(self.rtpLength)")
                        print("requisitedRtpBytes: \(self.requisiteRtpBytes)")
                        return []
                    }
                    print("check 4: requistedData received")
                    print("rtpLength: \(self.rtpLength)")
                    print("requisitedRtpBytes: \(self.requisiteRtpBytes)")
                    //self.checkDataBuffer.append(contentsOf: buffer[i..<self.requisiteRtpBytes-1])
                    print("read rtp bytes : \n\(self.checkDataBuffer)")
                    print("is read all rtp data? \(self.checkDataBuffer.count == self.rtpLength)")
                    
                    remainingBytes = Array(buffer[self.requisiteRtpBytes..<buffer.count])
                    
                    self.checkDataBuffer = []
                    self.requisiteRtpBytes = 0
                    self.rtpLength = 0
                    
                    //remainingBytes = Array(buffer[self.requisiteRtpBytes..<buffer.count])
                    return remainingBytes
                }
            }
        }
        return []
    }
    
    func checkDidReceivedAllRTPData(buffer: [UInt8], length: Int) -> Bool {
        guard self.isZeroBuffer(buffer: buffer) == false else {
            print("this buffer fill with zero")
            return false
        }
        
        if buffer.count == length {
            return true
        } else if buffer.count < length {
            return false
        }
        
        return false
    }
    
    func isZeroBuffer(buffer: [UInt8]) -> Bool {
        var isZeroBuffer = false
        var zeroCount = 0
        
        for byte in buffer {
            //print("byte: \(byte), zerocount: \(zeroCount)")
            if byte == 0 { // 0이 등장하면
                zeroCount += 1 // zeroCount를 올린다
                if zeroCount >= 9 { // zeroCount가 9개 이상이면
                    isZeroBuffer = true //buffer에 0이 많음
                    break // for문 탈출함
                }
            } else { // 0 등장하지 않으면
                if zeroCount > 0 { // 이전 byte가 0이었을 경우
                    zeroCount = 0 // zeroCount를 0로 리셋
                    isZeroBuffer = false
                }
            }
        }
        return isZeroBuffer
    }
    
    func findDollarInBufer(buffer: [UInt8]) -> [UInt8] {
        var bytesStartWithDollar: [UInt8] = []
        
        for i in 0...buffer.count {
            if buffer[i] == 0x24 {
                bytesStartWithDollar = Array(buffer[i..<buffer.count])
                break
            }
        }
        
        return bytesStartWithDollar
    }
    
    /*
    func readPlayResponse(buffer: [UInt8]){
        var buffer = [UInt8](repeating: 0, count: MAX_LINE_SIZE)
        let bytesRead = Darwin.recv(self.socket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            print("Failed to read response or connection closed.")
            return
        }
        print("\n--readResponse bytesRead: \(bytesRead)--")
        //print("buffer.count: \(buffer.count)")
        //print("buffer: \(buffer)")
        
        var dataArray: ([UInt8], [UInt8]) = ([], [])
        var parsingData: [UInt8] = []
        var retryCheckData: [UInt8] = []
        
        dataArray = check4byteOfBuffer(buffer: buffer)
        parsingData = dataArray.0
        retryCheckData = dataArray.1
        //print("parsingData:\n\(parsingData)")
        //print("retryCheckData:\n\(retryCheckData)")
        //print("retryCheckData.count:\n\(retryCheckData.count)")
        
        let dataString = String(bytes: parsingData, encoding: .utf8)
        //print("data:\n\(String(describing: dataString))")
        print("retryCheckData.count:\(retryCheckData.count)")
        
        repeat {
            if retryCheckData.isEmpty == true {
                break
            }
            dataArray = check4byteOfBuffer(buffer: retryCheckData)
            parsingData = dataArray.0
            retryCheckData = dataArray.1
            
            let dataString = String(bytes: parsingData, encoding: .utf8)
            print("data:\n\(String(describing: dataString))")
            print("retryCheckData.count:\(retryCheckData.count)")
            
            /*
            if retryCheckData[0..<4] == [82, 84, 83, 80]{
                parsingData = check4byteOfBuffer(buffer: retryCheckData).0
                retryCheckData = check4byteOfBuffer(buffer: retryCheckData).1
                let dataString = String(bytes: parsingData, encoding: .utf8)
                print("rtsp data:\n\(parsingData))")
                //print("rtsp data.count:\(parsingData.count)")
                //print("retryCheckData:\n\(retryCheckData))")
                //print("retryCheckData.count:\(retryCheckData.count)")
            }
            
            if retryCheckData[0] == 0x24 {
                parsingData = check4byteOfBuffer(buffer: retryCheckData).0
                retryCheckData = check4byteOfBuffer(buffer: retryCheckData).1
                //print("data:\n\(parsingData))")
                //print("data.count:\(parsingData.count)")
                //print("retryCheckData:\n\(retryCheckData))")
                //print("retryCheckData.count:\(retryCheckData.count)")
            }
             */
        } while retryCheckData.count > 0
        
//        if retryCheckData.isEmpty {
//            print("retryCheckData is empty")
//        }
        
//        let firstByte = buffer[0]
//        if firstByte == 0x24 {
//            let firstByteString = String(bytes: [firstByte], encoding: .utf8)
//            let channel = buffer[1]
//            let lengthBytes = Array(buffer[2..<4])
//            print("lengthBytes: \(lengthBytes)")
//            let lengthInt = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
//            print("buffer[0]: \(String(describing: firstByteString))") // 36 ($)
//            print("channel: \(channel)")
//            print("length: \(lengthInt) bytes")
//            print("Received RTP packet")
//            let dataArray = buffer[4..<lengthInt+4]
//            print("dataArray: \(Array(dataArray))")
//            print("dataArray type: \(type(of: Array(dataArray)))")
//            let dataString = String(bytes: buffer[4..<lengthInt+4], encoding: .utf8)
//            print("data: \(String(describing: dataString))")
//            
//            print("buffer[lengthInt+4]: \(buffer[lengthInt+4])")
//            if buffer[lengthInt+4] != 0 {
//                guard let response = extractUntilCRLF(buffer: Array(buffer[lengthInt+4..<buffer.count])) else {
//                    return ""
//                }
//                print("response: \(response)")
//                print("responseString:\n\(String(bytes: response, encoding: .utf8))")
//            }
//            return ""
//        } else if let response = extractUntilCRLF(buffer: Array(buffer[0..<buffer.count])) {
//            print("response: \(response)")
//            let responseString = String(bytes: response, encoding: .utf8)
//            print("responseString:\n\(responseString)")
//            return responseString ?? ""
//        } else {
//            //print("Unrecognize data received")
//            print("...")
//            return ""
//        }
    }
     
    
    func startReceiving() {
        //DispatchQueue.global(qos: .background).async {
            var buffer = [UInt8](repeating: 0, count: self.MAX_LINE_SIZE)
            while true {
                let bytesRead = Darwin.recv(self.socket, &buffer, buffer.count, 0)
                guard bytesRead > 0 else {
                    print("Connection closed or error occurred")
                    break
                }
                self.readPlayResponse(buffer: buffer)
                //self.parseResponseOrRTP(buffer: buffer, bytesRead: bytesRead)
            }
        //}
    }
     */
    
    
    /*
    func startReceivingData() {
        print("startReceivingData()")
        //DispatchQueue.global().async { [weak self] in
            //guard let self = self else { return }
            //print("DispatchQueue.global()")
            while true {
                var buffer = [UInt8](repeating: 0, count: self.MAX_LINE_SIZE/2)
                let bytesRead = Darwin.recv(self.socket, &buffer, buffer.count, 0)
                
                guard bytesRead > 0 else {
                    print("Connection closed or error occurred")
                    break
                }
                print("\n--readResponse bytesRead: \(bytesRead)--")
                
                //let copiedBuffer = buffer
                //print("ReceivingData buffer: \n\([UInt8](buffer))")
                
                /*
                self.dataQueue.async(flags: .barrier) {
                    self.dataBuffer.append(Array(buffer[0..<bytesRead]))
                    //print("dataBuffer: \(self.dataBuffer)")
                    print("dataBuffer count: \(self.dataBuffer.count)")
                }
                self.startParsingData()
                 */
                
                
                // accumulateBuffer에 안전하게 데이터 추가
                //self.dataQueue.async(flags: .barrier) {
                    self.accumulateBuffer.append(contentsOf: buffer[0..<bytesRead])
                    //self.dataAvailable.signal() // 새로운 데이터가 있음을 알림
                //}
                //print("ReceivingData accumulateBuffer: \(accumulateBuffer.count) \n\([UInt8](accumulateBuffer))")
                self.parsingDataQueue.sync {
                    self.startParsingData()
                }
            //}
        }
    }
    
    func startParsingData() {
        print("startParsingData()")
        //DispatchQueue.global().async { [weak self] in
            //guard let self = self else { return }
            
            //while true {
                
                // 데이터가 들어올 때까지 대기함
                //self.dataAvailable.wait()
                
                /*
                var checkData: [UInt8]?
                
                self.dataQueue.sync {
                    if self.dataBuffer.isEmpty {
                        checkData = self.dataBuffer.removeFirst()
                        print("checkData: \(String(describing: checkData))")
                    }
                }
                print("checkData: \(String(describing: checkData))")
                
                guard let data = checkData else {
                    usleep(100)
                    continue
                }
                
                self.parsingDataQueue.async {
                    let parsingData = self.checkIsResponseOrRtp(buffer: data)
                    print("parsingData: \(parsingData)")
                }
                 */
                
                print("accumulateBuffer.count: \(self.accumulateBuffer.count)")
                print("checkDataBuffer.count: \(self.checkDataBuffer.count)")
                //print("rtpLength: \(self.rtpLength)")
                print("requisiteRtpBytes: \(self.requisiteRtpBytes)")
        
                guard self.checkDataBuffer.count == 0 else {
                    if self.requisiteRtpBytes != 0 {
                        //print("0..<self.requisiteRtpBytes: 0..<\(self.requisiteRtpBytes)")
                        print("accumulateBuffer: \n\([UInt8](self.accumulateBuffer))")
                        let bytes = self.requisiteRtpBytes + (self.rtpLength + 4)
                        print("0..<self.requisiteRtpBytes: 0..<\(bytes)")
                        let dataArray = Array(self.accumulateBuffer[0..<bytes])
                        self.checkDataBuffer.append(contentsOf: dataArray)
                        self.accumulateBuffer.removeFirst(bytes)
                    }
                    self.checkDataBuffer = self.checkIsResponseOrRtp(buffer: [UInt8](self.checkDataBuffer))
                    //print("checkDataBuffer 1: \n\(self.checkDataBuffer)")
                    return
                }
                
                // 일정 크기만큼 데이터를 추출하고 accumulateBuffer를 조정
//                if self.requisiteRtpBytes != 0 {
//                    print("self.accumulateBuffer[0..<self.requisiteRtpBytes]: \([UInt8](self.accumulateBuffer[0..<self.requisiteRtpBytes]))")
//                    checkDataBuffer = Array(self.accumulateBuffer[0..<self.requisiteRtpBytes])
//                    self.accumulateBuffer.removeFirst(self.requisiteRtpBytes)
//                } else if self.requisiteRtpBytes == 0 {
                    if self.accumulateBuffer.count >= 4096 {
                        print("accumulateBuffer: \n\([UInt8](self.accumulateBuffer))")
                        let dataArray = Array(self.accumulateBuffer[0..<4096])
                        self.checkDataBuffer.append(contentsOf: dataArray)
                        self.accumulateBuffer.removeFirst(4096)
                    } else {
                        let dataArray = Array(self.accumulateBuffer)
                        self.checkDataBuffer.append(contentsOf: dataArray)
                        self.accumulateBuffer.removeAll()
                    }
                //}

                    
                // 데이터 파싱
                //self.parsingDataQueue.async {
                    //repeat {
                        if self.checkDataBuffer.isEmpty {
                            print("parsingData is Empty")
                            //break
                        }
                        
                        self.checkDataBuffer = self.checkIsResponseOrRtp(buffer: [UInt8](self.checkDataBuffer))
                        //print("checkDataBuffer 2: \n\(self.checkDataBuffer)")
                    //} while self.checkDataBuffer.count > 0
                //}
            //}
        //}
    }
     
     */
    
    func startReceivingData() {
        while true {
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
                
                var rtpBuffer = [UInt8](repeating: 0, count: lengthInt)
                bytesRead = Darwin.recv(self.socket, &rtpBuffer, lengthInt, 0)
                print("received all data? \(lengthInt == bytesRead)")
                if lengthInt == bytesRead {
                    print("read rtpBuffer: \(rtpBuffer)")
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
    
    func extractAndShift(from data: inout Data, range: Range<Data.Index>) -> Data {
        let extractedData = data.subdata(in: range)
        
        data.removeSubrange(range)
        
        return extractedData
    }
    
    
    func extractUntilCRLF(buffer: [UInt8]) -> [UInt8]? {
        let targetSequence: [UInt8] = [13, 10, 13, 10]
        let targetLength = targetSequence.count
        
        for i in 0...(buffer.count - targetLength) {
            if Array(buffer[i..<i + targetLength]) == targetSequence {
                return Array(buffer[0..<i + targetLength])
            }
        }
        
        return nil
    }
    
    func parseResponseOrRTP(buffer: [UInt8], bytesRead: Int) {
        self.accumulateBuffer.append(contentsOf: buffer[0..<bytesRead])
        print("\n--parseResponseOrRTP bytesRead: \(bytesRead)--")
        
        
        if buffer[0] >= 0x80 && buffer[0] <= 0xBF {
            print("Received RTP packet")
            
        } else if let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            print("Received response:\n\(response)")
        } else {
            //print("Unrecognize data received")
            print("...")
        }
        
        
//        
//        if buffer[0] == 0x24 { // // RTP/TCP 패킷의 Magic Byte (0x24, '$')
//            self.handleRTPPacket()
//        } else {
//            self.handleRTSPResponse()
//        }
         
    }
    
    func handleRTSPResponse() {
        guard let responseRange = accumulateBuffer.range(of: Data([13, 10, 13, 10])) else {
            print("Invaild RTSP Response")
            return // RTSP 응답이 완전하지 않음
        }
        
        let responseData = accumulateBuffer.subdata(in: 0..<responseRange.upperBound)
        accumulateBuffer.removeSubrange(0..<responseRange.upperBound)
        //print("responseData: \(responseData)")
        
        if let responseString = String(data: responseData, encoding: .utf8) {
            print("Received RTSP response:\n\(responseString)")
            if responseString.contains("200 OK") {
                print("RTSP request was successful")
            }
        } else {
            print("Failed to decode RTSP response")
        }
    }
    
    func handleRTPPacket() {
        while accumulateBuffer.count >= 12 {
            let firstByte = accumulateBuffer[0]
            //print("firstByte: \(firstByte)")
            
            // RTP 헤더에서 첫 번째 바이트는 8비트로 표현됨
            // 0x80: 1000 0000, 0xBF: 1011 1111
            guard firstByte >= 0x80 && firstByte <= 0xBF else {
                print("This is not an RTP Packet")
                return
            }
            
            guard accumulateBuffer.count >= 4 else {
                print("Insufficient data for RTP length")
                return
            }
            
            let payloadLength = Int(accumulateBuffer[2]) << 8 | Int(accumulateBuffer[3])
            
            guard accumulateBuffer.count >= payloadLength + 4 else {
                print("RTP packet not fully received yet")
                return
            }
            
            let rtpPacket = accumulateBuffer[0..<(4 + payloadLength)]
            accumulateBuffer.removeSubrange(0..<(4 + payloadLength))
            
            parseRTPPacket(Array(rtpPacket))
        }
    }
    
//    func parseResponseOrRTP(buffer: [UInt8], bytesRead: Int) {
//        self.accumulateBuffer.append(buffer, count: bytesRead)
//        print("--bytesRead: \(bytesRead)--")
//        if let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
//            print("Received response:\n\(response)")
//        }
//        // RTSP 응답이 완전한지 확인 (응답이 \r\n으로 끝나는가)
//        if let responseRange = accumulateBuffer.range(of: Data([13, 10, 13, 10])) {
//            let responseData = accumulateBuffer.subdata(in: 0..<responseRange.upperBound)
//            print("responseData: \(responseData)")
//            accumulateBuffer.removeSubrange(0..<responseRange.upperBound)
//            if let responseString = String(data: responseData, encoding: .utf8) {
//                print("Received RTSP response:\n\(responseString)")
//            } else {
//                print("Failed to decode RTSP response.")
//            }
//        }
//        
//        while accumulateBuffer.count >= 12 { // RTP 헤더 최소 크기
//            let firstByte = accumulateBuffer[0]
//            print("firstByte: \(firstByte)")
//            if firstByte >= 0x80 && firstByte <= 0xBF {
//                parseRTPPacket(Array(accumulateBuffer))
//                accumulateBuffer.removeFirst(12) // RTP 헤더 제거
//            } else {
//                print("this is not RTP Packet")
//                break
//            }
//        }
//    }
        
    func parseRTPPacket(_ data: [UInt8]) {
        guard data.count >= 12 else {
            print("Invaild RTP packet")
            return
        }
        // 비트 연산자
        // &: 대응되는 비트가 모두 1이면 1 반환, 그 외 0 반환 (AND)
        // |: 대응되는 비트 중 하나라도 1이면 1 반환, 그 외 0 반환 (OR)
        // ^: 대응되는 비트가 서로 다르면 1 반환, 그 외 0 반환 (XOR)
        // ~: 비트를 1이면 0으로, 0이면 1로 반전 (NOT)
        // <<: 지정한 수 만큼 비트들을 왼쪽으로 이동 (left shift)
        // >>: 부호를 유지하면서 지정한 수 만큼 비트 오른쪽 이동 (right shift)
        
        let version = (data[0] >> 6) & 0x03
        let payloadType = data[1] & 0x7F
        let sequenceNumber = UInt16(data[2]) << 8 | UInt16(data[3])
        let timestamp = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        
        print("RTP Packet - Version: \(version), Payload Type: \(payloadType), Sequence Number: \(sequenceNumber), Timestamp: \(timestamp)")
        
    }
    
    //func validateRTPPAcket(_ packet: [UInt8]) -> Bool {
        // 1. 최소 패킷 길이 확인 (RTP 헤더 크기: 12바이트)
        
        // 2. RTP 버전 확인 (첫 번째 바이트의 상위 2비트가 0b10이어야함
        
        // 3. CSRC Count 확인 (첫 번째 바이트 하위 4비트
        
        // 4. 확장 헤더 확인 (X 비트가 설정된 경우)
        
        // 5. 패
    //}
    
    // consuming : 값을 복사하거나 참조를 전달하는 방식을 사용하지 않도록 하여 메모리 성능 최적화함
    consuming func closeConnection() {
        if socket >= 0 {
            Darwin.close(socket)
            print("Socket closed\n")
        }
    }
    
    func sendKeepAlive() {
        guard let session = self.session else { return }
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
    
    func sendPlay(url: String, session: String) {
        var request = ""
        request += "PLAY \(url) RTSP/1.0\(self.CRLF)"
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
    
    func sendTearDown(url: String, session: String) {
        var request = ""
        request += "TEARDOWN \(url) RTSP/1.0\(self.CRLF)"
        request += "Session: \(session)\(self.CRLF)"
        request += "CSeq: \(self.cSeq)\(self.CRLF)"
        request += "\(self.CRLF)"
        
        sendRequest(request)
        self.cSeq += 1
    }
}

extension RTSPClient {
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
                let sessionInfo = headers[i].1.split(separator: ";")
                sessionString = String(sessionInfo[0])
                sessionTimeout = String(sessionInfo[1].split(separator: "=")[1])
                sessionInfoArr.append(sessionString)
                sessionInfoArr.append(sessionTimeout)
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
                    if values.count > 1 {
                        let codecDetails = values[1].split(separator: "/")
                        if let videoTrack = track as? VideoTrack {
                            switch codecDetails[0].lowercased() {
                            case "h264":
                                videoTrack.videoCodec = Codec.VIDEO_CODEC_H264
                            case "h265":
                                videoTrack.videoCodec = Codec.VIEEO_CODEC_H265
                            default:
                                print("Unknown video codec \(codecDetails[0])")
                            }
                            print("Video: \(codecDetails[0])")
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
        
        for param in params {
            if param.0.lowercased() == "scrop-parameter-sets" {
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
                    nalSps.append(sps)
                    
                    var nalPps = Data([0x00, 0x00, 0x00, 0x01]) // 00 00 00 01
                    nalPps.append(pps)
                    
                    // Setting VideoTrack
                    videoTrack.sps = nalSps
                    videoTrack.pps = nalPps
                }
            }
        }
    }
    
    func updateAudioTrackFromDescribeParam(audioTrack: AudioTrack, param: (String, String)) {
        guard let params = getSdpParams(param: param) else {
            return
        }
        
        for param in params {
            switch param.0.lowercased() {
            case "mode":
                audioTrack.mode = param.1
            case "config":
                audioTrack.config = getBytesFromHexString(hexString: param.1)
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
    
    //maek SdpInfo object from sdp information
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
    
    func readRtpData() {
        
    }
}
