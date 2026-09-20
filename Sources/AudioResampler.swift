import AVFoundation
import CoreMedia

final class AudioResampler {
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 16_000,
                                       channels: 1,
                                       interleaved: false)!
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let lock = NSLock()

    func samples(from input: AVAudioPCMBuffer) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if sourceFormat != input.format {
            sourceFormat = input.format
            converter = AVAudioConverter(from: input.format, to: target)
        }
        guard let converter else { return [] }
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, flag in
            if consumed {
                flag.pointee = .noDataNow
                return nil
            }
            consumed = true
            flag.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    func samples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return [] }
        var formatDescription = stream.pointee
        guard let format = AVAudioFormat(streamDescription: &formatDescription) else { return [] }
        var needed = 0
        var block: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &needed,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &block
        )
        guard needed > 0 else { return [] }
        let rawList = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { rawList.deallocate() }
        let list = rawList.assumingMemoryBound(to: AudioBufferList.self)
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: needed,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &block
        )
        guard result == noErr,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list, deallocator: nil) else { return [] }
        pcm.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        return samples(from: pcm)
    }
}
