//
//  Log.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/26/25.
//

import Foundation

class Log {
    static func timeStamp(_ msg: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
        let timeStr = dateFormatter.string(from: Date())

        print("time: \(timeStr)")
    }
}
