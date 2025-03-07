//
//  AACLATMDecoder.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 3/6/25.
//

import Foundation
import AVFoundation
import AudioToolbox

class AACLATMDecoder {
    private var converter: AudioConverterRef?
    private var inputData: Data
    private var currentPacketOffset: Int = 0
    
    init?() {
        self.inputData = Data()
        
        // AAC-LATM 입력 포맷 (RTP)에서 수신
        var inputFormat = AudioStreamBasicDescription()
        inputFormat.mSampleRate = 16000
        inputFormat.mFormatID = kAudioFormatMPEG4AAC
        inputFormat.mFormatFlags = 0
        inputFormat.mFramesPerPacket = 1024
        inputFormat.mChannelsPerFrame = 1
        inputFormat.mBitsPerChannel = 0
        inputFormat.mBytesPerPacket = 0
        inputFormat.mBytesPerFrame = 0
        
        // PCM 출력 포맷 설정 (16 bit Linear PCM)
        var outputFormat = AudioStreamBasicDescription()
        outputFormat.mSampleRate = 16000
        outputFormat.mFormatID = kAudioFormatLinearPCM
        outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        outputFormat.mFramesPerPacket = 1
        outputFormat.mChannelsPerFrame = 1
        outputFormat.mBitsPerChannel = 16
        outputFormat.mBytesPerPacket = 2
        outputFormat.mBytesPerFrame = 2
        
        let status = AudioConverterNew(&inputFormat, &outputFormat, &converter)
        
        if status != noErr {
            print("AudioConverter Create Error: \(status)")
            return nil
        } else {
            print("AudioConverter Created : \(String(describing: converter))")
        }
    }
    
    private let inputDataCallback: AudioConverterComplexInputDataProc = { (
        inAudioConverter,
        ioNumberDataPackets,
        ioData,
        outDataPacketDescription,
        inUserData
    ) -> OSStatus in
        guard let inUserData = inUserData else { return -1 }
        let decoder = Unmanaged<AACLATMDecoder>.fromOpaque(inUserData).takeUnretainedValue()
        print("decoder: \(decoder)")
        print("inAudioConverter: \(inAudioConverter)\nioNumberDataPackets: \(ioNumberDataPackets)\nioData: \(ioData)\noutDataPacketDescription: \(String(describing: outDataPacketDescription))\ninUserData: \(inUserData)")
        
        print("decoder.currentPacketOffset: \(decoder.currentPacketOffset)")
        print("decoder.inputData.count: \(decoder.inputData.count)")
        print("Int(ioNumberDataPackets.pointee) * 2: \(Int(ioNumberDataPackets.pointee) * 2)")
        guard decoder.currentPacketOffset < decoder.inputData.count else {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        
        let packetSize = min(decoder.inputData.count - decoder.currentPacketOffset, Int(ioNumberDataPackets.pointee) * 2)
        print("packetSize: \(packetSize)")
        
        ioData.pointee.mBuffers.mDataByteSize = UInt32(packetSize)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: packetSize, alignment: 1)
        decoder.inputData.copyBytes(to: ioData.pointee.mBuffers.mData!.assumingMemoryBound(to: UInt8.self), from: decoder.currentPacketOffset..<decoder.currentPacketOffset + packetSize)
        
        decoder.currentPacketOffset += packetSize
        ioNumberDataPackets.pointee = UInt32(packetSize / 2)
        
        if let outDataPacketDescription = outDataPacketDescription {
            outDataPacketDescription.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(ioNumberDataPackets.pointee))
            for i in 0..<Int(ioNumberDataPackets.pointee) {
                outDataPacketDescription.pointee?[i] = AudioStreamPacketDescription(
                    mStartOffset: Int64(i * 2),
                    mVariableFramesInPacket: 0,
                    mDataByteSize: 2
                )
            }
        }
        
        return noErr
    }
    
    func decodeAAC(_ audioData: Data) -> Data? {
        self.inputData = audioData
        self.currentPacketOffset = 0
        
        var outputData = Data()
        var numPacket: UInt32 = 1024
        
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1,
                                  mDataByteSize: numPacket * 2,
                                  mData: UnsafeMutableRawPointer.allocate(byteCount: Int(numPacket * 2), alignment: 1))
        )
        
        let status = AudioConverterFillComplexBuffer(converter!, inputDataCallback, Unmanaged.passUnretained(self).toOpaque(), &numPacket, &bufferList, nil)

        if status == noErr {
            outputData.append(bufferList.mBuffers.mData!.assumingMemoryBound(to: UInt8.self), count: Int(numPacket * 2))
        } else {
            print("AAC Decode Error: \(status)")
        }
        
        
        return outputData
    }
        
}




//
//// 변환 처리
//audioData.withUnsafeBytes { inputBytes in
//    var inputPacketSize: UInt32 = 1
//    var inputPacketDesc = AudioStreamPacketDescription(
//        mStartOffset: 0,
//        mVariableFramesInPacket: 0,
//        mDataByteSize: UInt32(audioData.count)
//    )
//    
//    var outputBuffer = [UInt8](repeating: 0, count: 8192)
//    var outputPacketSize: UInt32 = 1024
//    
//    // User data holds an AudioFileID, input max packet size, and a count of packets read
//    var uData = (inputPacketDesc, inputPacketSize, UnsafeMutablePointer<Int64>.allocate(capacity: 1))
//    
//    // AudioConverterFillComplesBuffer (inAudioConverter: AudioConverterRef,
//    //                                  inInputDataProc: AudioConverterComplexInputDataProc,
//    //                                  inInputDataProcUserData: UnsafeMutableRawPointer?,
//    //                                  ioOutputDataPacketSize: UnsafeMutablePointer<UInt32>,
//    //                                  outOutputData: UnsafeMutablePointer<AudioBufferList>,
//    //                                  outPacketDescription: UnsafeMutablePointer<AudioStreamPacketDescription>?) -> OSStatus
//    // https://stackoverflow.com/questions/14263808/how-to-use-audioconverterfillcomplexbuffer-and-its-callback
//    let status = AudioConverterFillComplexBuffer(converter!, { _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
//        guard let uData = inUserData?.load(as: (AudioFileID, UInt32, UnsafeMutablePointer<Int64>).self) else { return OSStatus()}
//        ioData.pointee.mBuffers.mDataByteSize = uData.1
//        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: Int(uData.1), alignment: 1)
//        outDataPacketDescription?.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(ioNumberDataPackets.pointee))
//        let err = AudioFileReadPacketData(uData.0, false, &ioData.pointee.mBuffers.mDataByteSize, outDataPacketDescription?.pointee, uData.2.pointee, ioNumberDataPackets, ioData.pointee.mBuffers.mData)
//        uData.2.pointee += Int64(ioNumberDataPackets.pointee)
//        return err
//    }, &uData, &numPacket, &bufferList, nil)
//    
//    if status == noErr {
//        outputData.append(outputBuffer, count: Int(outputPacketSize))
//    } else {
//        print("AAC 디코딩 실패: \(status)")
//    }
//}
//return outputData
