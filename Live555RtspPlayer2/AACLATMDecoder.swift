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
        
//        kAudioFormatFlagIsFloat                  = (1 << 0),    // 0x1
//        kAudioFormatFlagIsBigEndian              = (1 << 1),    // 0x2
//        kAudioFormatFlagIsSignedInteger          = (1 << 2),    // 0x4
//        kAudioFormatFlagIsPacked                 = (1 << 3),    // 0x8
//        kAudioFormatFlagIsAlignedHigh            = (1 << 4),    // 0x10
//        kAudioFormatFlagIsNonInterleaved         = (1 << 5),    // 0x20
//        kAudioFormatFlagIsNonMixable             = (1 << 6),    // 0x40
//        kAudioFormatFlagsAreAllClear             = (1 << 31),
        // AAC-LATM 입력 포맷 (RTP)에서 수신
        var inputFormat = AudioStreamBasicDescription()
        inputFormat.mSampleRate = 16000
        inputFormat.mFormatID = kAudioFormatMPEG4AAC
        inputFormat.mFormatFlags = 0 // AAC-LATM(RTP)에서 주로 사용됨
        inputFormat.mFramesPerPacket = 1024 // 프레임당 샘플 수: 1024 (일반적인 AAC 설정)
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
        outputFormat.mBytesPerPacket = 2 // (16bit PCM이므로 2bytes)
        outputFormat.mBytesPerFrame = 2 // (16bit PCM이므로 2bytes)
        
        let status = AudioConverterNew(&inputFormat, &outputFormat, &converter)
        
        if status != noErr {
            print("AudioConverter Create Error: \(status)")
            return nil
        } else {
            print("AudioConverter Created : \(String(describing: converter))")
        }
    }
    
    // 입력 데이터 공급을 위한 콜백 함수를 설정
    // AudioConverter는 입력 데이터를 다 처리할 때까지 AudioConverterFillComplexBuffer를 여러번 호출함
    private let inputDataCallback: AudioConverterComplexInputDataProc = { (
        inAudioConverter,
        ioNumberDataPackets, // 변환할 패킷 개수
        ioData, // 변환기가 사용할 입력 버퍼(AudioBufferList)를 전달하는 포인터
        outDataPacketDescription, // 패킷의 세부 정보를 담을 구조체 (AAC는 가변 길이 패킷을 가짐)
        inUserData // 콜백이 실행될 때 AACLATMDecoder 인스턴스를 참조하기 위한 포인터
    ) -> OSStatus in
        guard let inUserData = inUserData else { return -1 }
        let decoder = Unmanaged<AACLATMDecoder>.fromOpaque(inUserData).takeUnretainedValue()
        print("decoder: \(decoder)")
        //print("inAudioConverter: \(inAudioConverter)\nioNumberDataPackets: \(ioNumberDataPackets)\nioData: \(ioData)\noutDataPacketDescription: \(String(describing: outDataPacketDescription))\ninUserData: \(inUserData)")
        
        print("decoder.currentPacketOffset: \(decoder.currentPacketOffset)")
        print("decoder.inputData.count: \(decoder.inputData.count)")
        print("Int(ioNumberDataPackets.pointee): \(Int(ioNumberDataPackets.pointee))")
        
        // currentPacketOffset이 inpudata.count보다 작아야 변환할 데이터가 남아있는 것
        guard decoder.currentPacketOffset < decoder.inputData.count else {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        
        // ioNumberDataPackets.pointee : 변환기에 제공할 패킷 개수
        // packetSize: 실제 전달할 AAC 데이터 크기
        // min(남은 데이터 크기, 변환기에 요청된 크기)
        /// 남은 데이터 크기보다 변환기에 요청된 크기가 크면, 남은 데이터 크기만큼만 전달
        /// 변환기에 요청된 크기가 작으면, 요청된 만큼의 데이터만 제공
        /// >> 범위를 초과하는 잘못된 메모리 접근을 방지할 수 있다.
        let packetSize = min(decoder.inputData.count - decoder.currentPacketOffset, Int(ioNumberDataPackets.pointee) * 2)
        print("packetSize: \(packetSize)")
        
        if packetSize == 0 {
            ioNumberDataPackets.pointee = 0
            return -1 // 변환 종료
        }
        
//        if let existingData = ioData.pointee.mBuffers.mData {
//            existingData.deallocate()
//        }
        
//        if let existingData = ioData.pointee.mBuffers.mData {
//            if malloc_size(existingData) > 0 { // 메모리가 유효한지 확인
//                existingData.deallocate()
//            }
//        }
        
        ioData.pointee.mBuffers.mDataByteSize = UInt32(packetSize)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: packetSize, alignment: 1)
        decoder.inputData.copyBytes(to: ioData.pointee.mBuffers.mData!.assumingMemoryBound(to: UInt8.self), from: decoder.currentPacketOffset..<decoder.currentPacketOffset + packetSize)
        print("decoder.inputData.copyBytes finished")
        
        decoder.currentPacketOffset += packetSize
        // 일반적으로 AAC-LATM의 1 패킷 크기를 2 바이트로 가정하여 packetSize / 2를 계산
        ioNumberDataPackets.pointee = UInt32(packetSize / 2)
        
        print("checkpoint ioNumberDataPackets.pointee: \(ioNumberDataPackets.pointee)")
        
        if let outDataPacketDescription = outDataPacketDescription {
            outDataPacketDescription.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(ioNumberDataPackets.pointee))
            for i in 0..<Int(ioNumberDataPackets.pointee) {
                outDataPacketDescription.pointee?[i] = AudioStreamPacketDescription(
                    mStartOffset: Int64(i * 2),
                    mVariableFramesInPacket: 0,
                    mDataByteSize: 2
                )
                print("outDataPacketDescription.pointee?[\(i)]: \(String(describing: outDataPacketDescription.pointee?[i]))")
            }
        }
        print("checkpoint inputDataCallback End")
        return noErr
    }
    
    func decodeAAC(_ audioData: Data) -> Data? {
        self.inputData = audioData
        self.currentPacketOffset = 0
        
        var outputData = Data()
        //var numPacket: UInt32 = 1024
        var numPacket: UInt32 = min(1024, UInt32(inputData.count / 2))
        
        // pcm 데이터를 저장할 AudioBufferList 생성
        // 16bit PCMa 데이터는 한 샘플당 2 바이트를 차지하므로 numPacket * 2만큼 메모리 할당 
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1,
                                  mDataByteSize: numPacket * 2,
                                  mData: UnsafeMutableRawPointer.allocate(byteCount: Int(numPacket * 2), alignment: 1))
        )
        print("bufferList: \(bufferList)")
        
        let status = AudioConverterFillComplexBuffer(converter!, inputDataCallback, Unmanaged.passUnretained(self).toOpaque(), &numPacket, &bufferList, nil)
        
        print("checkpoint AudioConverterFillComplexBuffer End")
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
