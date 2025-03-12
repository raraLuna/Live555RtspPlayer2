//
//  AudioDecoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/5/25.
//

import Foundation
import AVFoundation
import AudioToolbox

struct ConverterInfo {
    var sourceChannelsPerFrame: UInt32
    var sourceDataSize: UInt32
    var sourceBuffer: UnsafeMutableRawPointer?
    var packetDesc: UnsafeMutablePointer<AudioStreamPacketDescription>
}

class AudioDecoder {
    private var audioConverter: AudioConverterRef?
    private var sourceFormat: AudioStreamBasicDescription
    private var destinationFormat: AudioStreamBasicDescription
    
    init(sourceFormat: AudioStreamBasicDescription, destFormatID: AudioFormatID, sampleRate: Float64, useHardwareDecode: Bool) {
        self.sourceFormat = sourceFormat
        self.destinationFormat = AudioStreamBasicDescription()
        self.audioConverter = configureDecoder(sourceFormatDesc: sourceFormat, destFormat: &self.destinationFormat, destFormatID: destFormatID, sampleRate: sampleRate, useHardwareDecode: useHardwareDecode)
    }
    
    deinit {
        freeDecoder()
    }
    
    // MARK: Public Functions
    func decodeAudio(sourceBuffer: UnsafeMutableRawPointer, sourceBufferSize: UInt32, completion: @escaping (AudioBufferList, UInt32, AudioStreamPacketDescription?) -> Void) {
        decodeFormat(converter: audioConverter, sourceBuffer: sourceBuffer, sourceBufferSize: sourceBufferSize, sourceFormat: sourceFormat, destFormat: destinationFormat, completion: completion)
    }
    
    func freeDecoder() {
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
    }
    
    // MARK: Private Functions
    private func configureDecoder(sourceFormatDesc: AudioStreamBasicDescription, destFormat: inout AudioStreamBasicDescription, destFormatID: AudioFormatID, sampleRate: Float64, useHardwareDecode: Bool) -> AudioConverterRef? {
        if destFormatID != kAudioFormatLinearPCM {
            print("Unsupported format after decoding")
            return nil
        }
        var sourceFormat = sourceFormatDesc
        print("configureDecoder sourceFormat: \(sourceFormat)")
        destFormat.mSampleRate = sampleRate
        destFormat.mFormatID = kAudioFormatLinearPCM
        destFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        destFormat.mFramesPerPacket = 1
        destFormat.mBitsPerChannel = 16
        destFormat.mChannelsPerFrame = sourceFormat.mChannelsPerFrame
        destFormat.mBytesPerFrame = destFormat.mBitsPerChannel / 8 * destFormat.mChannelsPerFrame
        destFormat.mBytesPerPacket = destFormat.mBytesPerFrame * destFormat.mFramesPerPacket
        
        printAudioStreamBasicDescription(sourceFormat)
        printAudioStreamBasicDescription(destFormat)
        
        guard let audioClassDesc = getAudioClassDescription(type: destFormatID, manufacturer: kAppleSoftwareAudioCodecManufacturer) else {
            print("configureDecoder audioClassDesc failed")
            return nil
        }
        
        var converter: AudioConverterRef?
        let status = AudioConverterNewSpecific(&sourceFormat, &destFormat, destFormat.mChannelsPerFrame, audioClassDesc, &converter)
        
        if status != noErr {
            print("Audio Converter creation failed")
            return nil
        }
        
        print("Audio converter created successfully")
        return converter
    }
    
    private func decodeFormat(converter: AudioConverterRef?, sourceBuffer: UnsafeMutableRawPointer, sourceBufferSize: UInt32, sourceFormat: AudioStreamBasicDescription, destFormat: AudioStreamBasicDescription, completion: @escaping (AudioBufferList, UInt32, AudioStreamPacketDescription?) -> Void) {
        print("decodeFormat() called")
        guard let converter = converter else { print("converter is nil"); return }
        
        let ioOutputDataPackets: UInt32 = 1024
        let outputBufferSize = ioOutputDataPackets * destFormat.mChannelsPerFrame * destFormat.mBytesPerFrame
        print("outputBufferSize: \(outputBufferSize)")
        
        var fillBufferList = AudioBufferList()
        fillBufferList.mNumberBuffers = 1
        fillBufferList.mBuffers.mNumberChannels = destFormat.mChannelsPerFrame
        fillBufferList.mBuffers.mDataByteSize = outputBufferSize
        fillBufferList.mBuffers.mData = malloc(Int(outputBufferSize))
        
        // `packetDesc` 메모리 할당
        let packetDescPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        packetDescPointer.initialize(to: AudioStreamPacketDescription(mStartOffset: 0,
                                                                      mVariableFramesInPacket: 0,
                                                                      mDataByteSize: sourceBufferSize))
        
        var userInfo = ConverterInfo(sourceChannelsPerFrame: sourceFormat.mChannelsPerFrame,
                                     sourceDataSize: sourceBufferSize,
                                     sourceBuffer: sourceBuffer,
                                     packetDesc: packetDescPointer
        )
        print("userInfo: \(userInfo)")
        
        // `outputPacketDesc` 메모리 할당
        let outputPacketDescPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        outputPacketDescPointer.initialize(to: AudioStreamPacketDescription())

        var numPackets = ioOutputDataPackets
        print("numPackets: \(numPackets)")

        // `AudioConverterFillComplexBuffer` 호출
        let status = AudioConverterFillComplexBuffer(
            converter,
            decodeConverterComplexInputDataProc,
            &userInfo,
            &numPackets,
            &fillBufferList,
            outputPacketDescPointer
        )

        if status != noErr {
            print("AudioConverterFillComplexBuffer failed: \(status)")
            return
        }

        // `completion` 블록 실행
        completion(fillBufferList, numPackets, outputPacketDescPointer.pointee)

        // 메모리 해제
        packetDescPointer.deallocate()
        outputPacketDescPointer.deallocate()
    }
    
