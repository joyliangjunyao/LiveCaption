import CWhisper
import Foundation
import CryptoKit

enum WhisperState: Equatable {
    case missing
    case downloaded
    case downloading
    case loading
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .missing: "模型尚未下载，点击开始后自动下载"
        case .downloaded: "模型已下载，点击开始加载"
        case .downloading: "正在下载 Whisper 模型…"
        case .loading: "正在加载 Whisper…"
        case .ready: "Whisper 已就绪"
        case .failed(let message): "Whisper 错误：\(message)"
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private final class WhisperModelDownload: NSObject, URLSessionDataDelegate {
    private let partialURL: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var response: URLResponse?
    private var fileHandle: FileHandle?
    private var receivedBytes: Int64 = 0
    private var expectedTotalBytes: Int64 = 0
    private var storedError: Error?
    private var completed = false
    private var session: URLSession?

    init(partialURL: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.partialURL = partialURL
        self.progress = progress
    }

    func start(request originalRequest: URLRequest) async throws -> URLResponse {
        let existingBytes = Int64((try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var request = originalRequest
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 206 else {
            storedError = URLError(.badServerResponse)
            completionHandler(.cancel)
            return
        }
        do {
            let existingFileSize = Int64((try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if existingFileSize > 0 && http.statusCode == 200 {
                storedError = NSError(
                    domain: "LiveCaption.WhisperDownload",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "当前下载源不支持断点续传"]
                )
                completionHandler(.cancel)
                return
            }
            let canResume = http.statusCode == 206 && existingFileSize > 0
            if http.statusCode == 206 {
                let prefix = "bytes \(existingFileSize)-"
                guard http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix(prefix) == true else {
                    throw URLError(.badServerResponse)
                }
            }
            if !canResume {
                try? FileManager.default.removeItem(at: partialURL)
                _ = FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            }
            let existing = canResume ? existingFileSize : 0
            let handle = try FileHandle(forWritingTo: partialURL)
            if canResume { try handle.seekToEnd() } else { try handle.truncate(atOffset: 0) }
            fileHandle = handle
            receivedBytes = existing
            expectedTotalBytes = Self.totalLength(from: http, existingBytes: existing)
            self.response = response
            progress(receivedBytes, expectedTotalBytes)
            completionHandler(.allow)
        } catch {
            storedError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            progress(receivedBytes, expectedTotalBytes)
        } catch {
            storedError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard !completed else { return }
        completed = true
        try? fileHandle?.close()
        fileHandle = nil
        if let storedError {
            continuation?.resume(throwing: storedError)
        } else if let error {
            continuation?.resume(throwing: error)
        } else if let response {
            continuation?.resume(returning: response)
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
        continuation = nil
        self.session = nil
        session.finishTasksAndInvalidate()
    }

    private static func totalLength(from response: HTTPURLResponse, existingBytes: Int64) -> Int64 {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let totalText = range.split(separator: "/").last,
           let total = Int64(totalText) {
            return total
        }
        return response.expectedContentLength > 0
            ? existingBytes + response.expectedContentLength
            : 0
    }
}

struct WhisperResult {
    let text: String
    let language: String
}

actor WhisperEngine {
    private let context: OpaquePointer

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw NSError(domain: "LiveCaption.Whisper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "模型无法加载"])
        }
        self.context = context
    }

    deinit { whisper_free(context) }

    func transcribe(_ samples: [Float], languageHint: String? = nil) throws -> WhisperResult {
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        guard rms > 0.003 else { return WhisperResult(text: "", language: "und") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.no_speech_thold = 0.55
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))

        let selectedLanguage = languageHint ?? "auto"
        let code: Int32 = selectedLanguage.withCString { language in
            params.language = language
            return samples.withUnsafeBufferPointer {
                whisper_full(context, params, $0.baseAddress, Int32($0.count))
            }
        }
        guard code == 0 else {
            throw NSError(domain: "LiveCaption.Whisper", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "Whisper 推理失败"])
        }
        var text = ""
        for index in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, index) {
                text += String(cString: segment)
            }
        }
        let languageID = whisper_full_lang_id(context)
        let language = whisper_lang_str(languageID).map(String.init(cString:)) ?? "und"
        return WhisperResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language)
    }
}

@MainActor
final class WhisperService: ObservableObject {
    @Published private(set) var state: WhisperState = .missing
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0
    @Published private(set) var isResumingDownload = false
    private var engine: WhisperEngine?
    private var loadedModel: WhisperModel?
    private var buffers: [AudioSource: [Float]] = [:]
    private var processing: Set<AudioSource> = []
    private var lastText: [AudioSource: String] = [:]
    private var automaticLanguageHistory: [AudioSource: [String]] = [:]
    private var stableLanguages: [AudioSource: String] = [:]
    private var constrainedRunsSinceProbe: [AudioSource: Int] = [:]
    private var recognitionGeneration = 0
    private var pendingSegmentEnds: Set<AudioSource> = []
    private let chunkSize = 48_000
    private let overlapSize = 6_400

    var onTranscript: ((AudioSource, String, String) -> Void)?

