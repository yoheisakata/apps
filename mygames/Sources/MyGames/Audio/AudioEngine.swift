import AVFAudio
import Foundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private let lock = NSLock()
    private var ringBuffer: [Float] = Array(repeating: 0, count: 16384)
    private var writePos = 0
    private var readPos = 0
    private var sampleRate: Double = 44100

    func start(sampleRate: Double) {
        stop()
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100

        let format = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: 2)!

        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            let count = Int(frameCount)

            self.lock.lock()
            for frame in 0..<count {
                let left: Float
                let right: Float
                if self.readPos != self.writePos {
                    left = self.ringBuffer[self.readPos]
                    self.readPos = (self.readPos + 1) % self.ringBuffer.count
                    right = self.ringBuffer[self.readPos]
                    self.readPos = (self.readPos + 1) % self.ringBuffer.count
                } else {
                    left = 0
                    right = 0
                }

                if ablPointer.count >= 2 {
                    let leftBuf = ablPointer[0]
                    let rightBuf = ablPointer[1]
                    leftBuf.mData?.assumingMemoryBound(to: Float.self).advanced(by: frame).pointee = left
                    rightBuf.mData?.assumingMemoryBound(to: Float.self).advanced(by: frame).pointee = right
                } else if ablPointer.count == 1 {
                    let buf = ablPointer[0]
                    let ptr = buf.mData?.assumingMemoryBound(to: Float.self)
                    ptr?.advanced(by: frame * 2).pointee = left
                    ptr?.advanced(by: frame * 2 + 1).pointee = right
                }
            }
            self.lock.unlock()

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("AudioEngine start failed: \(error)")
        }
    }

    func stop() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        lock.lock()
        writePos = 0
        readPos = 0
        lock.unlock()
    }

    func writeSample(left: Int16, right: Int16) {
        let l = Float(left) / 32768.0
        let r = Float(right) / 32768.0
        lock.lock()
        let next1 = (writePos + 1) % ringBuffer.count
        let next2 = (writePos + 2) % ringBuffer.count
        if next2 != readPos {
            ringBuffer[writePos] = l
            ringBuffer[next1] = r
            writePos = next2
        }
        lock.unlock()
    }

    func writeBatch(data: UnsafePointer<Int16>, frames: Int) {
        lock.lock()
        for i in 0..<frames {
            let left = Float(data[i * 2]) / 32768.0
            let right = Float(data[i * 2 + 1]) / 32768.0
            let next1 = (writePos + 1) % ringBuffer.count
            let next2 = (writePos + 2) % ringBuffer.count
            if next2 == readPos { break }
            ringBuffer[writePos] = left
            ringBuffer[next1] = right
            writePos = next2
        }
        lock.unlock()
    }
}
