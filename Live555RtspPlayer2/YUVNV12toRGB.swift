//
//  YUVNV12toRGB.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/25/25.
//

import Foundation
import CoreVideo
import UIKit
import Accelerate
import CoreGraphics

class YUVNV12toRGB: H264DecoderDelegate {
    
    // MARK: vImage 사용하지 않은 변환
    ///GPU 가속 없이 CPU에서 직접 변환 수행, CoreVideo 필요
    func convertYuvNV12ToRGBwithoutvImage(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        print("get width, height: \(width), \(height)")
        
        guard let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cbCrBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return
        }
        print("success to get y, CbCr base address")
        
        let yPitch = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let cbCrPitch = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        let yBuffer = yBaseAddress.assumingMemoryBound(to: UInt8.self)
        let cbCrBuffer = cbCrBaseAddress.assumingMemoryBound(to: UInt8.self)
        
        // YUV 데이터를 하나의 버퍼로 통합
        let yuvDataSize = yPitch * height + cbCrPitch * (height / 2)
        let yuvData = UnsafeMutablePointer<UInt8>.allocate(capacity: yuvDataSize)
        defer { yuvData.deallocate() }
        
        memcpy(yuvData, yBuffer, yPitch * height)
        memcpy(yuvData.advanced(by: yPitch * height), cbCrBuffer, cbCrPitch * (height / 2))
        
        
        // RGBA 버퍼 생성
        let rgbaBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        defer { rgbaBuffer.deallocate() }
        
        // YUV -> RGB 변환
        yuvToRGB(rgbaBuffer, yuvData, width: width, height: height, yPitch: yPitch, isNV12: true)
        
        // RGBA 데이터를 UIImage로 변환
        if let image = rgbaToUIImage(rgbaBuffer, width: width, height: height) {
            print("UIImage 변환 완료: \(image)")
            let cgImageFilePath = "/Users/yumi/Documents/videoDump/cgImage.png"
            if let imageData = image.pngData() {
                try? imageData.write(to: URL(fileURLWithPath: cgImageFilePath))
            }
        }
    }
    
    // YUV(NV12) → RGB 변환
    func yuvToRGB(_ rgb: UnsafeMutablePointer<UInt8>, _ yuv: UnsafeMutablePointer<UInt8>, width: Int, height: Int, yPitch: Int, isNV12: Bool = true) {
        let total = yPitch * height
        var index = 0
        
        for h in 0..<height {
            let yBufferLine = yuv.advanced(by: h * yPitch)
            let uvDataLine = yuv.advanced(by: total + (h >> 1) * yPitch)
            
            for w in 0..<width {
                let Y = Int16(yBufferLine[w])
                let U: Int16
                let V: Int16
                
                if isNV12 {
                    U = Int16(uvDataLine[w & ~1])
                    V = Int16(uvDataLine[w | 1])
                } else {
                    V = Int16(uvDataLine[w & ~1])
                    U = Int16(uvDataLine[w | 1])
                }

                var R = Y + Int16(1.400 * Float(V - 128))
                var G = Y - Int16(0.343 * Float(U - 128)) - Int16(0.711 * Float(V - 128))
                var B = Y + Int16(1.765 * Float(U - 128))
                
                R = min(max(R, 0), 255)
                G = min(max(G, 0), 255)
                B = min(max(B, 0), 255)
                
                rgb[index] = 0xFF // Alpha
                rgb[index + 1] = UInt8(B)
                rgb[index + 2] = UInt8(G)
                rgb[index + 3] = UInt8(R)
                
                index += 4
            }
        }
    }
    
    // RGBA 데이터를 UIImage로 변환
    func rgbaToUIImage(_ rgbaBuffer: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Little)
        
        guard let context = CGContext(
            data: rgbaBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("failed to create CGContext")
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            print("failed to create cgImage")
                return nil
            }
            
        print("Success to create cgImage")
        return UIImage(cgImage: cgImage)
    }
    
    
    
    
    // MARK: vImage 사용한 변환
    ///GPU 가속을 활용하여 최적화된 변환을 수행, CoreVideo, UIKit, Accelerate 필요
    func convertYuvNV12ToRGBwithvImage(pixelBuffer: CVPixelBuffer) -> UIImage {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        guard let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBaseAddreass = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return UIImage()
        }
        
        // line_stride: 이미지의 한 줄이 메모리에서 차지하는 바이트 수
        ///다음 행의 첫번째 픽셀주소로 이동하기 위해 행의 첫번째 픽셀에 추가해야 하는 바이트 수
        ///이미지 너비는 픽셀로 측정되고 이미지 자체를 설명함(이미지가 컴퓨터 메모리에 저장되는 방식에 따라 달라지지 않음)
        ///라인 스트라이드는 이미지가 메모리에 표현되는 방식에 따라 달라지며 바이트로 측정됨
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        var yPlane = vImage_Buffer(data: yBaseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: yStride)
        var uvPlane = vImage_Buffer(data: uvBaseAddreass, height: vImagePixelCount(height) / 2, width: vImagePixelCount(width) / 2 * 2, rowBytes: uvStride)
        
        var rgbBuffer = vImage_Buffer()
        defer { free(rgbBuffer.data) }
        
        let bytesPerPixel = 4
        let rowBytes = width * bytesPerPixel
        rgbBuffer.width = vImagePixelCount(width)
        rgbBuffer.height = vImagePixelCount(height)
        rgbBuffer.rowBytes = rowBytes
        rgbBuffer.data = malloc(rowBytes * height)
        
        guard rgbBuffer.data != nil else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return UIImage()
        }
        
        // 변환 행렬(Rec. 601 - standard Definition Tv)
