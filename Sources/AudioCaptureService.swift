import AVFoundation
import CoreMedia
import ScreenCaptureKit

@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var systemStream: SCStream?
    private let micResampler = AudioResampler()
    private let systemResampler = AudioResampler()
    private let systemOutput = SystemAudioOutput()
    private let pendingAudio = PendingAudioSamples()

    var onSamples: ((AudioSource, [Float]) -> Void)?

    func start(mode: AudioMode) async {
        guard !isRunning, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        errorMessage = nil
        let authorized = await requestPermissions(mode: mode)
        guard authorized else {
            errorMessage = "缺少录音权限，请在系统设置的隐私与安全性中授权。"
            return
        }
        do {
            if mode == .microphone || mode == .both { try startMicrophone() }
            if mode == .system || mode == .both { try await startSystemAudio() }
            isRunning = true
        } catch {
            await tearDownCapture()
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        await tearDownCapture()
    }

    private func tearDownCapture() async {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        let stream = systemStream
        systemStream = nil
        if let stream { try? await stream.stopCapture() }
        systemOutput.onSample = nil
        drainPendingAudio()
        isRunning = false
    }

    private func requestPermissions(mode: AudioMode) async -> Bool {
        if mode == .microphone || mode == .both {
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            guard mic else { return false }
        }
        return true
    }

    private func startMicrophone() throws {
        let input = audioEngine.inputNode
        // Passing a cached format can crash AVAudioEngine when the current input
        // device runs at a different sample rate. Let the engine supply the
        // device's live format; AudioResampler converts every buffer to 16 kHz.
        input.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.micResampler.samples(from: buffer)
            self.pendingAudio.append(samples, source: .microphone)
            Task { @MainActor in self.drainPendingAudio() }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "LiveCaption", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "没有找到可采集的显示器。"])
        }
        systemOutput.onSample = { [weak self] sample in
            guard let self else { return }
            let samples = self.systemResampler.samples(from: sample)
            self.pendingAudio.append(samples, source: .system)
            Task { @MainActor in self.drainPendingAudio() }
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: systemOutput)
        try stream.addStreamOutput(systemOutput, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "livecaption.system.audio"))
        try await stream.startCapture()
        systemStream = stream
    }

    private func drainPendingAudio() {
        for (source, samples) in pendingAudio.takeAll() { onSamples?(source, samples) }
    }
}

/// The audio callback owns captured samples before it schedules any UI task.
/// Stop explicitly drains this queue, so a delayed main-actor task cannot lose
/// the last captured buffer or deliver it into the next recording session.
final class PendingAudioSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [(AudioSource, [Float])] = []

    func append(_ samples: [Float], source: AudioSource) {
        lock.lock(); defer { lock.unlock() }
        frames.append((source, samples))
    }

    func takeAll() -> [(AudioSource, [Float])] {
        lock.lock(); defer { lock.unlock() }
        let result = frames
        frames.removeAll(keepingCapacity: true)
        return result
    }
}

private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onSample: ((CMSampleBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        onSample?(sampleBuffer)
    }
}
