import FluidAudio
import Foundation

private actor SpeakerDiarizationEngine {
    private var diarizer: LSEENDDiarizer?

    func prepare() async throws {
        guard diarizer == nil else { return }
        diarizer = try await LSEENDDiarizer(variant: .dihard3, stepSize: .step500ms)
    }

    func process(_ samples: [Float]) throws -> Int? {
        guard let diarizer else { return nil }
        guard let update = try diarizer.process(samples: samples, sourceSampleRate: 16_000) else { return nil }
        return (update.tentativeSegments + update.finalizedSegments)
            .max { first, second in
                if first.endTime == second.endTime { return first.activity < second.activity }
                return first.endTime < second.endTime
            }?.speakerIndex
    }

    func reset() {
        diarizer?.reset()
    }
}

@MainActor
final class SpeakerDiarizationService: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentSystemSpeaker = "说话人 1"

    private let engine = SpeakerDiarizationEngine()
    private var samples: [Float] = []
    private var isProcessing = false
    private var currentSpeakerIndex: Int?
    private let processingChunkSize = 8_000

    var onSpeakerTurn: ((AudioSource) -> Void)?

    func prepare() async {
        guard !isReady, !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        do {
            try await engine.prepare()
            isReady = true
        } catch {
            errorMessage = "说话人模型加载失败：\(error.localizedDescription)"
        }
        isPreparing = false
    }

    func append(_ newSamples: [Float], source: AudioSource) {
        guard source == .system, isReady, !newSamples.isEmpty else { return }
        samples.append(contentsOf: newSamples)
        processIfNeeded()
    }

    func speaker(for source: AudioSource) -> String {
        source == .microphone ? "我" : currentSystemSpeaker
    }

    func reset() {
        samples.removeAll()
        currentSystemSpeaker = "说话人 1"
        currentSpeakerIndex = nil
        Task { await engine.reset() }
    }

    private func processIfNeeded() {
        guard !isProcessing, samples.count >= processingChunkSize else { return }
        let chunk = samples
        samples.removeAll(keepingCapacity: true)
        isProcessing = true
        Task {
            do {
                if let index = try await engine.process(chunk) {
                    if let previous = currentSpeakerIndex, previous != index {
                        onSpeakerTurn?(.system)
                    }
                    currentSpeakerIndex = index
                    currentSystemSpeaker = "说话人 \(index + 1)"
                }
            } catch {
                errorMessage = "说话人识别失败：\(error.localizedDescription)"
            }
            isProcessing = false
            processIfNeeded()
        }
    }
}
