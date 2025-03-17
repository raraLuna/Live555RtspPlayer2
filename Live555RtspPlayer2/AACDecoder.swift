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
    var audioConverter: AudioConverterRef?
    var audioQueue: AudioQueueRef?
    
    let sampleRate: Float64 = 16000
    let numChannels: UInt32 = 1
    let aacBufferSize: UInt32 = 2048
    let packetSize: UInt32 = 1024 // AAC-LC 기준 한 프레임 크기
    
    init() {
        setupAudioConverter()
    }
    
    func setupAudioConverter() {
        var inputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: packetSize,
            mBytesPerFrame: 0,
            mChannelsPerFrame: numChannels,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        
        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
            mBytesPerPacket: numChannels * 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: numChannels * 2,
            mChannelsPerFrame: numChannels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        let status = AudioConverterNew(&inputFormat, &outputFormat, &audioConverter)
        if status != noErr {
            print("AudioConverter 생성 실패: \(status)")
        }
    }
    
    func processRtpPacket(_ packet: Data) {
        guard packet.count > 2 else { return }
        
        var auHeaderSize = 0
        var auSize = 0
        print("packet.count: \(packet.count)")
        if packet.starts(with: [255]) {
            auHeaderSize  = 2
            print("auHeaderSize: \(auHeaderSize), packet[0]: \(packet[0]), packet[1]: \(packet[1])")
            // AU Header에서 AAC 데이터 크기 추출
            auSize = Int(packet[0]) + Int(packet[1])
            print("Int(packet[0]): \(Int(packet[0]))")
            print("Int(packet[1]): \(Int(packet[1]))")
        } else {
            auHeaderSize  = 1
            print("auHeaderSize: \(auHeaderSize), packet[0]: \(packet[0])")
            auSize = Int(packet[0])
        }
        print("auSize: \(auSize)")
        
        guard packet.count >= auHeaderSize + auSize else { return }
        
        let aacData = packet.subdata(in: auHeaderSize..<(auHeaderSize + auSize)) // 순수 AAC 데이터
        print("aac raw Data : \(aacData) bytes")
        
        decodeAACFrame(aacData)
    }
    
    func decodeAACFrame(_ aacData: Data) {
        var outputBuffer = [UInt8](repeating: 0, count: Int(aacBufferSize))
        var outputPacketSize: UInt32 = 1
        var inputBufferList = AudioBufferList()
        inputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: numChannels, mDataByteSize: UInt32(aacData.count), mData: UnsafeMutableRawPointer(mutating: (aacData as NSData).bytes))
        )
        
        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: numChannels, mDataByteSize: aacBufferSize, mData: &outputBuffer)
        )
        
        let status = AudioConverterFillComplexBuffer(audioConverter!, { _, ioNumberDataPackets, ioData, ioPacketDesc, inUserData in
            let uData = inUserData!.load(as: (AudioFileID, UInt32, UnsafeMutablePointer<Int64>).self)
            ioData.pointee.mBuffers.mDataByteSize = uData.1
            ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: Int(uData.1), alignment: 1)
            ioPacketDesc?.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(ioNumberDataPackets.pointee))
            let err = AudioFileReadPacketData(uData.0, false, &ioData.pointee.mBuffers.mDataByteSize, ioPacketDesc?.pointee, uData.2.pointee, ioNumberDataPackets, ioData.pointee.mBuffers.mData)
            uData.2.pointee += Int64(ioNumberDataPackets.pointee)
            return err
            
//                ioData.pointee.mBuffers.mData = inUserData
//                ioData.pointee.mBuffers.mDataByteSize = UInt32(aacData.count)
//                ioNumberDataPackets.pointee = 1
//                return noErr
        }, &inputBufferList, &outputPacketSize, &outputBufferList, nil)
        
        if status == noErr {
            print("AAC 디코딩 완료: \(status)")
            //playPCMData(outputBufferList)
        } else {
            print("AAC 디코딩 실패: \(status)")
        }
    }
}







