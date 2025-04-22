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
    private let audioPcmQueue: ThreadSafeQueue<[UInt8]>
    private var timer: DispatchSourceTimer?
    private var isPlaying = false
    
    init(audioPcmQueue: ThreadSafeQueue<[UInt8]>) {
        self.audioPcmQueue = audioPcmQueue
    }
    
    func startPlayback() {
        self.audioEngine.attach(self.playerNode)
        
        //inputFormat
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: false) else {
            print("[PCMPlayer] Failed to create inputFormat")
            return
        }
        
        //outputFormat
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false) else {
            print("[PCMPlayer] Failed to create outputFormat")
            return
        }
     
        self.audioEngine.connect(self.playerNode, to: self.audioEngine.outputNode, format: outputFormat)
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try self.audioEngine.start()
            print("[PCMPlayer] audioEngine.start()")
            
            self.playerNode.play()  
            print("[PCMPlayer] playerNode.play()")
            
        } catch {
            print("[PCMPlayer] Error starting audio engine: \(error.localizedDescription)")
            return
        }
        
        timer = DispatchSource.makeTimerSource()
        timer?.schedule(deadline: .now(), repeating: 0.02) // 20ms 주기
        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.feedBuffer(inputFormat: inputFormat, outputFormat: outputFormat)
        }
        timer?.resume()
        isPlaying = true
        print("[PCMPlayer] Timer started")
    }
    
    func feedBuffer(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let byteArray = audioPcmQueue.dequeue() else { return }
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(byteArray.count / 2)) else { return }
        
        inputBuffer.frameLength = inputBuffer.frameCapacity
        
        byteArray.withUnsafeBytes { rawBufferPointer in
            let audioBuffer = inputBuffer.int16ChannelData![0]
            memcpy(audioBuffer, rawBufferPointer.baseAddress!, byteArray.count)
        }
        
        guard let outputBuffer = convertBuffer(inputFormat: inputFormat, inputBuffer: inputBuffer, outputFormat: outputFormat) else {
            print("[PCMPlayer] Failed to create output AVAudioPCMBuffer")
            return
        }
        outputBuffer.frameLength = outputBuffer.frameCapacity
        playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)
        print("[PCMPlayer] playerNode prepared to play audio")
        
    }
    
    func convertBuffer(inputFormat: AVAudioFormat, inputBuffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameCapacity) else {
            print("[PCMPlayer] Failed to create output buffer")
            return nil
        }
        
        if let floatData = outputBuffer.floatChannelData {
            memset(floatData.pointee, 0, Int(outputBuffer.frameCapacity) * MemoryLayout<Float32>.size)
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            return inputBuffer
        }
        
        if let error = error {
            print("[PCMPlayer] Conversion Error: \(error.localizedDescription)")
            return nil
        }
        return outputBuffer
    }
    
    func stopPlayback() {
        timer?.cancel()
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
        print("[PCMPlayer] Stopped playback")
    }
}

