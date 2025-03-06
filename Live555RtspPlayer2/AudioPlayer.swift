//
//  AudioPlayer.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/6/25.
//

import Foundation
import AVFoundation

class AudioPlayer {
//    private let audioEngine = AVAudioEngine()
//    private let playerNode = AVAudioPlayerNode()
    //private var pcmBufferQueue: [AVAudioPCMBuffer] = []
    static var pcmBufferQueue: [AVAudioPCMBuffer] = []
    //private var accumulatedFrames: AVAudioFrameCount = 0
    static var accumulatedFrames: AVAudioFrameCount = 0
    private let sampleRate: Double
    private let framePerSecond: AVAudioFrameCount
    

    
    
    init(format: AVAudioFormat) {
        self.sampleRate = format.sampleRate
        self.framePerSecond = AVAudioFrameCount(sampleRate) // 1초 분량의 프레임 수
        
//        audioEngine.attach(playerNode)
//        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
//        
//        do {
//            try audioEngine.start()
//        } catch {
//            print("AudioEngine start error: \(error)")
//        }
//        print("Audio Engine Started.")
    }
    
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        print("appending pcm buffer to accumulatedFrames...")
        AudioPlayer.pcmBufferQueue.append(buffer)
        AudioPlayer.accumulatedFrames += buffer.frameLength
        
        let requiredFrames = framePerSecond // * n n초 분량의 프레임 수
        print("accumulatedFrames: \(AudioPlayer.accumulatedFrames)")
        print("requiredFrames: \(requiredFrames)")
        
