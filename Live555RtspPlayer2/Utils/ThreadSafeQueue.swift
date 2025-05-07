//
//  ThreadSafeQueue.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/1/25.
//

import Foundation
import AVFoundation
import VideoToolbox

final class ThreadSafeQueue<T> {
    private var queue: [T] = []
    private let lock = DispatchSemaphore(value: 1)
    
    func enqueue(_ element: T) {
        lock.wait()
        queue.append(element)
        lock.signal()
    }
    
    func dequeue() -> T? {
        lock.wait()
        let element = queue.isEmpty ? nil : queue.removeFirst()
        lock.signal()
        return element
    }
    
    func isEmpty() -> Bool {
        lock.wait()
        let result = queue.isEmpty
        lock.signal()
        return result
    }
    
    func count() -> Int {
        lock.wait()
        let result = queue.count
        lock.signal()
        return result
    }
    
    func printQueue() {
        lock.wait()
        print(queue)
        lock.signal()
    }
    
    func sort(by areInIncreasingOrder: (T, T) -> Bool) {
        lock.wait()
        queue.sort(by: areInIncreasingOrder)
        lock.signal()
    }
    
    // 첫번째 요소 제거하지 않고 읽기만 함
    func peek() -> T? {
        lock.wait()
        let element = queue.first
        lock.signal()
        return element
    }
    
    func removeAll() {
        lock.wait()
        if !queue.isEmpty {
            queue.removeAll()
        }
        lock.signal()
    }
}

extension ThreadSafeQueue where T == (data: Data, rtpTimestamp: UInt32, nalType: UInt8) {
    func enqueuePacket(_ data: Data, timestamp: UInt32, nalType: UInt8) {
        self.enqueue((data, timestamp, nalType))
    }

    func dequeuePacket() -> (data: Data, rtpTimestamp: UInt32, nalType: UInt8)? {
        return self.dequeue()
    }
}

extension ThreadSafeQueue where T == (pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
    func enqueueFrame(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        self.enqueue((pixelBuffer, presentationTimeStamp))
    }
    
    func sortByPresentationTimeStamp() {
        self.sort { lhs, rhs in
            return lhs.presentationTimeStamp < rhs.presentationTimeStamp
        }
    }

    func dequeueFrame() -> (pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime)? {
        return self.dequeue()
    }
}
