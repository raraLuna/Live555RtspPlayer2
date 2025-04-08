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
    var packetDesc: UnsafeMutablePointer<AudioStreamPacketDescription>?
}

class AudioDecoder {
    private var audioConverter: AudioConverterRef?
    private var sourceFormat: AudioStreamBasicDescription
    private var destinationFormat: AudioStreamBasicDescription
    
    private let audioQueue: ThreadSafeQueue<Data>
    //private let audioSemaphore = DispatchSemaphore(value: 1)
    
    init(formatID: AudioFormatID, useHardwareDecode: Bool, audioQueue: ThreadSafeQueue<Data>) {
        //print("init Decoder")
        self.sourceFormat = AudioStreamBasicDescription()
        self.destinationFormat = AudioStreamBasicDescription()
        self.audioQueue = audioQueue
        self.audioConverter = configureDecoder(sourceFormat: &self.sourceFormat, destFormat: &self.destinationFormat, formatID: formatID, useHardwareDecode: useHardwareDecode)
    }
    
    deinit {
        freeDecoder()
    }
    
    // MARK: Public Functions
    //func decodeAudio(sourceBuffer: UnsafeMutableRawPointer, sourceBufferSize: UInt32, completion: @escaping (AudioBufferList, UInt32, AudioStreamPacketDescription?) -> Void) {
    func decodeAudio(completion: @escaping (AudioBufferList, UInt32, AudioStreamPacketDescription?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            //self.audioSemaphore.wait()
            //print("decodeAudio decode Semaphore wait")
            while true {
                if let audioData = self.audioQueue.dequeue() {
                    let sourceData: [UInt8] = [UInt8](audioData)
                    let sourceBufferSize = UInt32(sourceData.count)
                    guard sourceBufferSize > 0 else { return }
                    let sourceBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(sourceBufferSize), alignment: 4)
                    sourceData.withUnsafeBytes { rawBuffer in
                        if let baseAddress = rawBuffer.baseAddress {
                            sourceBuffer.copyMemory(from: baseAddress, byteCount: Int(sourceBufferSize))
                        }
                    }
                    self.decodeFormat(converter: self.audioConverter, sourceBuffer: sourceBuffer, sourceBufferSize: sourceBufferSize, sourceFormat: self.sourceFormat, destFormat: self.destinationFormat, completion: completion)
                    
                    sourceBuffer.deallocate()
                    print("sourceBuffer.deallocate()")
                }
            }
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
        }
    }
    
    func freeDecoder() {
        //print("freeDecoder")
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
    }
    
    // MARK: Private Functions
    private func configureDecoder(sourceFormat: inout AudioStreamBasicDescription, destFormat: inout AudioStreamBasicDescription, formatID: AudioFormatID, useHardwareDecode: Bool) -> AudioConverterRef? {
//        if formatID != kAudioFormatLinearPCM {
//            print("Unsupported format after decoding")
//            return nil
//        }
        // mFormatFlags:
        ///오디오 데이터의 속성(Endian, 부호, Float/Integer, 패킹 여부 등을 설정
        ///사용하는 값은 formatID에 따라 다름
        ///kAudioFormatFlagsIsSignedInteger: 정수형(Integer) PCM 데이터
        ///kAudioFormatFlagIsFloat: 부동소수점(Float) PCM 데이터
        ///kAudioFormatFlagIsBigEndian: 빅 엔디안(Big Endian) 데이터
        ///kAudioFormatFlagIsPacked: 패킹된(Packed) 데이터
        ///kAudioFormatFlagIsNonInterleaved: 채널을 분리하여 저장 (Planar Format)
        ///
        ///mFormatID = kAudioFormatLinearPCM
        ///mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        ///
        ///mFormatID = kAudioFormatMPEG4AAC
        ///mFormatFlags = 0
        ///
        // mBytePerPacket:
        ///오디오 데이터가 패킷 단위로 저장될 때, 패킷 하나의 크기(Byte)
        ///mFormatID에 따라 계산 방식이 다르다
        ///PCM, 16bit의 경우: 2 (16-bit) * 2 (채널) = 4 bytes
        ///AAC의 경우는 패킷크기가 가변적이므로 0
        ///
        // mFramesPerPacket:
        ///하나의 패킷이 몇개의 프레임이 포함하는가
        ///PCM: 항상 1프레임 = 1패킷
        ///AAC: 한 패킷당 1024프레임이 기본
        sourceFormat.mSampleRate = Float64(16000.0) // 샘플링 레이트(Hz)
        sourceFormat.mFormatID = kAudioFormatMPEG4AAC // 오디오 포맷 ID
        sourceFormat.mFormatFlags = 0 // 포맷에 대한 플래그
        //sourceFormat.mFormatFlags = kAudioFileMPEG4Type // 포맷에 대한 플래그
        sourceFormat.mFramesPerPacket = 1024 // 패킷당 프레임 수
        sourceFormat.mChannelsPerFrame = 1 // 프레임당 채널 수
        sourceFormat.mBitsPerChannel = 0 // 채널당 비트 수
        sourceFormat.mBytesPerPacket = 0 // 패킷당 바이트 수
        sourceFormat.mBytesPerFrame = 0 // 프레임당 바이트 수
        sourceFormat.mReserved = 0 // 예약된 값 (항상 0)
        //printAudioStreamBasicDescription(sourceFormat)
        
        destFormat.mSampleRate = Float64(16000.0)
        destFormat.mFormatID = kAudioFormatLinearPCM
        destFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        destFormat.mFramesPerPacket = 1
        destFormat.mBitsPerChannel = 16
        destFormat.mChannelsPerFrame = 1
        destFormat.mBytesPerFrame = 2
        destFormat.mBytesPerPacket = 2
        //destFormat.mBytesPerFrame = destFormat.mBitsPerChannel / 8 * destFormat.mChannelsPerFrame
        //destFormat.mBytesPerPacket = destFormat.mBytesPerFrame * destFormat.mFramesPerPacket
        //print("destFormat.mFormatFlags: \(destFormat.mFormatFlags)")
        //printAudioStreamBasicDescription(destFormat)
        
        guard let audioClassDesc = getAudioClassDescription(type: formatID, manufacturer: kAppleSoftwareAudioCodecManufacturer) else {
            print("configureDecoder audioClassDesc failed")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
            return nil
        }
        
        //var converter: AudioConverterRef?
        let status = AudioConverterNewSpecific(&sourceFormat, &destFormat, destFormat.mChannelsPerFrame, audioClassDesc, &audioConverter)
        //let status = AudioConverterNew(&sourceFormat, &destFormat, &converter)
        
        if status != noErr {
            print("Audio Converter creation failed")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
            return nil
        }
        
        //print("Audio converter created successfully")
        return audioConverter
    }
    
    private func decodeFormat(converter: AudioConverterRef?, sourceBuffer: UnsafeMutableRawPointer, sourceBufferSize: UInt32, sourceFormat: AudioStreamBasicDescription, destFormat: AudioStreamBasicDescription, completion: @escaping (AudioBufferList, UInt32, AudioStreamPacketDescription?) -> Void) {
        //print("decodeFormat() called")
        guard let converter = converter else { print("converter is nil")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
            return }
        
        let ioOutputDataPackets: UInt32 = 1024 // 변환 예정인 패킷 수(AAC는 1024 고정)
        // 패킷 개수 x 채널 수 x 바이트 크기 (PCM의 경우 한 프레임 당 mBytesPerFrame만큼의 데이터를 가짐
        let outputBufferSize = ioOutputDataPackets * destFormat.mChannelsPerFrame * destFormat.mBytesPerFrame
        //print("outputBufferSize: \(outputBufferSize)")
        
        var fillBufferList = AudioBufferList()
        fillBufferList.mNumberBuffers = 1
        fillBufferList.mBuffers.mNumberChannels = destFormat.mChannelsPerFrame
        fillBufferList.mBuffers.mDataByteSize = outputBufferSize
        //fillBufferList.mBuffers.mData = malloc(Int(outputBufferSize))
        fillBufferList.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: Int(outputBufferSize), alignment: 4)
        
        // `packetDesc` 메모리 할당
        // PCM 변환이라면 packetDescPointer를 굳이 사용할 필요가 없음 → nil 전달 가능
        let packetDescPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        packetDescPointer.initialize(to: AudioStreamPacketDescription(mStartOffset: 0,
                                                                      mVariableFramesInPacket: 0,
                                                                      mDataByteSize: sourceBufferSize))
        
        var userInfo = ConverterInfo(sourceChannelsPerFrame: sourceFormat.mChannelsPerFrame,
                                     sourceDataSize: sourceBufferSize,
                                     sourceBuffer: sourceBuffer,
                                     packetDesc: packetDescPointer
        )
        //print("userInfo: \(userInfo)")
        
        // `outputPacketDesc` 메모리 할당
        // PCM 변환에서는 패킷 설명이 필요 없으므로 nil로 설정 가능
        let outputPacketDescPointer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        outputPacketDescPointer.initialize(to: AudioStreamPacketDescription())

        var numPackets = ioOutputDataPackets
        //print("numPackets: \(numPackets)")

        // `AudioConverterFillComplexBuffer` 호출
        let status = AudioConverterFillComplexBuffer(
            converter,
            decodeConverterComplexInputDataProc,
            &userInfo,
            &numPackets,
            &fillBufferList,
            nil
        )

        if status != noErr {
            print("AudioConverterFillComplexBuffer failed: \(status)")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
            return
        }
        
        verifyDecodedAudio(bufferList: fillBufferList, expectedFormat: destFormat)

        
        // `completion` 블록 실행
        completion(fillBufferList, numPackets, outputPacketDescPointer.pointee)

        // 메모리 해제
        packetDescPointer.deallocate()
        //print("packetDescPointer.deallocate()")
        outputPacketDescPointer.deallocate()
        //print("outputPacketDescPointer.deallocate()")
        fillBufferList.mBuffers.mData?.deallocate()
        //print("fillBufferList.mBuffers.mData?.deallocate()")
    }
    
    func verifyDecodedAudio(bufferList: AudioBufferList, expectedFormat: AudioStreamBasicDescription) {
        let buffer = bufferList.mBuffers
        
        //print("✅ Decoded Audio Verification")
        //print(" - Number of Buffers: \(bufferList.mNumberBuffers)")
        //print(" - Data Byte Size: \(buffer.mDataByteSize)")
        //print(" - Number of Channels: \(buffer.mNumberChannels)")
        
        if bufferList.mNumberBuffers != 1 {
            print("⚠️ Warning: Unexpected number of buffers!")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
        }
        
        if buffer.mNumberChannels != expectedFormat.mChannelsPerFrame {
            print("❌ Channel count mismatch! Expected: \(expectedFormat.mChannelsPerFrame), Got: \(buffer.mNumberChannels)")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
        }
        
        if buffer.mDataByteSize == 0 || buffer.mData == nil {
            print("❌ No audio data found!")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
        } else {
            print("✅ Audio data is present")
        }
    }
    
    
    // MARK: Audio Converter Input Data Callback
    private let decodeConverterComplexInputDataProc: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
        //print("decodeConverterComplexInputDataProc")
        guard let inUserData = inUserData else {
            return -1
        }
        
        var info = inUserData.assumingMemoryBound(to: ConverterInfo.self).pointee
        
        if info.sourceDataSize <= 0 {
            ioNumberDataPackets.pointee = 0
            return -1
        }
        
        //print("info.sourceDataSize: \(info.sourceDataSize), \ninfo.sourceChannelsPerFrame: \(info.sourceChannelsPerFrame), \ninfo.sourceBuffer: \(String(describing: info.sourceBuffer)), \ninfo.packetDesc: \(String(describing: info.packetDesc))")
        
        // outDataPacketDescription 타입: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>
        // packetDesc 타입: UnsafeMutablePointer<AudioStreamPacketDescription>?
        // packetDesc.pointee 타입: AudioStreamPacketDescription
        // pointee : The data or object referenced by a pointer.
        // pointer : variable that stores the memory address of another variable as its value.
        guard let outDataPacketDescription = outDataPacketDescription else { return -1 }
        if let packetDesc = info.packetDesc{
            //outDataPacketDescription.pointee = packetDesc.pointee
            outDataPacketDescription.pointee = packetDesc
        }
        
        
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = info.sourceBuffer
        ioData.pointee.mBuffers.mNumberChannels = info.sourceChannelsPerFrame
        ioData.pointee.mBuffers.mDataByteSize = info.sourceDataSize
        return noErr

    }
    
    
    // MARK: Utility Functions
    private func getAudioClassDescription(type: AudioFormatID, manufacturer: UInt32) -> UnsafePointer<AudioClassDescription>? {
        //print("getAudioClassDescription() called")
        //print("getAudioClassDescription type:\(type), manufacturer: \(manufacturer)")
        var propertyDataSize: UInt32 = 0
        var decoderSpecific = type
        
        let formatID = decoderSpecific
        let formatString = String(format: "%c%c%c%c",
                                  (formatID >> 24) & 0xFF,
                                  (formatID >> 16) & 0xFF,
                                  (formatID >> 8) & 0xFF,
                                  formatID & 0xFF)
        //print("AudioFormatID: \(formatString)")

        let manufacturerID = (manufacturer)
        let manufacturerString = String(format: "%c%c%c%c",
                                        (manufacturerID >> 24) & 0xFF,
                                        (manufacturerID >> 16) & 0xFF,
                                        (manufacturerID >> 8) & 0xFF,
                                        manufacturerID & 0xFF)
        //print("Manufacturer: \(manufacturerString)")

        
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
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
            return nil
        }
        //print("propertyDataSize: \(propertyDataSize)")
        
        let count = Int(propertyDataSize) / MemoryLayout<AudioClassDescription>.size
        var descriptions = [AudioClassDescription](repeating: AudioClassDescription(), count: count)
        
        let status2 = AudioFormatGetProperty(kAudioFormatProperty_Decoders, UInt32(MemoryLayout.size(ofValue: decoderSpecific)), &decoderSpecific, &propertyDataSize, &descriptions)
        
        if status2 != noErr {
            print("Failed to get audio decoder property")
            //self.audioSemaphore.signal()
            //print("decodeAudio decode Semaphore signal")
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
        print("Format ID:           \(formatStr)")
        print(String(format: "Format Flags:        %10X", asbd.mFormatFlags))
        print(String(format: "Bytes per Packet:    %10d", asbd.mBytesPerPacket))
        print(String(format: "Frames per Packet:   %10d", asbd.mFramesPerPacket))
        print(String(format: "Bytes per Frame:     %10d", asbd.mBytesPerFrame))
        print(String(format: "Channels per Frame:  %10d", asbd.mChannelsPerFrame))
        print(String(format: "Bits per Channel:    %10d", asbd.mBitsPerChannel))
        print("")
    }
}



