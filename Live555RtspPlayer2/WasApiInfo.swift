//
//  WasApiInfo.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/21/25.
//

import Foundation

struct WasApiInfo {
    static let URL_WAS_USA_DEV                              = "https://wasdev-usa.remobell.com:8443/HT/WAS"
    static let URL_WAS_USA_KOR                              = "https://wasdev-kor.remobell.com:8443/HT/WAS"
    static let URL_WAS_USA                                  = "https://was-usa.remobell.com:8443/HT/WAS"
    
    static let URL_WAS_MEM_LOGIN                            = "/inf/memInfo/memLogin.json"
    static let URL_CCTV_WAS_REQ_VOD                         = "/inf/strm/requestVod.json"
    static let URL_CCTV_WAS_CAN_BE_STREAMING                = "/inf/strm/canbestreaming.json"
    static let URL_CCTV_WAS_GET_STREAM_URL                  = "/inf/strm/getstreamurl/v1/"

    static let INTERFACE_ID_MEM_LOGIN                       = "CCTV_WAS_MEM_LOGIN"
    static let INTERFACE_ID_REQ_VOD                         = "WAS_REQ_VOD"
    static let INTERFACE_ID_CAN_BE_STREAMING                = "WAS_REQ_ALBETO_STREAM"
    static let INTERFACE_ID_GET_STREAM_URL                  = "CCTV_WAS_STRM_GETURL"
}
