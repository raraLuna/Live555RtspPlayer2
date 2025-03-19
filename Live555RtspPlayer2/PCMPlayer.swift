//
//  PCMPlayer.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/17/25.
//

import Foundation
import AVFoundation

class PCMPlayer {
    private lazy var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 16000.0
    private let channel: AVAudioChannelCount = 1
    private let duration: TimeInterval = 5.0
    
    private var pcmData = Data()
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        print("setupAudioEngine() called")
        let bus: AVAudioNodeBus = 0
        
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        
        self.engine.attach(self.playerNode)
        print("AVAudio Engine attached AVAudio Player Node")
        print("AVAudio Player Node outputformat: \(self.playerNode.outputFormat(forBus: bus))")
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: self.sampleRate, channels: self.channel, interleaved: false) else {
            print("Failed to create AVAudioformat")
            return
        }
        print("create format: \(String(describing: format))")
        
        self.engine.connect(self.playerNode, to: self.engine.outputNode, format: format)
        print("Audio Player Node connected to AudioEngine.outputNode with format")
        
        do {
            try engine.start()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            print("Audio engine start successfully")
        } catch {
            print("Audio engine start failed: \(error.localizedDescription)")
        }
    }
    
    /*
    func appendPCMData(from audioBufferList: UnsafePointer<AudioBufferList>, frameCount: UInt32) {
        let audioBuffer = audioBufferList.pointee.mBuffers
        let data = Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
        pcmData.append(data)
        print("pcm data appended: \(pcmData.count)")
        
        // 5초 분량 누적
        let requiredByteSize = Int(sampleRate * duration) * MemoryLayout<Float32>.size
        print("requiredByteSize: \(requiredByteSize)")
        print("pcmData.count: \(pcmData.count)")
        if pcmData.count >= requiredByteSize {
            playBufferedPCMData()
            pcmData.removeAll()
        }
    }
     */
    
    func playBufferedPCMData(pcmData: Data) {
        print("playBufferedPCMData() called")
        let frameCapacity = pcmData.count / MemoryLayout<Float32>.size
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: self.channel, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCapacity)) else {
            print("Failed to create AVAudioPCMBuffer")
            return
        }
        print("pcm data count: \(pcmData.count)")
        print("playBufferedPCMData buffer: \(buffer)")
        buffer.frameLength = AVAudioFrameCount(frameCapacity)
        print("buffer.frameLength: \(buffer.frameLength)")
        print("buffer.floatChannelData: \(String(describing: buffer.floatChannelData))")
        let floatBuffer = buffer.floatChannelData![0]
        pcmData.withUnsafeBytes { rawBuffer in
            let rawPointer = rawBuffer.bindMemory(to: Float32.self)
            floatBuffer.update(from: rawPointer.baseAddress!, count: frameCapacity)
        }
        
        self.playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !self.playerNode.isPlaying {
            self.playerNode.play()
            print("played pcm data")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.playerNode.stop()
                self.playerNode.reset()
                print("Player node stop and reset")
                
                self.engine.stop()
                self.engine.reset()
                print("Audio Engine stop and reset")
            }
        }
    }
}
