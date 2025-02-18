//
//  ViewController.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 1/13/25.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet var startRtspBtn: UIView!
    @IBOutlet weak var stopRtspBtn: UIButton!
    
    var urlHost: String = ""
    var urlPort: Int = 0
    var urlPath: String = ""
    var url: String = ""
    var rtspSession: String = ""
    
    //let backgroundQueue = DispatchQueue(label: "com.olivendove.backgroundQueue", qos: .background)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        //let rtspUrl = "rtsp://192.168.0.50:554/test.264"
        //let rtspUrl = "rtsp://192.168.0.50:554/SampleVideo_1280x720_30mb_h264_AAC.mkv"
        let rtspUrl = "rtsp://192.168.0.74:554/TheSimpsonsMovie_1080x800_h264_AAC.mkv"
        //let rtspUrl = "rtsp://192.168.0.50:554/TheSimpsonsMovie_1080x800_h265_AAC.mkv"
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
    
    @IBAction func stopRtsp(_ sender: Any) {
        DispatchQueue.global(qos: .background).async {
            let rtspClient = RTSPClient(serverAddress: self.urlHost, serverPort: UInt16(self.urlPort), serverPath: self.urlPath, url: self.url)
            if !rtspClient.connect() {
                return
            }
            rtspClient.sendTearDown(url: self.url, session: self.rtspSession)
            let tearDownResponse = rtspClient.readResponse()
            print("tearDownResponse: \(tearDownResponse)")
            
            guard rtspClient.readResponseStatusCode(response: tearDownResponse) == 200 else {
                return
            }
            rtspClient.closeConnection()
        }
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
            rtspClient.sendPlay(url: self.url, session: sessionVideo)
            
            rtspClient.startReceivingData()
        }
    }
}