//class AACDecoder {
//    private var audioConverter: AudioConverterRef?
//    private var inputFormat: AudioStreamBasicDescription
//    private var outputFormat: AudioStreamBasicDescription
//    private var inputData: Data?
//    
//    init() {
//        // AAC (ADTS) 입력 포맷 설정(16,000Hz, Channel mono)
//        inputFormat = AudioStreamBasicDescription(mSampleRate: 16000,
//                                                  mFormatID: kAudioFormatMPEG4AAC,
//                                                  mFormatFlags: 0,
//                                                  mBytesPerPacket: 0,
//                                                  mFramesPerPacket: 1024,
//                                                  mBytesPerFrame: 0,
//                                                  mChannelsPerFrame: 1,
//                                                  mBitsPerChannel: 0,
//                                                  mReserved: 0)
//        
//        // PCM 출력 포맷 설정(16,000Hz, Linesr PCM)
//        outputFormat = AudioStreamBasicDescription(mSampleRate: 16000,
//                                                   mFormatID: kAudioFormatLinearPCM,
//                                                   mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
//                                                   mBytesPerPacket: 2,
//                                                   mFramesPerPacket: 1,
//                                                   mBytesPerFrame: 2,
//                                                   mChannelsPerFrame: 1,
//                                                   mBitsPerChannel: 16,
//                                                   mReserved: 0)
//        
//        setupAudioConverter()
//    }
//    
//    private func setupAudioConverter() {
//        print("setupAudioConverter() Called")
//        var status : OSStatus = -1
//        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
//        status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &outputFormat)
//            
//        if status != noErr {
//            print("AudioFormatGetProperty kAudioFormatProperty_FormatInfo error: \(status)")
//            return
//        }
//        print("AudioFormatGetProperty size: \(size)")
//        print("outputFormat: \(outputFormat)")
//        
//        guard let description = getAudioClassDescription(type: &outputFormat.mFormatID, manufacturer: kAppleSoftwareAudioCodecManufacturer) else {
//            print("Get audio class description error")
//            return
//        }
//        
//        //var status = AudioConverterNewSpecific(&inputFormat, &outputFormat, 0, nil, &audioConverter)
//        status = AudioConverterNewSpecific(&inputFormat, &outputFormat, outputFormat.mChannelsPerFrame, description, &audioConverter)
//        if status != noErr {
//            print("AudioConverter create failed: \(status)")
//        }
//    }
//    
//    // MARK: WHY getAudioClassDescription CREATE FAIL!!!!
//    private func getAudioClassDescription(type: inout UInt32, manufacturer: UInt32) -> UnsafePointer<AudioClassDescription>? {
//        var encoderDescription = [AudioClassDescription]()
//        var size: UInt32 = 0
//        
//        // type: outputFormat.mFormatID == 1819304813 (kAudioFormatLinearPCM)
//        var status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, UInt32(MemoryLayout.size(ofValue: type)), &type, &size)
//        
//        if status != noErr {
//            print("AudioFormatGetPropertyInfo error: \(status)")
//            return nil
//        }
//        print("AudioFormatGetPropertyInfo status: \(status)")
//        print("AudioFormatGetPropertyInfo type: \(type)")
//        print("AudioFormatGetPropertyInfo size: \(size)")
//        
//        let count = Int(size) / MemoryLayout<AudioClassDescription>.size
//        encoderDescription = Array(repeating: AudioClassDescription(mType: 0, mSubType: 0, mManufacturer: 0), count: count)
//
//        status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, UInt32(MemoryLayout.size(ofValue: type)), &type, &size, &encoderDescription)
//        
//        if status != noErr {
//            print("AudioFormatGetProperty error: \(status)")
//            return nil
//        }
//        print("AudioFormatGetProperty status: \(status)")
//        print("encoderDescription.description: \(encoderDescription.description)")
//        
//        for desc in encoderDescription {
//            if desc.mManufacturer == manufacturer {
//                print("desc.mManufacturer == manufacturer")
//                //return UnsafePointer<AudioClassDescription>(&desc)
//            }
//        }
////        if let index = encoderDescription.firstIndex(where: { $0.mManufacturer == manufacturer }) {
////            return withUnsafePointer(to: &encoderDescription[index]) { $0 }
////        }
//        
//        print("encoderDescription not found for manufacturer: \(manufacturer), status: \(status)")
//        
//        return nil
//    }
//    
//    private func removeADTSHeader(from data: Data) -> Data {
//        guard data.count > 7 else { return Data() }
//        let adtsHeaderSize = (data[1] & 0x03) << 11 | (data[2] << 3) | ((data[3] & 0xE0) >> 5)
//        return data.suffix(from: Int(adtsHeaderSize))
//    }
//    
//    func decode(aacData: Data) -> Data? {
//        inputData = removeADTSHeader(from: aacData)
//        
//        var outputBuffer = [UInt8](repeating: 0, count: 4096)
//        var outputPacketSize: UInt32 = 1
//        
//        var outputPacketDescription = AudioStreamPacketDescription(mStartOffset: 0,
//                                                                   mVariableFramesInPacket: 0,
//                                                                   mDataByteSize: UInt32(outputBuffer.count))
//        
//        var outputBufferList = AudioBufferList(mNumberBuffers: 1,
//                                               mBuffers: AudioBuffer(mNumberChannels: 1,
//                                                                     mDataByteSize: UInt32(outputBuffer.count),
//                                                                     mData: &outputBuffer))
//        
//        let status = AudioConverterFillComplexBuffer(audioConverter!,
//                                                             decodeInputCallback,
//                                                             UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
//                                                             &outputPacketSize,
//                                                             &outputBufferList,
//                                                             &outputPacketDescription)
//        if status != noErr {
//            print("오디오 디코딩 실패: \(status)")
//            return nil
//        }
//        
//        return Data(bytes: outputBuffer, count: Int(outputBufferList.mBuffers.mDataByteSize))
//    }
//    
//    /// AudioConverter의 입력 콜백 함수
//    private let decodeInputCallback: AudioConverterComplexInputDataProc = { inAudioConverter, ioNumberDataPackets, ioData, ioPacketDescription, inUserData in
//        let decoder = Unmanaged<AACDecoder>.fromOpaque(inUserData!).takeUnretainedValue()
//
//        guard let inputData = decoder.inputData, inputData.count > 0 else {
//            return -1
//        }
//
//        ioData.pointee.mNumberBuffers = 1
//        ioData.pointee.mBuffers.mNumberChannels = 1
//        ioData.pointee.mBuffers.mDataByteSize = UInt32(inputData.count)
//        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: (inputData as NSData).bytes)
//
//        ioNumberDataPackets.pointee = 1
//        return noErr
//    }
//}












