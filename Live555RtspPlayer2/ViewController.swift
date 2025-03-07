//
//  ViewController.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 1/13/25.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var loginBtn: UIButton!
    @IBOutlet var startRtspBtn: UIView!
    @IBOutlet weak var stopRtspBtn: UIButton!
    
    let wasUrl = WasApiInfo.URL_WAS_USA_DEV
    let userId = "ymchoi@olivendove.com"
    let password = "test531!"
    let viewerId = "test531!"
    let userAgent = "03"
    let pushId = "test531!"
    let camId = "100675"
    var sessionId = ""
    var memNo = ""
    var rtspUrl = ""
    
    var urlHost: String = ""
    var urlPort: Int = 0
    var urlPath: String = ""
    var url: String = ""
    var rtspSession: String = ""
    
    private var rtspClient: RTSPClient?
    private var isRunning = false
    
    let backgroundQueue = DispatchQueue(label: "com.olivendove.backgroundQueue", qos: .background)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        //let rtspUrl = "rtsp://192.168.0.50:554/test.264"
        //let rtspUrl = "rtsp://192.168.0.139:554/SampleVideo_1280x720_30mb_h264_AAC.mkv"
        //let rtspUrl = "rtsp://192.168.0.139:554/TheSimpsonsMovie_1080x800_h264_AAC.mkv"
        //let rtspUrl = "rtsp://192.168.0.50:554/TheSimpsonsMovie_1080x800_h265_AAC.mkv"
        
        
