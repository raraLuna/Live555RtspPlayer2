//
//  ViewController.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 1/13/25.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet var startRtspBtn: UIView!
    
    var urlHost: String = ""
    var urlPort: Int = 0
    var urlPath: String = ""
    var url: String = ""
    
    //let backgroundQueue = DispatchQueue(label: "com.olivendove.backgroundQueue", qos: .background)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        //let rtspUrl = "rtsp://192.168.0.93:554/test.264"
        let rtspUrl = "rtsp://192.168.0.93:554/SampleVideo_1280x720_30mb_h264_AAC.mkv"
        guard let components = URLComponents(string: rtspUrl) else {
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
        self.url = "rtsp://\(urlHost):\(urlPort)\(urlPath)"
        //print("rtspConnect host: \(self.urlHost), port: \(self.urlPort), path: \(self.urlPath)")
        print("connect to url: \(self.url)")
    }
    
    @IBAction func startRtspHandShake(_ sender: Any) {
        self.startRTSP()
    }
    
    private func startRTSP() {
        DispatchQueue.global(qos: .background).async {
            let rtspClient = RTSPClient(serverAddress: self.urlHost, serverPort: UInt16(self.urlPort), serverPath: self.urlPath, url: self.url)
            
            guard rtspClient.connect() else {
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
            }
            
            var sessionVideo = ""
            var sessionAudio = ""
            var sessionVideoTimeout = 0
            var sessionAudioTimeout = 0
            var uriRtspSetupVideo = ""
            var uriRtspSetupAudio = ""
            var interleaved = ""
            
            for i in 0...1 {
                let track: Track = ((i == 0 ? sdpInfo.videoTrack : sdpInfo.audioTrack) ?? Track())
                //uriRtspSetup = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                if i == 0  {
                    interleaved = "0-1"
                    uriRtspSetupVideo = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                    rtspClient.sendSetup(trackURL: uriRtspSetupVideo, interleaved: interleaved)
                } else  {
                    interleaved = "2-3"
                    uriRtspSetupAudio = rtspClient.getUriForSetup(uriRtsp: self.url, track: track)
                    rtspClient.sendSetup(trackURL: uriRtspSetupAudio, interleaved: interleaved)
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
                    sessionVideoTimeout = Int(setupSessionInfo[1]) ?? 0
                } else {
                    sessionAudio = setupSessionInfo[0]
                    sessionAudioTimeout = Int(setupSessionInfo[1]) ?? 0
                }
            }
            
            if sessionVideo == sessionAudio {
                rtspClient.sendPlay(url: self.url, session: sessionVideo)
                let playResponse = rtspClient.readResponse()
                guard rtspClient.readResponseStatusCode(response: playResponse) == 200 else {
                    return
                }
            } else {
                rtspClient.sendPlay(url: uriRtspSetupVideo, session: sessionVideo)
                var playVideoResponseString = ""
                for _ in 0...4 {
                    playVideoResponseString = rtspClient.readResponse()
                    if playVideoResponseString.contains("200 OK") {
                        break
                    }
                }
                
                rtspClient.sendPlay(url: uriRtspSetupAudio, session: sessionAudio)
                var playAudioResponseString = ""
                for _ in 0...4 {
                    playAudioResponseString = rtspClient.readResponse()
                    if playAudioResponseString.contains("200 OK") {
                        break
                    }
                }
                
                if (playVideoResponseString == "" || playVideoResponseString.starts(with: "$")) ||
                    (playAudioResponseString == "" || playAudioResponseString.starts(with: "$")) {
                    rtspClient.sendTearDown(url: uriRtspSetupVideo, session: sessionVideo)
                    rtspClient.sendTearDown(url: uriRtspSetupAudio, session: sessionAudio)
                    //let videoTeardownResponse = rtspClient.readResponse()
                    //let audioTeardownResponse = rtspClient.readResponse()
                    self.startRTSP()
                }
                
//                rtspClient.sendPlay(url: uriRtspSetupVideo, session: sessionVideo)
//                var playVideoResponseString = ""
//                repeat {
//                    playVideoResponseString = rtspClient.readResponse()
//                } while (playVideoResponseString == "" || playVideoResponseString.starts(with: "$"))
//
//                rtspClient.sendPlay(url: uriRtspSetupAudio, session: sessionAudio)
//                var playAudioResponseString = ""
//                repeat {
//                    playAudioResponseString = rtspClient.readResponse()
//                } while (playAudioResponseString == "" || playAudioResponseString.starts(with: "$"))
                
                
                
                
//                guard rtspClient.readResponseStatusCode(response: videoPlayResponse) == 200 else {
//                    return
//                }
                
                //rtspClient.sendPlay(url: uriRtspSetupAudio, session: sessionAudio)
                //let audioPlayResponse = rtspClient.readResponse()
//                guard rtspClient.readResponseStatusCode(response: audioPlayResponse) == 200 else {
//                    return
//                }
            }
            
            //let playResponse = rtspClient.readResponse()
//            guard rtspClient.readResponseStatusCode(response: playResponse) == 200 else {
//                return
//            }
            //rtspClient.startReceiving()
            
            //rtspClient.sendGetParameter(session: sessionVideo)
            //let getParameterResponse = rtspClient.readResponse()
            //print("getParameterResponse: \(getParameterResponse)")
        }
    }
}

