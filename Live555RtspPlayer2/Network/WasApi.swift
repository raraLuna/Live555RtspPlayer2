//
//  WasApi.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/21/25.
//

import Foundation

class WasApi {
    struct LoginInfo {
        let sessionId: String
        let memNo: String
    }
    
    static func login(id: String, password: String, viewerId: String, userAgent: String, pushId: String, completion: @escaping (Result<LoginInfo, ApiError>) -> Void) {
        NSLog(#function)

        let client = HTTPClient()
        let wasUrl = WasApiInfo.URL_WAS_USA_DEV
        let url = wasUrl + WasApiInfo.URL_WAS_MEM_LOGIN
        let interfaceId = WasApiInfo.INTERFACE_ID_MEM_LOGIN
        let request = MemLoginRequest(mem_id: id,
                                  mem_pw: password,
                                  user_cellphone_no: viewerId,
                                  user_agent: userAgent,
                                  push_id: pushId)

        client.sendPostRequest(urlString: url, interfaceId: interfaceId, requestBody: request, responseType: MemLoginResponse.self) { result in
            switch result {
            case .success(let response):
                print("Response: \(response)")
                NSLog("sessionId \(response.session_id) memNo \(response.mem_no)")
                let loginInfo = LoginInfo(sessionId: response.session_id, memNo: response.mem_no)
                completion(.success(loginInfo))
            case .failure(let apiError):
                print("ApiError: \(apiError)")
                completion(.failure(apiError))
            }
        }
    }

    static func reqVod(sessionId: String, camId: String, completion: @escaping (Result<Bool, ApiError>) -> Void) {
        NSLog(#function)
        
        let client = HTTPClient()
        let wasUrl = WasApiInfo.URL_WAS_USA_DEV
        let url = wasUrl + WasApiInfo.URL_CCTV_WAS_REQ_VOD
        let interfaceId = WasApiInfo.INTERFACE_ID_REQ_VOD
        let request = ReqVodRequest(session_id: sessionId,
                                    cam_id: camId)

        client.sendPostRequest(urlString: url, interfaceId: interfaceId, requestBody: request, responseType: NoneResponse.self) { result in
            switch result {
            case .success(let response):
                print("Response: \(response)")
                completion(.success(true))
            case .failure(let apiError):
                print("ApiError: \(apiError)")
                completion(.failure(apiError))
            }
        }
    }

    static func canBeStreaming(sessionId: String, memNo: String, camId: String, completion: @escaping (Result<Bool, ApiError>) -> Void) {
        NSLog(#function)
        
        let client = HTTPClient()
        let wasUrl = WasApiInfo.URL_WAS_USA_DEV
        let url = wasUrl + WasApiInfo.URL_CCTV_WAS_CAN_BE_STREAMING
        let interfaceId = WasApiInfo.INTERFACE_ID_CAN_BE_STREAMING
        let request = CanBeStreamingRequest(session_id: sessionId,
                                            mem_no: memNo)
        
        client.sendPostRequest(urlString: url, interfaceId: interfaceId, requestBody: request, responseType: CanBeStreamingResponse.self) { result in
            switch result {
            case .success(let response):
                print("Response: \(response)")
                for info in response.nodes {
                    if info.cam_id == camId && info.stream_ok == "Y" {
                        NSLog("cam_id \(info.cam_id) stream_ok \(info.stream_ok)")
                        completion(.success(true))
                        return
                    }
                }
                NSLog("not ready streaming")
                completion(.success(false))
            case .failure(let apiError):
                print("ApiError: \(apiError)")
                completion(.failure(apiError))
            }
        }
    }

    static func getStreamUrl(sessionId: String, camId: String, completion: @escaping (Result<String, ApiError>) -> Void) {
        NSLog(#function)
        
        let client = HTTPClient()
        let wasUrl = WasApiInfo.URL_WAS_USA_DEV
        let url = wasUrl + WasApiInfo.URL_CCTV_WAS_GET_STREAM_URL + WasApiInfo.INTERFACE_ID_GET_STREAM_URL + "/" + sessionId + "/" + camId
        let interfaceId = WasApiInfo.INTERFACE_ID_GET_STREAM_URL
        
        client.sendGetRequest(urlString: url, interfaceId: interfaceId, responseType: GetStreamUrlResponse.self) { result in
            switch result {
            case .success(let response):
                print("Response: \(response)")
                completion(.success(response.url))
            case .failure(let apiError):
                print("ApiError: \(apiError)")
                completion(.failure(apiError))
            }
        }
    }
}