    // MARK: Audio Converter Input Data Callback
    private let decodeConverterComplexInputDataProc: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
        guard let inUserData = inUserData else {
            return -1
        }
        
        var info = inUserData.assumingMemoryBound(to: ConverterInfo.self).pointee
        
        if info.sourceDataSize <= 0 {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        
        if let outDataPacketDescription = outDataPacketDescription {
            outDataPacketDescription.pointee = info.packetDesc
        }
        
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = info.sourceBuffer
        ioData.pointee.mBuffers.mNumberChannels = info.sourceChannelsPerFrame
        ioData.pointee.mBuffers.mDataByteSize = info.sourceDataSize
        
        return noErr

    }
    
    // MARK: Utility Functions
    private func getAudioClassDescription(type: AudioFormatID, manufacturer: UInt32) -> UnsafePointer<AudioClassDescription>? {
        print("getAudioClassDescription() called")
        print("getAudioClassDescription type:\(type), manufacturer: \(manufacturer)")
        var propertyDataSize: UInt32 = 0
        var decoderSpecific = type
        
        let formatID = decoderSpecific
        let formatString = String(format: "%c%c%c%c",
                                  (formatID >> 24) & 0xFF,
                                  (formatID >> 16) & 0xFF,
                                  (formatID >> 8) & 0xFF,
                                  formatID & 0xFF)
        print("AudioFormatID: \(formatString)")

        let manufacturerID = (manufacturer)
        let manufacturerString = String(format: "%c%c%c%c",
                                        (manufacturerID >> 24) & 0xFF,
                                        (manufacturerID >> 16) & 0xFF,
                                        (manufacturerID >> 8) & 0xFF,
                                        manufacturerID & 0xFF)
        print("Manufacturer: \(manufacturerString)")

        
//        func AudioFormatGetPropertyInfo(
//            _ inPropertyID: AudioFormatPropertyID,
//            _ inSpecifierSize: UInt32,
//            _ inSpecifier: UnsafeRawPointer?,
//            _ outPropertyDataSize: UnsafeMutablePointer<UInt32>
//        ) -> OSStatus
        let status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders, UInt32(MemoryLayout.size(ofValue: decoderSpecific)), &decoderSpecific, &propertyDataSize)
        //let status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders, UInt32(MemoryLayout<AudioFormatID>.size), &decoderSpecific, &size)
        
        if status != noErr || propertyDataSize == 0 {
            print("Failed to get audio decoder info. status: \(status), size: \(propertyDataSize)")
            return nil
        }
        print("propertyDataSize: \(propertyDataSize)")
        
        let count = Int(propertyDataSize) / MemoryLayout<AudioClassDescription>.size
        var descriptions = [AudioClassDescription](repeating: AudioClassDescription(), count: count)
        
        let status2 = AudioFormatGetProperty(kAudioFormatProperty_Decoders, UInt32(MemoryLayout.size(ofValue: decoderSpecific)), &decoderSpecific, &propertyDataSize, &descriptions)
        
        if status2 != noErr {
            print("Failed to get audio decoder property")
            return nil
        }
        
        //return descriptions.first { $0.mSubType == type && $0.mManufacturer == manuFacturer }.map { UnsafePointer<AudioClassDescription>(bitPattern: $0.hashValue) } ?? nil
        
        // 1. $0.mSubType == type && $0.mManufacturer == manuFacturer 조건을 만족하는 첫번째 요소를 찾음
        // 2. map은 옵셔널 바인딩과 같은 역할을 함. first가 nil이 아니라면 클로저 내부 코드를 실행. (flatMap도 nil일 경우를 대응)
        // 3. desc의 메모리 주소를 UnsafePointer<AudioClassDescription>으로 변환함
        return descriptions.first { $0.mSubType == type && $0.mManufacturer == manufacturer }.flatMap { desc -> UnsafePointer<AudioClassDescription>? in
            return withUnsafePointer(to: desc) { $0 }
        }
    }
    
    private func printAudioStreamBasicDescription(_ asbd: AudioStreamBasicDescription) {
        var formatID = asbd.mFormatID.bigEndian
        let formatStr = withUnsafePointer(to: &formatID) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) {
                String(cString: UnsafePointer($0), encoding: .ascii) ?? "?????"
            }
        }
        print(String(format: "Sample Rate:         %10.0f", asbd.mSampleRate))
        print(String(format: "Format ID:           %s".replacingOccurrences(of: "%s", with: "%@"), formatStr))
        print(String(format: "Format Flags:        %10X", asbd.mFormatFlags))
        print(String(format: "Bytes per Packet:    %10d", asbd.mBytesPerPacket))
        print(String(format: "Frames per Packet:   %10d", asbd.mFramesPerPacket))
        print(String(format: "Bytes per Frame:     %10d", asbd.mBytesPerFrame))
        print(String(format: "Channels per Frame:  %10d", asbd.mChannelsPerFrame))
        print(String(format: "Bits per Channel:    %10d", asbd.mBitsPerChannel))
        print("")
    }
}
