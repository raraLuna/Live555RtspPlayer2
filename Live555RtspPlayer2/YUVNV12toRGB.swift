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
        
        // Pitch: 메모리에서 한줄(row)를 저장하는데 필요한 바이트 수 (이미지의 한 행이 차지하는 총 메모리)
        ///일반적으로 픽셀 데이터가 정렬되기 때문에 Pitch는 이미지의 가로크기보다 클 수 있음(padding 포함된 크기임)
        ///
        // Stride: 데이터 간의 간격 (픽셀 단위의 간격)
        ///RGB 이미지에서 stride는 한 픽셀을 구성하는 바이트 수를 나타낼 수 있음 (RGBA8888 포맷에서 stride = 4(R, G, B, A 4bytes)
        ///YUV 이미지에서 stride는 한 색상 성분(Y, U, V)의 각 행(row)간의 간격
        /////// NV12 포맷에서 Y(휘도) 채널의 stride는 보통 픽셀 개수(width)와 동일하지만, UV 채널의 stride는 Y 채널 stride의 절반이 될 수 있음
        /////// (YUV420 포맷은 UV(색차) 채널이 Y의 절반 크기이므로 stride가 다를 수 있음)
        ///
        // ** CPU와 GPU는 효율적인 작업을 위해 특정 메모리 정렬을 요구 할 수 있음
        //    예를 들어 width가 1920인 이미지의 경우, 메모리 정렬 때문에 Pitch가 2048이 될 수 있음
        //    16bytes, 32bytes 단위로 정렬된 데이터가 더 빠른 처리 속도를 보이기 때문
        
        // Pitch를 고려해야하는 이유:
        // width 만큼의 픽셀을 사용해야하지만(실제 픽셀 데이터), row당 메모리는 pitch 크기로 정렬됨.
        // 따라서 row * Pitch로 접근해야 올바르게 데이터에 접근할 수 있음
        let yPitch = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let cbCrPitch = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        print("yPitch: \(yPitch), cbCrPitch: \(cbCrPitch)")
        
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
//        if let image = rgbaToUIImage(rgbaBuffer, width: width, height: height) {
//            print("UIImage 변환 완료")
//            let cgImageFilePath = "/Users/yumi/Documents/videoDump/cgImage.png"
//            if let imageData = image.pngData() {
//                try? imageData.write(to: URL(fileURLWithPath: cgImageFilePath))
//            }
//        }
        
        // RGBA 데이터를 Bitmap Image로 변환
        let bmpImage = self.createBitmap(rgbaBuffer, width: width, height: height)
        print("bitmap header 생성 및 bitmap 변환 완료")
        let cgImageFilePath = "/Users/yumi/Documents/videoDump/bitmapImage.bmp"
        try? bmpImage.write(to: URL(fileURLWithPath: cgImageFilePath))
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
    
    func createBitmap(_ rgbBuffer: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> Data {
        let bytesPerPixel = 3 // 24 bit BMP (RGB)
        // BMP 파일에서 픽셀 데이터는 RGB 형식으로 저장된다.
        // 24비트 BMP에서는 각 픽셀당 R, G, B 각각 1 byte(8bits)씩 저장하므로 총 3bytes(24bits)가 필요하다
        
        // rowSize는 **BMP 한 줄의 크기(패딩 포함)**를 의미
        //// BMP 파일의 각 행은 4바이트 단위로 맞춰야 하므로 width * 3에 패딩을 추가한 크기
        let rowSize = (width * bytesPerPixel + 3) & ~3 // 4byte alignment
        let imageSize = rowSize * height
        let fileSize = 54 + imageSize // 54-bytes BMP header + pixel data
        
        var bmpHeader = [UInt8](repeating: 0, count: 54)
        
        // BMP Header (Bitmap File Header, 14bytes)
        bmpHeader[0] = 0x42 // 'B'
        bmpHeader[1] = 0x4D // 'M'
        
        // 파일 크기
        withUnsafeBytes(of: UInt32(fileSize).littleEndian) { buffer in
            bmpHeader.replaceSubrange(2..<6, with: buffer)
        }
        // bmpHeader[6..<10] : 어플리케이션 세팅으로 보통 0이 할당 됨. 이미 0으로 채워져있으므로 skip
        
        // 픽셀 데이터 오프셋 (54bytes): 픽셀 데이터가 시작하는 위치 표시
        withUnsafeBytes(of: UInt32(54).littleEndian) { buffer in
            bmpHeader.replaceSubrange(10..<14, with: buffer)
        }
        
        // DIB Header 크기 (Bitmap Info Header, 40bytes): 항상 40
        withUnsafeBytes(of: UInt32(40).littleEndian) { buffer in
            bmpHeader.replaceSubrange(14..<18, with: buffer)
        }
        
        // 이미지 width
        withUnsafeBytes(of: UInt32(width).littleEndian) { buffer in
            bmpHeader.replaceSubrange(18..<22, with: buffer)
        }
        
        // 이미지 height
        withUnsafeBytes(of: UInt32(height).littleEndian) { buffer in
            bmpHeader.replaceSubrange(22..<26, with: buffer)
        }
        
        // 컬러 플랜 (1, 고정값)
        withUnsafeBytes(of: UInt32(1).littleEndian) { buffer in
            bmpHeader.replaceSubrange(26..<28, with: buffer)
        }
        
        // 비트 깊이 (24bit BMP = 24): 깊이란 유효한 컬러 데이터를 말함. RGBA8888을 봤을 때, RGB 가 유효한 컬러 데이터이므로 8 * 3 = 24(bits)
        // 비디오나 이미지의 해상도에 따라 값이 달라질 수 있음(비트 깊이에따라 픽셀당 차지하는 바이트 수가 달라짐)
        withUnsafeBytes(of: UInt32(24).littleEndian) { buffer in
            bmpHeader.replaceSubrange(28..<30, with: buffer)
        }
        
        // 압축 방식 (BI_RGB = 0)
        // : 버퍼를 압축 할 것인가의 여부. 실시간 처리에서는 압축/압축 해제 시 CPU 소모가 크므로 보통 사용하지 않는다.
        withUnsafeBytes(of: UInt32(0).littleEndian) { buffer in
            bmpHeader.replaceSubrange(30..<34, with: buffer)
        }
        
        // 이미지 데이터 크기 (픽셀 데이터 크기. width * height * bytesPerPixel
        let imageDataSize = width * height * bytesPerPixel
        withUnsafeBytes(of: UInt32(imageDataSize).littleEndian) { buffer in
            bmpHeader.replaceSubrange(34..<38, with: buffer)
        }
        
        // 프린트 해상도 (보통 0) (38~41: X 해상도, 42~25: Y 해상도)
        withUnsafeBytes(of: UInt32(0).littleEndian) { buffer in
            bmpHeader.replaceSubrange(38..<46, with: buffer)
        }
        
        // 팔레트 정보 (24bit BMP에서는 사용하지 않음): 사용되는 색상 개수 (0 = 전체 색상 사용)
        withUnsafeBytes(of: UInt32(0).littleEndian) { buffer in
            bmpHeader.replaceSubrange(46..<50, with: buffer)
        }
        
        // 중요한 색상 정보 (보통 0): 중요한 색상 개수 (0 = 모든 색상 중요)
        withUnsafeBytes(of: UInt32(0).littleEndian) { buffer in
            bmpHeader.replaceSubrange(50..<54, with: buffer)
        }
        
        // 변환된 UnsafeMutablePointer 사용
        bmpHeader.withUnsafeMutableBytes { rawBuffer in
            let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            // ptr을 사용하여 파일 저장 또는 다른 작업 수행 가능
            print("BMP Header 생성 완료")
        }
        
        // Convert RGBA to BMP RGB (BGR order, with padding)
        /// rgbBuffer는 abgr 형식으로되어 있음
        //var pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: imageSize)
        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 3)
        defer { pixelData.deallocate() }
        for y in 0..<height {
            // y * width * 4 만큼 이동하여 현재 y 행의 시작 주소를 찾음
            let srcRow = rgbBuffer.advanced(by: y * width * 4)
            // height - 1 - y를 사용하여 Y 좌표를 뒤집음
            let dstRow = pixelData.advanced(by: (height - 1 - y) * width * 3) // BMP는 Bottom-Up 저장 (바닥부터 데이터가 시작됨..?)
            
            for x in 0..<width {
                // x * 4 만큼 이동하여 현재 픽셀의 주소를 찾음 (원본 RGBA 픽셀은 4바이트(R, G, B, A))
                let srcPixel = srcRow.advanced(by: x * 4)
                // x * 3 만큼 이동하여 BMP 데이터에서 저장할 픽셀 위치를 찾음 (BMP는 24비트 RGB 형식(3바이트 BGR))
                let dstPixel = dstRow.advanced(by: x * 3)
                
                // RGBA (srcPixel) -> BGR (dstPixel) 변환
                // srcPixel의 순서: ABGR, dstPixel의 순서: BGR
                dstPixel[0] = srcPixel[1] // B
                dstPixel[1] = srcPixel[2] // G
                dstPixel[2] = srcPixel[3] // R
            }
        }
        let pixelDataArray = Array(UnsafeBufferPointer(start: pixelData, count: width * height * 3))
        let bmpData: [UInt8] = bmpHeader + pixelDataArray
        
        return Data(bmpData)
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
