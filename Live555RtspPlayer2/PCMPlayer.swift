//
//  PCMPlayer.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/17/25.
//

import Foundation
import AVFoundation

class PCMPlayer {
    private lazy var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    //private var audioByteArrays: [UInt8] = []
    
    func playPCMData(_ byteArrays: [[UInt8]]) {
        //let bus: AVAudioNodeBus = 0
        var byteCount = 0
        var frameLength = 0
        
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        
        self.audioEngine.attach(self.playerNode)
        
        //inputFormat
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: false) else {
            print("[PCMPlayer] Failed to create inputFormat")
            return
        }
        print("[PCMPlayer] Successed to create inputFormat: \(inputFormat)")
        
        //outputFormat
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false) else {
            print("[PCMPlayer] Failed to create outputFormat")
            return
        }
     
        self.audioEngine.connect(self.playerNode, to: self.audioEngine.outputNode, format: outputFormat)
        print("[PCMPlayer] Audio Player Node connected to AudioEngine with format")
        
        do {
            try self.audioEngine.start()
            
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            for byteArray in byteArrays {
//                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(byteArray.count) / (inputFormat.streamDescription.pointee.mBytesPerFrame)) else {
//                    print("[PCMPlayer] Failed to create input AVAudioPCMBuffer")
//                    return
//                }
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(byteArray.count) / 2) else {
                    print("[PCMPlayer] Failed to create input AVAudioPCMBuffer")
                    return
                }
                print("[PCMPlayer] frameCapacity AVAudioFrameCount(byteArray.count) : \(AVAudioFrameCount(byteArray.count))")
                print("[PCMPlayer] inputFormat.streamDescription.pointee.mBytesPerFrame: \(inputFormat.streamDescription.pointee.mBytesPerFrame)")
                
                let frameCount = UInt32(byteArray.count) / 2
                inputBuffer.frameLength = frameCount

                byteArray.withUnsafeBytes { rawBufferPointer in
                    let audioBuffer = inputBuffer.int16ChannelData![0]
                    memcpy(audioBuffer, rawBufferPointer.baseAddress!, byteArray.count)
                }

                
                guard let outputBuffer = convertBuffer(inputFormat: inputFormat, inputBuffer: inputBuffer, outputFormat: outputFormat) else {
                    print("[PCMPlayer] Failed to create output AVAudioPCMBuffer")
                    return
                }
                print("[PCMPlayer] success to create output PCM Buffer")
                print("[PCMPlayer] output PCM Buffer.format: \(outputBuffer.format)")
                print("[PCMPlayer] outputBuffer.frameCapacity: \(outputBuffer.frameCapacity)")
                
                outputBuffer.frameLength = outputBuffer.frameCapacity
                
                self.playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)

                if !self.playerNode.isPlaying {
                    self.playerNode.play()
                }
                
//                let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
//                
//                guard let dst = audioBuffer.mData?.bindMemory(to: UInt8.self, capacity: byteArray.count) else {
//                    print("[PCMPlayer] Failed to bind memory to destination buffer")
//                    return
//                }
//                
//                byteArray.withUnsafeBufferPointer {
//                    if let baseAddress = $0.baseAddress {
//                        dst.update(from: baseAddress, count: byteArray.count)
//                        print("[PCMPlayer] Data successfully copied to output buffer")
//                    } else {
//                        print("[PCMPlayer] Failed to get base address of byte array")
//                    }
//                }
//                byteCount += byteArray.count
//                frameLength += Int(outputBuffer.frameLength)
//                print("[PCMPlayer] pcm total byteCount: \(byteCount)")
//                print("[PCMPlayer] pcm total frameLength: \(frameLength)")
//                
//                self.playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)
                
            }
            
        } catch {
            print("[PCMPlayer] Error starting audio engine: \(error.localizedDescription)")
        }
        
//        if self.audioEngine.isRunning {
//            self.playerNode.play()
//            print("[PCMPlayer] Player Node play audio start")
//            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
//                self.playerNode.stop()
//                self.playerNode.reset()
//                print("[PCMPlayer] Player node stop and reset")
//                
//                self.audioEngine.stop()
//                self.audioEngine.reset()
//                print("[PCMPlayer] Audio Engine stop and reset")
//            }
//        } else {
//            print("[PCMPlayer] Audio Engine is not running")
//        }
    }
    
    func convertBuffer(inputFormat: AVAudioFormat, inputBuffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        //guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return nil }
        //guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return nil }
        //inputBuffer.frameLength = inputBuffer.frameCapacity

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameCapacity) else {
            print("[PCMPlayer] Failed to create output buffer")
            return nil
        }
        
        if let floatData = outputBuffer.floatChannelData {
            memset(floatData.pointee, 0, Int(outputBuffer.frameCapacity) * MemoryLayout<Float32>.size)
        }
        
        //print("[PCMPlayer] outputBuffer.frameCapacity: \(outputBuffer.frameCapacity)")

        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            //inputBuffer.frameLength = inputBuffer.frameCapacity
            //print("[PCMPlayer] convert check 1")
            //print("[PCMPlayer] inputBuffer.format: \(inputBuffer.format)")
            return inputBuffer
        }
        
        if let error = error {
            print("[PCMPlayer] Conversion Error: \(error.localizedDescription)")
            return nil
        }
        //print("[PCMPlayer] convert check 2")
        //print("[PCMPlayer] outputBuffer.format: \(outputBuffer.format)")
        return outputBuffer
    }
}