    var isBusy: Bool { state == .downloading || state == .loading }

    func refreshState(for model: WhisperModel) {
        guard state != .downloading && state != .loading else { return }
        if engine != nil, loadedModel == model {
            state = .ready
        } else {
            state = modelIsDownloaded(model) ? .downloaded : .missing
        }
    }

    func statusLabel(for model: WhisperModel) -> String {
        switch state {
        case .downloading:
            if let downloadProgress {
                let action = isResumingDownload ? "正在续传" : "正在下载"
                return "\(action) \(model.title)：\(Int(downloadProgress * 100))%（\(Self.byteString(downloadedBytes)) / \(Self.byteString(expectedBytes))）"
            }
            return "正在连接并下载 \(model.title)…"
        case .loading:
            return "正在加载 \(model.title)…"
        case .ready:
            return "\(model.title) 已就绪"
        case .downloaded:
            return "\(model.title) 已下载，点击开始加载"
        case .missing:
            let savedBytes = partialFileSize(for: model)
            if savedBytes > 0 {
                return "\(model.title) 已保存 \(Self.byteString(savedBytes))，点击开始继续下载"
            }
            return "\(model.title) 尚未下载，点击开始后自动下载"
        case .failed(let message):
            return "Whisper 错误：\(message)"
        }
    }

