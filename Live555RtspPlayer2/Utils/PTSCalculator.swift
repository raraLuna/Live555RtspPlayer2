//
//  PTSCalculator.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/24/25.
//

import Foundation

struct H265PTSContext {
    var prevPicOrderCntMsb: Int
    var prevPicOrderCntLsb: Int
}


class PTSCalculator {
    func calculatePOC(
        sliceHeader: H265SliceHeader,
        sps: H265SPS,
        /*vps: H265VPS,*/
        context: inout H265PTSContext
    ) -> Double? {
        let lsbBits = Int(sps.log2MaxPicOrderCntLsbMinus4 + 4)
        let maxPicOrderCntLsb = 1 << lsbBits
        let picOrderCntLsb = Int(sliceHeader.slicePicOrderCntLsb)

        // POC 계산 (h264bsd 방식 기반)
        var pocMsb = 0
        if (picOrderCntLsb < context.prevPicOrderCntLsb &&
            (context.prevPicOrderCntLsb - picOrderCntLsb) >= (maxPicOrderCntLsb / 2)) {
            pocMsb = context.prevPicOrderCntMsb + maxPicOrderCntLsb
        } else if (picOrderCntLsb > context.prevPicOrderCntLsb &&
                   (picOrderCntLsb - context.prevPicOrderCntLsb) > (maxPicOrderCntLsb / 2)) {
            pocMsb = context.prevPicOrderCntMsb - maxPicOrderCntLsb
        } else {
            pocMsb = context.prevPicOrderCntMsb
        }

        let poc = pocMsb + picOrderCntLsb
        context.prevPicOrderCntMsb = pocMsb
        context.prevPicOrderCntLsb = picOrderCntLsb
        
        return Double(poc)
    }

}