        if AudioPlayer.accumulatedFrames >= requiredFrames {
            playAccumulatedBuffer()
        }
        
    }
    
    private func playAccumulatedBuffer() {
        print("playAccumulatedBuffer() start")
        //guard let format = AudioPlayer.pcmBufferQueue.first?.format else { return }
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        print("audioformat: \(String(describing: inputFormat))")

        // 3초 분량의 AVAudioPCMBuffer 생성
        guard let mergedPCMBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AudioPlayer.accumulatedFrames) else {
            print("Failed to create merged buffer")
            return
        }
        print("AVAudioPCMBuffer format: \(mergedPCMBuffer.format)")
        
        mergedPCMBuffer.frameLength = AudioPlayer.accumulatedFrames
        print("mergedPCMBuffer.frameLength : \(mergedPCMBuffer.frameLength)")
        print("format.channelCount \(inputFormat.channelCount)")
        
        // 각 버퍼의 데이터 병합
        var currentFrame: AVAudioFrameCount = 0
        for buffer in AudioPlayer.pcmBufferQueue {
            let copyFrameLength = buffer.frameLength
            if let src = buffer.int16ChannelData, let dst = mergedPCMBuffer.int16ChannelData {
                
                for channel in 0..<inputFormat.channelCount {
                    memcpy(
                        dst[Int(channel)] + Int(currentFrame),
                        src[Int(channel)],
                        Int(copyFrameLength) * MemoryLayout<Int16>.size
                    )
                }
            }
            currentFrame += copyFrameLength
        }
        print("mergedPCMBuffer: \(mergedPCMBuffer)")
        
        // Audio Engine은 float32 format만 사용하므로 포맷 형식을 변환해줌
        guard let playingPCMBuffer = convertBuffer(mergedPCMBuffer) else {
            return
        }
        
        printPCMBufferInfo(playingPCMBuffer)
        
        
        // MARK: UInt8로 변환하여 재생 시도 -> 실패함
        /*
        guard let uInt8BufferData = floatChannelDataToUInt8(buffer: playingPCMBuffer) else { return }
        print("uInt8BufferData: \(uInt8BufferData)")
        
        // AVAudioEngine은 기본적으로 Float32를 지원함. pcmFormatInt16을 사용하기 위해서는 convert해줘야 한다.
        let audioEngine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        
        audioEngine.attach(playerNode)
        print("Audio Engine attached to playerNode.")
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: outputFormat)
        print("Audio Engine connected to mainMixerNode.")
        //audioEngine.prepare()
        
        do {
            try audioEngine.start()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio Engine Started.")
            
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(uInt8BufferData.count) / (outputFormat.streamDescription.pointee.mBytesPerFrame)) else {
                print("Failed to create AVAudioPCMBuffer")
                return
            }

            buffer.frameLength = buffer.frameCapacity
            
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            guard let dst = audioBuffer.mData?.bindMemory(to: UInt8.self, capacity: uInt8BufferData.count) else {
                print("Failed to bind memory to destination buffer")
                return
            }
            
            uInt8BufferData.withUnsafeBufferPointer {
                if let baseAddress = $0.baseAddress {
                    dst.update(from: baseAddress, count: uInt8BufferData.count)
                    print("Data successfully copied to buffer.")
                } else {
                    print("Failed to get base address of byte array")
                }
            }
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
            print("Player Node scheduleBuffer prepared")
         */
        
        // AVAudioEngine은 기본적으로 Float32를 지원함. pcmFormatInt16을 사용하기 위해서는 convert해줘야 한다.
        let audioEngine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        
        audioEngine.attach(playerNode)
        print("Audio Engine attached to playerNode.")
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: outputFormat)
        print("Audio Engine connected to mainMixerNode.")
        //audioEngine.prepare()
        
        do {
            try audioEngine.start()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio Engine Started.")
        
        
            playerNode.scheduleBuffer(playingPCMBuffer, completionHandler: nil)
            print("Player Node scheduleBuffer prepared")
            
        } catch {
            print("AudioEngine start error: \(error)")
        }

        if audioEngine.isRunning {
            playerNode.play()
            print("Audio Played")
        } else {
            print("Audio Engine is not running")
        }
        
        // 누적 데이터 초기화
        AudioPlayer.pcmBufferQueue.removeAll()
        AudioPlayer.accumulatedFrames = 0
    }
    
    func convertBuffer(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return nil }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return nil }
        
        print("outputformat: \(outputFormat)")
        print("inputFormat: \(inputFormat)")
        print("inputBuffer.format: \(inputBuffer.format)")
        print("inputBuffer.frameLength: \(inputBuffer.frameLength)")
        print("inputBuffer.frameCapacity: \(inputBuffer.frameCapacity)")

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameCapacity) else {
            print("Failed to create output buffer")
            return nil
        }
        
        // outputBuffer.frameLength = inputBuffer.frameLength
        
        
        
        if let floatData = outputBuffer.floatChannelData {
            memset(floatData.pointee, 0, Int(outputBuffer.frameCapacity) * MemoryLayout<Float32>.size)
        }
        
        print("inputBuffer.frameCapacity: \(inputBuffer.frameCapacity)")
        print("outputBuffer.frameCapacity: \(outputBuffer.frameCapacity)")

        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            inputBuffer.frameLength = inputBuffer.frameCapacity
            return inputBuffer
        }
        
        if let error = error {
            print("Conversion Error: \(error.localizedDescription)")
            return nil
        }
        
        return outputBuffer
    }
    
    func logPCMBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else {
            print("⚠️ floatChannelData is nil")
            return
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        for channel in 0..<channelCount {
            let channelData = floatData[channel]  // 채널별 데이터 포인터
            var samples: [Float] = []
            
            for i in 0..<frameLength {
                samples.append(channelData[i])
            }
            
            //print("🔹 Channel \(channel) Data: \(samples.prefix(20)) ...") // 앞 20개 샘플만 출력
            print("🔹 Channel \(channel) Data: \(samples) ...")
        }
    }

    
    func logPCMBufferInt16(_ buffer: AVAudioPCMBuffer) {
        guard let int16Data = buffer.int16ChannelData else {
            print("⚠️ int16ChannelData is nil")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        for channel in 0..<channelCount {
            let channelData = int16Data[channel]  // 채널별 데이터 포인터
            var samples: [Int16] = []
            
            for i in 0..<frameLength {
                samples.append(channelData[i])
            }

            print("🔹 Channel \(channel) Data: \(samples.prefix(20)) ...") // 앞 20개 샘플만 출력
        }
    }

    
    func printPCMBufferInfo(_ buffer: AVAudioPCMBuffer) {
        print("🎵 AVAudioPCMBuffer Info 🎵")
        print("🔹 Sample Rate: \(buffer.format.sampleRate) Hz")
        print("🔹 Channel Count: \(buffer.format.channelCount)")
        print("🔹 Frame Length: \(buffer.frameLength)")
        print("🔹 Frame Capacity: \(buffer.frameCapacity)")
        
        if buffer.format.isInterleaved {
            print("🔹 Format: Interleaved")
        } else {
            print("🔹 Format: Non-Interleaved (Planar)")
        }
        
        if let _ = buffer.floatChannelData {
            print("🔹 Data Type: Float32")
            logPCMBuffer(buffer)
        } else if let _ = buffer.int16ChannelData {
            print("🔹 Data Type: Int16")
            logPCMBufferInt16(buffer)
        } else {
            print("⚠️ No valid channel data found!")
        }
    }
    
    func floatChannelDataToUInt8(buffer: AVAudioPCMBuffer) -> [UInt8]? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var uint8Array: [UInt8] = []
        
        for channel in 0..<channelCount {
            let floatbuffer = floatChannelData[channel] // Float32 array
            let data = Data(bytes: floatbuffer, count: frameLength * MemoryLayout<Float32>.size) // Float32 → Data 변환
            uint8Array.append(contentsOf: data) // Data → [UInt8] 변환
        }
        
        return uint8Array
    }

}

extension Float {
    /**
     Converts the float to an array of UInt8.

     With this method, it is possible to encode a float as bytes and later
     unpack the bytes to a float again. Note though that some of the precision
     is lost in the conversion.

     For instance, a conversion of 0.75 with the maxRange 1.0 results in the
     array `[233, 255, 255, 0]`. To convert the array back to a float, do the
     following calculation:

         (223 / 256 + 255 / 256 / 256 + 255 / 256 / 256 / 256) * (1.0 * 2.0) - 1.0 ≈
         0.8749999 * 2.0 - 1.0 ≈
         0.7499999

     A conversion of 23.1337 with the maxRange 100.0 results in the array
     `[157, 156, 114, 0]`. Converting it back:

         (157 / 256 + 156 / 256 / 256 + 114 / 256 / 256 / 256) * (100.0 * 2.0) - 100.0 ≈
         23.133683
     */
    func toUint8Array(maxRange: Float) -> [UInt8] {
        let max = (UInt32(UInt16.max) + 1) * UInt32(UInt32(UInt8.max) + 1) - 1
        let int = UInt32(((self / maxRange + 1.0) / 2.0 * Float(max)).rounded())
        let a = int.quotientAndRemainder(dividingBy: UInt32(UInt16.max) + 1)
        let b = a.remainder.quotientAndRemainder(dividingBy: UInt32(UInt8.max) + 1)
        return [UInt8(a.quotient), UInt8(b.quotient), UInt8(b.remainder), 0]
    }
}


