//
//  DebugLog.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/1/25.
//

import Foundation

class DebugLog {
    static func timeStamp() {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
        let timeStr = dateFormatter.string(from: Date())

        print("timeStamp: \(timeStr)")
    }
    
    static func currentTimeString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
        let timeStr = dateFormatter.string(from: Date())
        
        return timeStr
    }
}
