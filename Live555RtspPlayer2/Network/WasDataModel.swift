//
//  WasDataModel.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/21/25.
//

import Foundation

struct MemLoginRequest: Codable {
    let mem_id: String
    let mem_pw: String
    let user_cellphone_no: String
    let user_agent: String
    let push_id: String
}

struct MemLoginResponse: Codable {
    let join_channel: String
    let mem_no: String
    let mem_status: String
    let pw_mod_disp_yn: String
    let session_id: String
}

struct ReqVodRequest: Codable {
    let session_id: String
    let cam_id: String
}

struct NoneResponse: Codable {
    
}

struct CanBeStreamingRequest: Codable {
    let session_id: String
    let mem_no: String
}

struct CanBeStreamingResponse: Codable {
    let camera_count: String
    let nodes: [StreamingInfo]
}

struct StreamingInfo: Codable {
    let cam_id: String
    let stream_ok: String
    let object_id: String
    let cam_model_nm: String
    let cam_nm: String
}

struct GetStreamUrlResponse: Codable {
    let passcode: String
    let url: String
    let ctsip: String
    let ctsport: String
    let csid: String
    let vsid: String
    let sdp: String
    let pps: String
    let sps: String
    let twowayurl: String
}