//        let yuvToRGBMatrix: [Int16] = [
//            256, 0, 359, // R = Y + 1.402 (Cr - 128)
//            256, -88, -183, // G = Y - 0.34414 (Cb - 128) - 0.71414 (Cr - 128)
//            256, 454, 0 // B = Y + 1.772 (Cb - 128)
//        ]
        
        var yuvToRGBMatrix = vImage_YpCbCrToARGB()
        var pixelRange = vImage_YpCbCrPixelRange(Yp_bias: 16,
                                                 CbCr_bias: 128,
                                                 YpRangeMax: 235,
                                                 CbCrRangeMax: 240,
                                                 YpMax: 255,
                                                 YpMin: 0,
                                                 CbCrMax: 255,
                                                 CbCrMin: 0)

        // 변환 행렬 생성
        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,  // 변환 행렬 (Rec.601)
            &pixelRange,                             // 픽셀 범위
            &yuvToRGBMatrix,                         // 변환 정보를 저장할 변수
            kvImage420Yp8_CbCr8,                     // YUV 포맷 (601 사용)
            kvImageARGB8888,                         // RGB 출력 포맷
            vImage_Flags(kvImageNoFlags)             // 변환 플래그
        )

        // 오류 확인
        if error != kvImageNoError {
            print("YUV -> RGB 변환 행렬 생성 실패: \(error)")
        }

        
        //let permuteMap: [UInt8] = [0, 1, 2, 3] // ARGB 순서 유지
        //let divisor: Int32 = 256
        
        // YUV -> RGB 변환 실행
        vImageConvert_420Yp8_CbCr8ToARGB8888(&yPlane, &uvPlane, &rgbBuffer, &yuvToRGBMatrix, nil, 255, vImage_Flags(kvImageNoFlags))
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        // CG Image 변환
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: rgbBuffer.data,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: rowBytes,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return UIImage()
        }
        
        guard let cgImage = context.makeImage() else {
            print("CGImage 생성 실패")
            return UIImage()
        }
        print("CGImage 생성 성공")
        
        return UIImage(cgImage: cgImage)
    }
    
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer) {
//        let uiImage = self.convertYuvNV12ToRGBwithvImage(pixelBuffer: pixelBuffer)
//        let cgImageFilePath = "/Users/yumi/Documents/videoDump/cgImage.png"
//        if let imageData = uiImage.pngData() {
//            try? imageData.write(to: URL(fileURLWithPath: cgImageFilePath))
//        }
        self.convertYuvNV12ToRGBwithoutvImage(pixelBuffer: pixelBuffer)
    }
    
}
