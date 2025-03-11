//
//  MakeDumpFile.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/28/25.
//

import Foundation
import CoreVideo

class MakeDumpFile {
    static func dumpRTPPacket(_ packet: [UInt8], to filePath: String) {
        print("Start writing RTP dump file")

        let fileURL = URL(fileURLWithPath: filePath)
        
        // 파일이 없으면 생성
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        // 파일 핸들 열기
        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            print("Failed to open file for writing")
            return
        }

        // 데이터 변환 후 파일에 기록
        let data = Data(packet)
        fileHandle.seekToEndOfFile()  // 기존 파일에 추가
        fileHandle.write(data)
        fileHandle.closeFile()

        print("RTP Dump saved at \(filePath)")
    }
    
    static func dumpCVPixelBuffer(_ pixelBuffer: CVPixelBuffer, to filePath: String) {
        print("start make dump file")
        // 픽셀 버퍼로의 접근 막음
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        print("dump's width: \(width), height: \(height)")

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            print("Unsupported pixel format")
            return
        }
        
        print("pixel format : \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
        
        let fileURL = URL(fileURLWithPath: filePath)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)

        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            print("Failed to open file for writing")
            return
        }

        // Y Plane
        guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            print("Failed to get Y Plane address")
            return
        }
        let yPlaneHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let yPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        
        let yData = Data(bytes: yPlaneAddress, count: yPlaneHeight * yPlaneBytesPerRow)
        fileHandle.write(yData)
        
        // UV Plane (Interleaved CbCr)
        guard let uvPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            print("Failed to get UV Plane address")
            return
        }
        let uvPlaneHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let uvPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        let uvData = Data(bytes: uvPlaneAddress, count: uvPlaneHeight * uvPlaneBytesPerRow)
        fileHandle.write(uvData)

        fileHandle.closeFile()
        
        print("YUV Dump saved at \(filePath)")
        
    }
}