//
//extension FixedWidthInteger {
//    var littleEndianData: Data {
//        withUnsafeBytes(of: self.littleEndian, { Data($0) })
//    }
//}


// wav 파일로 생성 -> 재생 안됨 header 생성 틀렸을 가능성 있음

//let data = Data(bytes: fillBufferList.mBuffers.mData!, count: Int(fillBufferList.mBuffers.mDataByteSize))
//print("pcm data: \(data)")
//
//for _ in 0..<20 {
//    wavTestData.append(data)
//    
//}
//print("wavTestData.count: \(wavTestData.count)")
//if wavTestData.count > 40000 {
//    let wavHeader = createWavHeader(sampleRate: 16000, numChannels: 1, bitsPerSample: 16, dataSize: UInt32(data.count))
//    let wavFilePath = FileManager.default.temporaryDirectory.appendingPathComponent("wav_dump.wav").path()
//    let fileURL = URL(fileURLWithPath: wavFilePath)
//
//    if !FileManager.default.fileExists(atPath: fileURL.path) {
//        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
//    }
//    else {
//        do {
//            try FileManager.default.removeItem(at: fileURL)
//        } catch {
//            print("failed remove existing file")
//        }
//    }
//
//    do {
//        try wavHeader.write(to: fileURL)
//        let fileHandle = try FileHandle(forWritingTo: fileURL)
//        fileHandle.seekToEndOfFile()
//        fileHandle.write(wavTestData)
//        fileHandle.closeFile()
//        wavTestData = Data()
//        print("WAV Dump saved at \(wavFilePath)")
//    } catch {
//        print("save wav file failed")
//    }
//    
//}