//        guard let components = URLComponents(string: rtspUrl) else {
//            print("Failed to parse RTSP URL")
//            return
//        }
//        guard let host = components.host, let port = components.port else {
//            print("Failed to get host or port")
//            return
//        }
//        let filePath = components.path
//
//        self.urlHost = host
//        self.urlPort = port
//        self.urlPath = filePath
//        self.url = "rtsp://\(urlHost):\(urlPort)\(urlPath)"
//        //print("rtspConnect host: \(self.urlHost), port: \(self.urlPort), path: \(self.urlPath)")
//        print("connect to url: \(self.url)")
    }
    
    func processError(apiError: ApiError) {
        switch apiError {
        case .invalidUrl:
            NSLog("invalidUrl")
        case .inputJsonDecodingError:
            NSLog("inputJsonDecodingError")
        case .nsUrlError(let error):
            NSLog("nsUrlError: \(error)")
        case .invalidHttpResponse:
            NSLog("invalidHttpResponse")
        case .httpError(let httpErrorcode):
            NSLog("httpError: \(httpErrorcode)")
        case .wasError(let wasErrorCode):
            NSLog("wasError: \(wasErrorCode)")
        case .noDataReceived:
            NSLog("noDataReceived")
        case .responseJsonDecodingError:
            NSLog("responseJsonDecodingError")
        }
    }
    
    @IBAction func startRtspHandShake(_ sender: Any) {
        self.startRTSP()
    }
    
    @IBAction func login(_ sender: Any) {
        let id = userId
        let pw = password
        let viewerId = viewerId
        let userAgent = userAgent
        let pushId = pushId
        
        backgroundQueue.async {
            WasApi.login(id: id, password: pw, viewerId: viewerId, userAgent: userAgent, pushId: pushId) { result in
                switch result {
                case .success(let response):
                    print("Response: \(response)")
                    self.sessionId = response.sessionId
                    self.memNo = response.memNo
                    NSLog("sessionId \(self.sessionId) memNo \(self.memNo)")
                    self.reqVod()
                case .failure(let apiError):
                    print("ApiError: \(apiError)")
                    self.processError(apiError: apiError)
                }
            }
        }
    }
    
    func reqVod() {
        let sessionId = sessionId
        let camId = camId

        backgroundQueue.async {
            WasApi.reqVod(sessionId: sessionId, camId: camId) { result in
                switch result {
                case .success(let response):
                    print("Response: \(response)")
                    NSLog("success reqVod")
                    self.canBeStreaming(retryCount: 3)
                case .failure(let apiError):
                    print("ApiError: \(apiError)")
                    self.processError(apiError: apiError)
                }
            }
        }
    }

    func canBeStreaming(retryCount: Int = 0) {
        let sessionId = sessionId
        let memNo = memNo
        let camId = camId

        backgroundQueue.async {
            WasApi.canBeStreaming(sessionId: sessionId, memNo: memNo, camId: camId) { result in
                switch result {
                case .success(let response):
                    print("Response: \(response)")
                    if response {
                        NSLog("can be streaming")
                        self.getStreamUrl()

                    } else {
                        NSLog("cannot be streaming")
                        if retryCount > 0 {
                            let count = retryCount - 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.canBeStreaming(retryCount: count)
                            }
                        }
                    }
                case .failure(let apiError):
                    print("ApiError: \(apiError)")
                    self.processError(apiError: apiError)
                }
            }
        }
    }

    func getStreamUrl() {
        let sessionId = sessionId
        let camId = camId
        
        backgroundQueue.async {
            WasApi.getStreamUrl(sessionId: sessionId, camId: camId) { result in
                switch result {
                case .success(let response):
                    print("Response: \(response)")
                    self.rtspUrl = response
                    NSLog("rtspUrl \(self.rtspUrl)")
                    guard let components = URLComponents(string: self.rtspUrl) else {
                        print("Failed to parse RTSP URL")
                        return
                    }
                    guard let host = components.host, let port = components.port else {
                        print("Failed to get host or port")
                        return
                    }
                    let filePath = components.path

                    self.urlHost = host
                    self.urlPort = port
                    self.urlPath = filePath
                    self.url = "rtsp://\(self.urlHost):\(self.urlPort)\(self.urlPath)"
                    //print("rtspConnect host: \(self.urlHost), port: \(self.urlPort), path: \(self.urlPath)")
                    print("connect to url: \(self.url)")
                    
                case .failure(let apiError):
                    print("ApiError: \(apiError)")
                    self.processError(apiError: apiError)
                }
            }
        }
    }

    // MARK: RTSP
    func getUriForSetup(uriRtsp: String, request: String) -> String {
        var uriRtspSetup = uriRtsp
        if request.starts(with: "rtsp://") || request.starts(with: "rtsps://") {
           uriRtspSetup = request
        } else {
            if request.starts(with: "/") {
                uriRtspSetup = uriRtspSetup + request
            } else {
                uriRtspSetup = uriRtspSetup + "/" + request
            }
        }
        return uriRtspSetup
    }
    
    @IBAction func stopRtsp(_ sender: Any) {
        DispatchQueue.global(qos: .background).async {
            guard let rtspClient = self.rtspClient, self.isRunning else {
                return
            }
            self.isRunning = false
            
            rtspClient.stopReceivingData()
            
            rtspClient.sendTearDown(session: self.rtspSession, userAgent: self.userAgent)
            let tearDownResponse = rtspClient.readResponse()
            print("TEARDOWN Response: \(tearDownResponse)")
            
            guard rtspClient.readResponseStatusCode(response: tearDownResponse) == 200 else {
                return
            }
            
            rtspClient.closeConnection()
            self.rtspClient = nil
            
            
//            let rtspClient = RTSPClient(serverAddress: self.urlHost, serverPort: UInt16(self.urlPort), serverPath: self.urlPath, url: self.url)
//            if !rtspClient.connect() {
//                return
//            }
//            rtspClient.sendTearDown(session: self.rtspSession, userAgent: self.userAgent)
//            let tearDownResponse = rtspClient.readResponse()
//            print("TEARDOWN Response: \(tearDownResponse)")
//            
//            guard rtspClient.readResponseStatusCode(response: tearDownResponse) == 200 else {
//                return
//            }
//            rtspClient.closeConnection()
        }
    }
    
    private func startRTSP() {
        DispatchQueue.global(qos: .background).async {
            //let rtspClient = RTSPClient(serverAddress: self.urlHost, serverPort: UInt16(self.urlPort), serverPath: self.urlPath, url: self.url)
            self.rtspClient = RTSPClient(serverAddress: self.urlHost, serverPort: UInt16(self.urlPort), serverPath: self.urlPath, url: self.url)
            
            guard let rtspClient = self.rtspClient else {
                return
            }
            
            // 스트리밍 시작 플래그 설정
            self.isRunning = true
            
            guard rtspClient.connect() else {
                self.isRunning = false
                return
            }

            // 중간에 stop 요청이 들어오면 종료
            if !self.isRunning {
                self.stopRtsp(self)
                return
            }
            
            rtspClient.sendOption()
            let optionResponse = rtspClient.readResponse()
            guard rtspClient.readResponseStatusCode(response: optionResponse) == 200 else {
                return
            }
            let optionHeaders = rtspClient.readResponseHeaders(response: optionResponse)
            print("optionHeaders: \(optionHeaders)")
            let capabilities = rtspClient.getSupportedCapabilities(headers: optionHeaders)
            print("capabilities: \(capabilities)")
            print("\(Capablility.RTSP_CAPABILITY_GET_PARAMETER & capabilities)")
            
            rtspClient.sendDescribe()
            let describeResponse = rtspClient.readResponse()
            guard rtspClient.readResponseStatusCode(response: describeResponse) == 200 else {
                return
            }
            let describeHeaders = rtspClient.readResponseHeaders(response: describeResponse)
            let contentLength = rtspClient.getHeaderContentLength(headers: describeHeaders)
            
            var sdpInfo = SdpInfo()
            if contentLength > 0 {
                let params = rtspClient.getDescribeParams(response: describeResponse)
                sdpInfo = rtspClient.getSdpInfoFromDescribeParams(params: params)
                print("sdpInfo: \(sdpInfo)")
                print("SPS: \([UInt8](sdpInfo.videoTrack?.sps ?? Data()))")
                print("PPS: \([UInt8](sdpInfo.videoTrack?.pps ?? Data()))")
            }
            
            var sessionVideo = ""
            //var sessionAudio = ""
            //var sessionVideoTimeout = 0
            //var sessionAudioTimeout = 0
            var uriRtspSetupVideo = ""
            var uriRtspSetupAudio = ""
            var interleaved = ""
            
            for i in 0...1 {
                let track: Track = ((i == 0 ? sdpInfo.videoTrack : sdpInfo.audioTrack) ?? Track())
                //uriRtspSetup = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                if i == 0  {
                    if sdpInfo.videoTrack != nil {
                        interleaved = "0-1"
                        uriRtspSetupVideo = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                        rtspClient.sendSetup(trackURL: uriRtspSetupVideo, interleaved: interleaved)
                    } else {
                        print("Video track not found in SDP")
                        continue
                    }
                } else  {
                    if sdpInfo.audioTrack != nil {
                        interleaved = "2-3"
                        uriRtspSetupAudio = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                        rtspClient.sendSetup(trackURL: uriRtspSetupAudio, interleaved: interleaved)
                    } else {
                        print("Audio track not found in SDP")
                        break
                    }
                }
                
                //rtspClient.sendSetup(trackURL: uriRtspSetup, interleaved: interleaved)
                let setupResponse = rtspClient.readResponse()
                guard rtspClient.readResponseStatusCode(response: setupResponse) == 200 else {
                    return
                }
                
                let setupHeaders = rtspClient.readResponseHeaders(response: setupResponse)
                let setupSessionInfo = rtspClient.getSessionInfo(headers: setupHeaders)

                if i == 0 {
                    sessionVideo = setupSessionInfo[0]
                    //sessionVideoTimeout = Int(setupSessionInfo[1]) ?? 0
                } else {
                    //sessionAudio = setupSessionInfo[0]
                    //sessionAudioTimeout = Int(setupSessionInfo[1]) ?? 0
                }

            }
            self.rtspSession = sessionVideo
            rtspClient.sendPlay(session: sessionVideo)
            
            DispatchQueue.global(qos: .background).async {
                rtspClient.startReceivingData(sdpInfo: sdpInfo)
            }
        }
    }
}

