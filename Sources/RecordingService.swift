import AVFoundation
import Foundation

struct RecordingResult {
    let folder: URL
    let transcript: URL
    let translatedTranscript: URL?
    let audioFiles: [URL]
}

@MainActor
final class RecordingService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastResult: RecordingResult?
    @Published private(set) var errorMessage: String?

    private let writerQueue = DispatchQueue(label: "livecaption.recording.writer")
    private var audioFiles: [AudioSource: AVAudioFile] = [:]
    private var transcriptEntries: [(lineID: UUID, entry: SessionTranscriptEntry)] = []
    private var sessionFolder: URL?
    private var includeSpeakers = false
    private var includeTranslations = false

    func restoreLatestResult(in directory: URL) {
        guard !isRecording else { return }
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let candidates = folders.compactMap { folder -> (URL, Date)? in
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true,
                  fileManager.fileExists(atPath: folder.appendingPathComponent("字幕记录.txt").path) else {
                return nil
            }
            return (folder, values?.contentModificationDate ?? .distantPast)
        }
        guard let folder = candidates.max(by: { $0.1 < $1.1 })?.0 else {
            lastResult = nil
            return
        }
        let transcript = folder.appendingPathComponent("字幕记录.txt")
        let audioFiles = ["电脑音频.wav", "麦克风.wav"]
            .map { folder.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        let translatedTranscript = folder.appendingPathComponent("字幕记录（含翻译）.txt")
        lastResult = RecordingResult(
            folder: folder,
            transcript: transcript,
            translatedTranscript: fileManager.fileExists(atPath: translatedTranscript.path)
                ? translatedTranscript : nil,
            audioFiles: audioFiles
        )
    }

    func start(mode: AudioMode,
               directory: URL,
               includeSpeakers: Bool,
               includeTranslations: Bool = false) throws {
        guard !isRecording else { return }
        errorMessage = nil
        transcriptEntries.removeAll()
        self.includeSpeakers = includeSpeakers
        self.includeTranslations = includeTranslations

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let folder = directory.appendingPathComponent("LiveCaption_\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var files: [AudioSource: AVAudioFile] = [:]
        for source in sources(for: mode) {
            files[source] = try makeAudioFile(for: source, in: folder)
        }

        audioFiles = files
        sessionFolder = folder
        startedAt = Date()
        isRecording = true
        checkpointTranscript()
    }

    func updateMode(_ mode: AudioMode) throws {
        guard isRecording, let sessionFolder else { return }
        do {
            for source in sources(for: mode) where audioFiles[source] == nil {
                audioFiles[source] = try makeAudioFile(for: source, in: sessionFolder)
            }
        } catch {
            errorMessage = "切换录音来源失败：\(error.localizedDescription)"
            throw error
        }
    }

    func enableTranslatedTranscript() {
        guard isRecording else { return }
        includeTranslations = true
    }

    func append(_ samples: [Float], source: AudioSource) {
        guard isRecording, !samples.isEmpty, let file = audioFiles[source] else { return }
        writerQueue.async {
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for index in samples.indices {
                channel[index] = max(-1, min(1, samples[index]))
            }
            do { try file.write(from: buffer) }
            catch {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "录音写入失败：\(error.localizedDescription)。已识别文本仍会保存。"
                }
            }
        }
    }

    func appendTranscript(_ entry: SessionTranscriptEntry, lineID: UUID = UUID()) {
        guard isRecording else { return }
        defer { checkpointTranscript() }
        if let index = transcriptEntries.lastIndex(where: {
            entry.timestamp - $0.entry.timestamp <= 8
                && entry.timestamp >= $0.entry.timestamp
                && TranscriptSimilarity.isLikelyDuplicate(
                    $0.entry.original,
                    entry.original,
                    threshold: $0.entry.source == entry.source ? 0.82 : 0.72
                )
        }) {
            let existing = transcriptEntries[index].entry
            if existing.source == .system, entry.source == .microphone { return }
            if existing.source == .microphone, entry.source == .system
                || entry.original.count > existing.original.count {
                transcriptEntries[index] = (lineID, entry)
            }
            return
        }
        transcriptEntries.append((lineID, entry))
    }

    func updateTranslation(lineID: UUID, original: String, translated: String) {
        guard !translated.isEmpty,
              let index = transcriptEntries.lastIndex(where: {
                  $0.lineID == lineID && $0.entry.original == original
              }) else { return }
        let existing = transcriptEntries[index]
        transcriptEntries[index] = (
            existing.lineID,
            SessionTranscriptEntry(timestamp: existing.entry.timestamp,
                                   source: existing.entry.source,
                                   speaker: existing.entry.speaker,
                                   original: existing.entry.original,
                                   translated: translated)
        )
        if isRecording { checkpointTranscript() }
        guard !isRecording,
              let translatedURL = lastResult?.translatedTranscript else { return }
        try? makeTranscript(includeTranslations: true)
            .write(to: translatedURL, atomically: true, encoding: .utf8)
    }

    func stop() async -> RecordingResult? {
        guard isRecording, let folder = sessionFolder else { return nil }
        isRecording = false
        startedAt = nil

        await withCheckedContinuation { continuation in
            writerQueue.async { continuation.resume() }
        }
        let urls = audioFiles.values.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent }
        audioFiles.removeAll()

        let transcriptURL = folder.appendingPathComponent("字幕记录.txt")
        do {
            try makeTranscript(includeTranslations: false)
                .write(to: transcriptURL, atomically: true, encoding: .utf8)
            let translatedURL: URL?
            if includeTranslations {
                let url = folder.appendingPathComponent("字幕记录（含翻译）.txt")
                try makeTranscript(includeTranslations: true)
                    .write(to: url, atomically: true, encoding: .utf8)
                translatedURL = url
            } else {
                translatedURL = nil
            }
            let result = RecordingResult(folder: folder,
                                         transcript: transcriptURL,
                                         translatedTranscript: translatedURL,
                                         audioFiles: urls)
            lastResult = result
            sessionFolder = nil
            return result
        } catch {
            errorMessage = "文本保存失败：\(error.localizedDescription)"
            sessionFolder = nil
            return nil
        }
    }

    func elapsed(at date: Date = Date()) -> TimeInterval? {
        startedAt.map { max(0, date.timeIntervalSince($0)) }
    }

    private func checkpointTranscript() {
        guard let folder = sessionFolder else { return }
        let original = makeTranscript(includeTranslations: false)
        let translated = includeTranslations ? makeTranscript(includeTranslations: true) : nil
        writerQueue.async { [weak self] in
            do {
                try original.write(to: folder.appendingPathComponent("字幕记录.txt"), atomically: true, encoding: .utf8)
                if let translated {
                    try translated.write(to: folder.appendingPathComponent("字幕记录（含翻译）.txt"), atomically: true, encoding: .utf8)
                }
            } catch {
                Task { @MainActor in self?.errorMessage = "字幕自动保存失败：\(error.localizedDescription)" }
            }
        }
    }

    private func makeTranscript(includeTranslations: Bool) -> String {
        var output = "LiveCaption 字幕记录\n"
        output += "生成时间：\(Date().formatted(date: .long, time: .standard))\n\n"
        for recorded in transcriptEntries {
            let entry = recorded.entry
            let time = Self.formatTime(entry.timestamp)
            let speaker = includeSpeakers ? " \(entry.speaker ?? fallbackSpeaker(for: entry.source))" : ""
            output += "[\(time)]\(speaker)  \(entry.original)\n"
            if includeTranslations, !entry.translated.isEmpty, entry.translated != entry.original {
                output += "           翻译：\(entry.translated)\n"
            }
        }
        if transcriptEntries.isEmpty { output += "（本次录音没有识别到语音）\n" }
        return output
    }

    private func fallbackSpeaker(for source: AudioSource) -> String {
        source == .microphone ? "我" : "说话人 1"
    }

    private func makeAudioFile(for source: AudioSource, in folder: URL) throws -> AVAudioFile {
        let name = source == .system ? "电脑音频.wav" : "麦克风.wav"
        let url = folder.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        return try AVAudioFile(forWriting: url,
                               settings: settings,
                               commonFormat: .pcmFormatFloat32,
                               interleaved: false)
    }

    private func sources(for mode: AudioMode) -> [AudioSource] {
        switch mode {
        case .system: [.system]
        case .microphone: [.microphone]
        case .both: [.system, .microphone]
        }
    }

    static func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