//    private var audioFormat: AVAudioFormat?
//    private var converter: AVAudioConverter?
//    
//    func decodeAACData(_ aacData: Data) {
//        var formatDescription: CMAudioFormatDescription?
//        // asbd: Audio Stream Basic Description
//        var asbd = AudioStreamBasicDescription(mSampleRate: 16000, // AAC 샘플 레이트
//                                               mFormatID: kAudioFormatMPEG4AAC,
//                                               mFormatFlags: 0,
//                                               mBytesPerPacket: 0,
//                                               mFramesPerPacket: 1024, // AAC
//                                               mBytesPerFrame: 0,
//                                               mChannelsPerFrame: 1, // 모노
//                                               mBitsPerChannel: 0,
//                                               mReserved: 0)
//        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
//                                                    asbd: &asbd, // & 연산자로 포인터 전달
//                                                    layoutSize: 0,
//                                                    layout: nil,
//                                                    magicCookieSize: 0,
//                                                    magicCookie: nil,
//                                                    extensions: nil,
//                                                    formatDescriptionOut: &formatDescription)
//        guard status == noErr, let formatDesc = formatDescription else {
//            print("Failed to create format description")
//            return
//        }
//        print("formatDescription created: \(String(describing: formatDescription))")
//        
//        var blockBuffer: CMBlockBuffer?
//        status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
//                                                    memoryBlock: UnsafeMutableRawPointer(mutating: (aacData as NSData).bytes),
//                                                    blockLength: aacData.count,
//                                                    blockAllocator: kCFAllocatorNull,
//                                                    customBlockSource: nil,
//                                                    offsetToData: 0,
//                                                    dataLength: aacData.count,
//                                                    flags: 0,
//                                                    blockBufferOut: &blockBuffer)
//        guard status == noErr,let blockBuffer = blockBuffer else {
//            print("Failed to create block buffer")
//            return
//        }
//        
//        print("blockBuffer create success: \(blockBuffer)")
//        print("blockBuffer dataLength: \(blockBuffer.dataLength)")
//        
//
//        
//        aacData.withUnsafeBytes { rawBufferPointer in
//            guard let rawPointer = rawBufferPointer.baseAddress else { return }
//            let status = CMBlockBufferReplaceDataBytes(with: rawPointer,
//                                                   blockBuffer: blockBuffer,
//                                                   offsetIntoDestination: 0,
//                                                   dataLength: aacData.count)
//            guard status == noErr else {
//                print("Failed to copy data to block buffer")
//                return
//            }
//        }
//        
//        var dataLength = aacData.count
//        var sampleBuffer: CMSampleBuffer?
//        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
//                                            presentationTimeStamp: CMTime.zero,
//                                            decodeTimeStamp: CMTime.invalid)
//        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
//                                           dataBuffer: blockBuffer,
//                                           formatDescription: formatDesc,
//                                           sampleCount: 1,
//                                           sampleTimingEntryCount: 1,
//                                           sampleTimingArray: &timingInfo,
//                                           sampleSizeEntryCount: 1,
//                                           sampleSizeArray: &dataLength,
//                                           sampleBufferOut: &sampleBuffer)
//        
//        guard status == noErr, let sampleBuffer = sampleBuffer else {
//            print("Failed to create sample buffer")
//            return
//        }
//        
//        print("sampleBuffer create success: \(sampleBuffer)")
//        print("totalSampleSize: \(sampleBuffer.totalSampleSize)")
//        
//        guard let format = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)!) else {
//                print("Invalid audio format")
//                return
//            }
//        //audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.pointee.mSampleRate, channels: format.pointee.mChannelsPerFrame, interleaved: false)
//        audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: format.pointee.mSampleRate, channels: format.pointee.mChannelsPerFrame, interleaved: false)
//        if let format = audioFormat {
//            guard let pcmBuffer = self.convertSampleBufferToPCMBuffer(sampleBuffer, format: format) else {
//                return
//            }
//            print("now play pcm buffer")
//            let audioPlayer = AudioPlayer(format: format)
//            
//            audioPlayer.appendBuffer(pcmBuffer)
//        }
//    }
//    
//    func convertSampleBufferToPCMBuffer(_ sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
//        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
//            print("Failed to get data buffer from sample buffer")
//            return nil
//        }
//        
//        var dataPointer: UnsafeMutablePointer<Int8>?
//        var dataLength = 0
//        let status = CMBlockBufferGetDataPointer(blockBuffer,
//                                    atOffset: 0,
//                                    lengthAtOffsetOut: nil,
//                                    totalLengthOut: &dataLength,
//                                    dataPointerOut: &dataPointer)
//        guard status == noErr, let audioData = dataPointer else {
//            print("Failed to get audio data pointer")
//            return nil
//        }
//        
//        let bytePerFrame = format.streamDescription.pointee.mBytesPerPacket
//        let frameCount = AVAudioFrameCount(dataLength) / AVAudioFrameCount(bytePerFrame)
//        
//        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
//                                            frameCapacity: frameCount) else {
//            print("Failed to create AVAudioPCMBuffer")
//            return nil
//        }
//        buffer.frameLength = frameCount
//        print("buffer.frameLength: \(buffer.frameLength)")
//        
//        print("audioData: \(audioData)")
//        print("buffer.frameLength: \(buffer.frameLength)")
//        
//        if let int16Data = buffer.int16ChannelData{
//            memcpy(int16Data.pointee, audioData, dataLength)
//            
//        } else if let floatData = buffer.floatChannelData {
//            memcpy(floatData.pointee, audioData, dataLength)
//        } else {
//            print("Check PCM format. It is not int16 and float")
//        }
//        print("AVAudioPCMBuffer created successfully: \(buffer)")
//        
//        return buffer
//    }
//}