///// WAV 파일 헤더 생성 함수
//func createWavHeader(sampleRate: UInt32, numChannels: UInt16, bitsPerSample: UInt16, dataSize: UInt32) -> Data {
//    let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
//    let blockAlign = numChannels * (bitsPerSample / 8)
//    let chunkSize = 36 + dataSize // 전체 파일 크기 - 8
//    var header = Data()
//
//    header.append("RIFF".data(using: .ascii)!)               // ChunkID (RIFF)
//    header.append(UInt32(chunkSize).littleEndianData)       // ChunkSize
//    header.append("WAVE".data(using: .ascii)!)              // Format
//
//    header.append("fmt ".data(using: .ascii)!)              // Subchunk1ID
//    header.append(UInt32(16).littleEndianData)              // Subchunk1Size (16 for PCM)
//    header.append(UInt16(1).littleEndianData)               // AudioFormat (1 = PCM)
//    header.append(numChannels.littleEndianData)             // NumChannels
//    header.append(sampleRate.littleEndianData)              // SampleRate
//    header.append(byteRate.littleEndianData)                // ByteRate
//    header.append(blockAlign.littleEndianData)              // BlockAlign
//    header.append(bitsPerSample.littleEndianData)           // BitsPerSample
//
//    header.append("data".data(using: .ascii)!)              // Subchunk2ID
//    header.append(dataSize.littleEndianData)                // Subchunk2Size
//
//    print("wav header created: \(header)")
//    return header
//}







