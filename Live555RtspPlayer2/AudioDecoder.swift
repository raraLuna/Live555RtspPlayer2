//
//  AudioDecoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/5/25.
//

import Foundation
import AVFoundation
import AudioToolbox

class AudioDecoder {
    private let mimeType: String
    private let sampleRate: Int
    private let channelCount: Int
    private let codecConfig: Data?
    private let audioFrameQueue: AudioFrameQueue
    private var isRunning = true
    private let queue = DispatchQueue(label: "AudioDecodeQueue", qos: .userInitiated)
    private let semaphore = DispatchSemaphore(value: 0)
    
    private var audioDecoder: AudioConverterRef? // 오디오를 변환하는 Apple API
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    private var audioFormat: AVAudioFormat!
    
    init(mimeType: String, sampleRate: Int, channelCount: Int, codecConfig: Data?, audioFrameQueue: AudioFrameQueue) {
        self.mimeType = mimeType
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.codecConfig = codecConfig
        self.audioFrameQueue = audioFrameQueue
    }
    
    func stopAsync() {
        isRunning = false
        semaphore.signal() // awake thread
    }
    
    func startDecoding() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                // 데이터를 가져오거나 대기함
                guard let audioFrame = self.getAudioFrame() else {
                    self.semaphore.wait(timeout: .now() + 1) // 1초 대기 후 다시 체크
                    continue
                }
                
                // 오디오 디코딩
                self.decodeAudio(audioFrame)
            }
        }
    }
    
    private func getAudioFrame() -> Data? {
        guard let frame = audioFrameQueue.pop() else {
            print("Empty audio frame")
            return nil
        }
        return Data(frame.data[frame.offset..<(frame.offset + frame.length)])
    }
    
    private func decodeAudio(_ frame: Data) {
        setupAudioDecoder(sampleRate: 16000, channels: 1, codecType: kAudioFormatMPEG4AAC)
    }
    
    
    func setupAudioDecoder(sampleRate: Int, channels: Int, codecType: AudioFormatID) {
        var inputFormat = AudioStreamBasicDescription()
        inputFormat.mFormatID = codecType // kAudioFormatMPEG4AAC 또는 kAudioFormatOpus
        inputFormat.mSampleRate = Float64(sampleRate)
        inputFormat.mChannelsPerFrame = UInt32(channels)
        inputFormat.mFramesPerPacket = 1024
        inputFormat.mBitsPerChannel = 0
        inputFormat.mBytesPerFrame = 0
        inputFormat.mBytesPerPacket = 0
        
        var outputFormat = AudioStreamBasicDescription()
        outputFormat.mFormatID = kAudioFormatLinearPCM
        outputFormat.mSampleRate = Float64(sampleRate)
        outputFormat.mChannelsPerFrame = UInt32(channels)
        outputFormat.mFramesPerPacket = 1
        outputFormat.mBitsPerChannel = 16
        outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * 2
        outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame
        outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        
        let status = AudioConverterNew(&inputFormat, &outputFormat, &audioDecoder)
        if status != noErr {
            print("AudioConverter creation failed with error: \(status)")
        } else {
            print("AudioDecoder Initialized successfully")
        }
    }
}

class AudioFrame {
    var data: [UInt8]
    var offset: Int
    var length: Int
    var timestampMs: Int64
    
    init(data: [UInt8], offset: Int, length: Int, timestampMs: Int64) {
        self.data = data
        self.offset = offset
        self.length = length
        self.timestampMs = timestampMs
    }
}

class AudioFrameQueue {
    private var queue: [AudioFrame] = []
    private let lock = NSLock()
    
    func push(_ frame: AudioFrame) {
        lock.lock()
        queue.append(frame)
        lock.unlock()
    }
    
    func pop() -> AudioFrame? {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty ? nil : queue.removeFirst()
    }
    
    func clear() {
        lock.lock()
        queue.removeAll()
        lock.unlock()
    }
    
    func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty
    }
}