    func prepare(model: WhisperModel) async throws {
        if engine != nil, loadedModel == model, state == .ready { return }
        let path = try await modelPath(for: model)
        state = .loading
        do {
            engine = try WhisperEngine(modelPath: path.path)
            loadedModel = model
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func append(_ samples: [Float], from source: AudioSource) {
        guard state == .ready, !samples.isEmpty else { return }
        buffers[source, default: []].append(contentsOf: samples)
        scheduleIfNeeded(source)
    }

    func reset() {
        recognitionGeneration += 1
        buffers.removeAll()
        processing.removeAll()
        pendingSegmentEnds.removeAll()
        lastText.removeAll()
        automaticLanguageHistory.removeAll()
        stableLanguages.removeAll()
        constrainedRunsSinceProbe.removeAll()
    }

    func flush() async {
        while !processing.isEmpty || buffers.values.contains(where: { $0.count >= chunkSize }) {
            for source in Array(buffers.keys) { scheduleIfNeeded(source) }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let engine else { return }
        let remaining = buffers
        buffers.removeAll()
        for (source, samples) in remaining where !samples.isEmpty {
            let languageHint = nextLanguageHint(for: source)
            if let result = try? await engine.transcribe(Self.paddedTail(samples), languageHint: languageHint), !result.text.isEmpty {
                observeAutomaticLanguage(result.language, for: source, wasConstrained: languageHint != nil)
                let text = removeOverlap(previous: lastText[source] ?? "", current: result.text)
                lastText[source] = result.text
                if !text.isEmpty { onTranscript?(source, text, result.language) }
            }
        }
    }

    func finishSegment(for source: AudioSource) {
        if processing.contains(source) {
            pendingSegmentEnds.insert(source)
            return
        }
        guard let engine,
              let segment = buffers.removeValue(forKey: source),
              !segment.isEmpty else { return }
        processing.insert(source)
        let generation = recognitionGeneration
        Task {
            let languageHint = nextLanguageHint(for: source)
            if let result = try? await engine.transcribe(Self.paddedTail(segment), languageHint: languageHint), !result.text.isEmpty {
                guard generation == recognitionGeneration else { return }
                observeAutomaticLanguage(result.language, for: source, wasConstrained: languageHint != nil)
                let text = removeOverlap(previous: lastText[source] ?? "", current: result.text)
                lastText[source] = result.text
                if !text.isEmpty { onTranscript?(source, text, result.language) }
            }
            guard generation == recognitionGeneration else { return }
            processing.remove(source)
            if pendingSegmentEnds.remove(source) != nil { finishSegment(for: source) }
            else { scheduleIfNeeded(source) }
        }
    }

    private func scheduleIfNeeded(_ source: AudioSource) {
        guard !processing.contains(source),
              let samples = buffers[source], samples.count >= chunkSize,
              let engine else { return }
        let chunk = Array(samples.prefix(chunkSize))
        buffers[source] = Self.remainingSamples(samples, chunkSize: chunkSize, overlapSize: overlapSize)
        processing.insert(source)
        let generation = recognitionGeneration
        Task {
            let languageHint = nextLanguageHint(for: source)
            let result = try? await engine.transcribe(chunk, languageHint: languageHint)
            guard generation == recognitionGeneration else { return }
            processing.remove(source)
            if let result, !result.text.isEmpty {
                observeAutomaticLanguage(result.language, for: source, wasConstrained: languageHint != nil)
                let text = removeOverlap(previous: lastText[source] ?? "", current: result.text)
                lastText[source] = result.text
                if !text.isEmpty { onTranscript?(source, text, result.language) }
            }
            if pendingSegmentEnds.remove(source) != nil { finishSegment(for: source) }
            else { scheduleIfNeeded(source) }
        }
    }

    nonisolated static func remainingSamples(_ samples: [Float], chunkSize: Int, overlapSize: Int) -> [Float] {
        Array(samples.dropFirst(max(0, chunkSize - overlapSize)))
    }

    nonisolated static func paddedTail(_ samples: [Float]) -> [Float] {
        samples + Array(repeating: 0, count: max(0, 8_000 - samples.count))
    }

    private func nextLanguageHint(for source: AudioSource) -> String? {
        guard let stableLanguage = stableLanguages[source] else { return nil }
        if constrainedRunsSinceProbe[source, default: 0] >= 1 {
            constrainedRunsSinceProbe[source] = 0
            return nil
        }
        constrainedRunsSinceProbe[source, default: 0] += 1
        return stableLanguage
    }

    private func observeAutomaticLanguage(_ language: String,
                                          for source: AudioSource,
                                          wasConstrained: Bool) {
        guard !wasConstrained, language != "und" else { return }
        var history = automaticLanguageHistory[source, default: []]
        history.append(language)
        if history.count > 3 { history.removeFirst(history.count - 3) }
        automaticLanguageHistory[source] = history

        if history.count >= 2, history.suffix(2).allSatisfy({ $0 == language }) {
            stableLanguages[source] = language
            return
        }
        guard history.count == 3 else { return }
        let counts = Dictionary(grouping: history, by: { $0 }).mapValues(\.count)
        if let majority = counts.max(by: { $0.value < $1.value }), majority.value >= 2 {
            stableLanguages[source] = majority.key
        }
    }

    private func removeOverlap(previous: String, current: String) -> String {
        TranscriptSimilarity.removingLeadingOverlap(previous: previous, current: current)
    }

    private func modelPath(for model: WhisperModel) async throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("LiveCaption/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(model.fileName)
        if modelIsDownloaded(model), try Self.verifyModel(destination, model: model) { return destination }
        let partial = root.appendingPathComponent(model.fileName + ".download")
        let savedBytes = partialFileSize(at: partial)
        if savedBytes == model.expectedFileSize, try Self.verifyModel(partial, model: model) {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            return destination
        }
        if savedBytes >= model.expectedFileSize {
            try? FileManager.default.removeItem(at: partial)
        }
        state = .downloading
        downloadedBytes = partialFileSize(at: partial)
        expectedBytes = model.expectedFileSize
        downloadProgress = Double(downloadedBytes) / Double(expectedBytes)
        isResumingDownload = downloadedBytes > 0
        var lastError: Error = URLError(.badURL)
        for url in model.downloadURLs {
            for attempt in 0..<3 {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 120
                    let downloader = WhisperModelDownload(partialURL: partial) { [weak self] received, expected in
                        Task { @MainActor in
                            guard let self else { return }
                            self.downloadedBytes = received
                            self.expectedBytes = expected > 0 ? expected : model.expectedFileSize
                            self.downloadProgress = Double(received) / Double(self.expectedBytes)
                        }
                    }
                    let response = try await downloader.start(request: request)
                    guard let http = response as? HTTPURLResponse,
                          http.statusCode == 200 || http.statusCode == 206 else {
                        throw URLError(.badServerResponse)
                    }
                    let size = partialFileSize(at: partial)
                    guard size == model.expectedFileSize else {
                        if size > model.expectedFileSize { try FileManager.default.removeItem(at: partial) }
                        throw URLError(.networkConnectionLost)
                    }
                    guard try Self.verifyModel(partial, model: model) else {
                        try FileManager.default.removeItem(at: partial)
                        throw NSError(domain: "LiveCaption.Model", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "模型校验失败，已清除损坏下载，请重试"])
                    }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: partial, to: destination)
                    downloadProgress = 1
                    isResumingDownload = false
                    return destination
                } catch {
                    lastError = error
                    downloadedBytes = partialFileSize(at: partial)
                    expectedBytes = model.expectedFileSize
                    downloadProgress = Double(downloadedBytes) / Double(expectedBytes)
                    isResumingDownload = downloadedBytes > 0
                    if attempt < 2 {
                        try? await Task.sleep(for: .seconds(attempt == 0 ? 2 : 5))
                    }
                }
            }
        }
        let saved = partialFileSize(at: partial)
        let continuationNote = saved > 0
            ? "；已保留 \(Self.byteString(saved))，再次点击开始会继续"
            : ""
        state = .failed("模型下载暂停：\(lastError.localizedDescription)\(continuationNote)")
        throw lastError
    }

    private func partialFileSize(for model: WhisperModel) -> Int64 {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
            .appendingPathComponent("LiveCaption/Models", isDirectory: true) else { return 0 }
        return partialFileSize(at: root.appendingPathComponent(model.fileName + ".download"))
    }

    private func partialFileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func modelIsDownloaded(_ model: WhisperModel) -> Bool {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
            .appendingPathComponent("LiveCaption/Models", isDirectory: true) else { return false }
        let url = root.appendingPathComponent(model.fileName)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size == model.expectedFileSize
    }

    private static func verifyModel(_ url: URL, model: WhisperModel) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == model.sha256
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