// 링버퍼 형식: 누적하면서 부분 데이터 output 및 부분 데이터 input
//class PCMRingBuffer {
//    private let queue = DispatchQueue(label: "com.pcmRignBuffer.queue", attributes: .concurrent)
//    private var buffer = Data()
//    private let maxSize: Int
//
//    init(maxSize: Int) {
//        self.maxSize = maxSize
//    }
//
//    // PCM 데이터 추가 (오래 된 데이터는 자동 삭제 되도록)
//    func append(_ newData: Data) {
//        if newData.count + buffer.count >= maxSize {
//            let removeDataSize = newData.count + buffer.count - maxSize
//            self.buffer.removeFirst(removeDataSize)
//        }
//
//        queue.async(flags: .barrier) {
//            self.buffer.append(newData)
//        }
//    }
//
//    // 일정 크기(Chunk) 만큼 데이터 꺼내기
//    func readChunk(size: Int) -> Data? {
//        return queue.sync {
//            guard buffer.count >= size else { return nil } // 데이터가 충분하지 않은 경우
//            let chunk = buffer.prefix(size)
//            buffer.removeFirst(size) // 읽은 데이터 제거
//            return chunk
//        }
//    }
//
//    // 현재 버퍼 크기 확인
//    func currentSize() -> Int {
//        return queue.sync {
//            buffer.count
//        }
//    }
//
//    // 버퍼 초기화
//    func clear() {
//        queue.async(flags: .barrier){
//            self.buffer.removeAll()
//        }
//    }
//}
