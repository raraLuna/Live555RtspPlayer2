//
//  AACDecoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/5/25.
//

import Foundation
import AVFoundation
import AudioToolbox

class AACDecoder {
    //private var audioQueue: AVAudioEngine
    //private var audioPlayer: AVAudioPlayerNode
    private var audioFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    
//    init() {
//        self.audioQueue = AVAudioEngine()
//        self.audioPlayer = AVAudioPlayerNode()
//        audioQueue.attach(audioPlayer)
//    }
    
//    func parseRTPPacket(_ packet: [UInt8]) -> Data {
//        // RFC 3640 기반 AAC RTP 패킷 파싱
//        guard packet.count > 12 else { return Data() } // RTP Header (12 bytes) 제거
//        let aacPayload = packet[12...] // AAC 데이터만 추출
//        print("aacHeadre: \(packet[0..<12])")
//        print("aacPayload: \(aacPayload)")
//        return Data(aacPayload)
//    }
    
    func decodeAACData(_ aacData: Data) {
        var formatDescription: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(mSampleRate: 16000, // AAC 샘플 레이트
                                               mFormatID: kAudioFormatMPEG4AAC,
                                               mFormatFlags: 0,
                                               mBytesPerPacket: 0,
                                               mFramesPerPacket: 1024, // AAC
                                               mBytesPerFrame: 0,
                                               mChannelsPerFrame: 1, // 모노
                                               mBitsPerChannel: 0,
                                               mReserved: 0)
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                    asbd: &asbd, // & 연산자로 포인터 전달
                                                    layoutSize: 0,
                                                    layout: nil,
                                                    magicCookieSize: 0,
                                                    magicCookie: nil,
                                                    extensions: nil,
                                                    formatDescriptionOut: &formatDescription)
        guard status == noErr, let formatDesc = formatDescription else {
            print("Failed to create format description")
            return
        }
        print("formatDescription created: \(String(describing: formatDescription))")
        
        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                    memoryBlock: UnsafeMutableRawPointer(mutating: (aacData as NSData).bytes),
                                                    blockLength: aacData.count,
                                                    blockAllocator: kCFAllocatorNull,
                                                    customBlockSource: nil,
                                                    offsetToData: 0,
                                                    dataLength: aacData.count,
                                                    flags: 0,
                                                    blockBufferOut: &blockBuffer)
        guard status == noErr,let blockBuffer = blockBuffer else {
            print("Failed to create block buffer")
            return
        }
        
        print("blockBuffer create success: \(blockBuffer)")
        print("blockBuffer dataLength: \(blockBuffer.dataLength)")
        

        
        aacData.withUnsafeBytes { rawBufferPointer in
            guard let rawPointer = rawBufferPointer.baseAddress else { return }
            let status = CMBlockBufferReplaceDataBytes(with: rawPointer,
                                                   blockBuffer: blockBuffer,
                                                   offsetIntoDestination: 0,
                                                   dataLength: aacData.count)
            guard status == noErr else {
                print("Failed to copy data to block buffer")
                return
            }
        }
        
        var dataLength = aacData.count
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: CMTime.zero,
                                            decodeTimeStamp: CMTime.invalid)
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                           dataBuffer: blockBuffer,
                                           formatDescription: formatDesc,
                                           sampleCount: 1,
                                           sampleTimingEntryCount: 1,
                                           sampleTimingArray: &timingInfo,
                                           sampleSizeEntryCount: 1,
                                           sampleSizeArray: &dataLength,
                                           sampleBufferOut: &sampleBuffer)
        
        guard status == noErr, let sampleBuffer = sampleBuffer else {
            print("Failed to create sample buffer")
            return
        }
        
        print("sampleBuffer create success: \(sampleBuffer)")
        print("totalSampleSize: \(sampleBuffer.totalSampleSize)")
        
        guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!) else {
                print("Invalid audio format")
                return
            }
        //audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.pointee.mSampleRate, channels: format.pointee.mChannelsPerFrame, interleaved: false)
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: format.pointee.mSampleRate, channels: format.pointee.mChannelsPerFrame, interleaved: false)
        if let format = audioFormat {
            guard let pcmBuffer = self.convertSampleBufferToPCMBuffer(sampleBuffer, format: format) else {
                return
            }
            print("now play pcm buffer")
            let audioPlayer = AudioPlayer(format: format)
            
            audioPlayer.appendBuffer(pcmBuffer)
        }
    }
    
    func convertSampleBufferToPCMBuffer(_ sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("Failed to get data buffer from sample buffer")
            return nil
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var dataLength = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer,
                                    atOffset: 0,
                                    lengthAtOffsetOut: nil,
                                    totalLengthOut: &dataLength,
                                    dataPointerOut: &dataPointer)
        guard status == noErr, let audioData = dataPointer else {
            print("Failed to get audio data pointer")
            return nil
        }
        
        let bytePerFrame = format.streamDescription.pointee.mBytesPerPacket
        let frameCount = AVAudioFrameCount(dataLength) / AVAudioFrameCount(bytePerFrame)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frameCount) else {
            print("Failed to create AVAudioPCMBuffer")
            return nil
        }
        buffer.frameLength = frameCount
        print("buffer.frameLength: \(buffer.frameLength)")
        
        print("audioData: \(audioData)")
        print("buffer.frameLength: \(buffer.frameLength)")
        
        if let int16Data = buffer.int16ChannelData{
            memcpy(int16Data.pointee, audioData, dataLength)
            
        } else if let floatData = buffer.floatChannelData {
            memcpy(floatData.pointee, audioData, dataLength)
        } else {
            print("Check PCM format. It is not int16 and float")
        }
        print("AVAudioPCMBuffer created successfully: \(buffer)")
        
        return buffer
    }
}

