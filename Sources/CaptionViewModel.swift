import AppKit
import Combine
import Foundation
import Translation

@MainActor
final class CaptionViewModel: ObservableObject {
    @Published var interfaceLanguage = InterfaceLanguage.current {
        didSet { UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage") }
    }
    private struct RecentRecognition {
        let source: AudioSource
        var text: String
        let lineID: UUID
        let receivedAt: Date
    }
    private var isInitializing = true
    @Published var audioMode: AudioMode = .both {
        didSet {
            saveSettings()
            applyAudioModeChange()
        }
    }
    @Published var targetLanguage = "zh-Hans" { didSet { saveSettings() } }
    @Published var fontSize: Double = 14 { didSet { saveSettings() } }
    @Published var translationFontSize: Double = 14 { didSet { saveSettings() } }
    @Published var opacity: Double = 0.82 { didSet { saveSettings() } }
    @Published var displayMode: CaptionDisplayMode = .captionsAndTranslation {
        didSet {
            saveSettings()
            if displayMode.showsTranslation { recording.enableTranslatedTranscript() }
        }
    }
    @Published var whisperModel: WhisperModel = .balanced {
        didSet {
            saveSettings()
            applyWhisperModelChange()
        }
    }
    @Published var diarizationEnabled = false {
        didSet {
            saveSettings()
            if diarizationEnabled { Task { await diarization.prepare() } }
        }
    }
    @Published var automaticSummary = true { didSet { saveSettings() } }
    @Published var summaryProvider: SummaryProvider = .local { didSet { saveSettings() } }
    @Published var customSummaryCLIPath = "" { didSet { saveSettings() } }
    @Published var customSummaryCLIArguments = "" { didSet { saveSettings() } }
    @Published var autoHideEnabled = true {
        didSet { saveSettings(); scheduleAutoHide() }
    }
    @Published var sleepDelayMinutes: Double = 3 {
        didSet { saveSettings(); scheduleAutoHide() }
    }
    @Published var showInDock = false {
        didSet { saveSettings(); applyActivationPolicy() }
    }
    @Published private(set) var saveDirectory: URL
    @Published var showControls = false
    @Published var lines: [CaptionLine] = []
    @Published private(set) var translationJob: TranslationJob?
    @Published private(set) var translationError: String?
    @Published private(set) var translationPackRequest: TranslationPackRequest?
    @Published private(set) var translationRetryGeneration = 0
    @Published private(set) var isSwitchingAudioMode = false
    @Published private(set) var isCaptionWindowVisible = true

    let capture = AudioCaptureService()
    let whisper = WhisperService()
    let recording = RecordingService()
    let diarization = SpeakerDiarizationService()
    let summary = SummaryService()
    private var captureObservation: AnyCancellable?
    private var whisperObservation: AnyCancellable?
    private var serviceObservations: Set<AnyCancellable> = []
    private var latestIDs: [AudioSource: UUID] = [:]
    private var translationQueue: [TranslationJob] = []
    private var captureStartedForRecording = false
    private var autoHideTask: Task<Void, Never>?
    private var windowTransitionGeneration = 0
    private var recentRecognitions: [RecentRecognition] = []

    init() {
        let defaults = UserDefaults.standard
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveDirectory = defaults.string(forKey: "saveDirectory").map(URL.init(fileURLWithPath:))
            ?? documents.appendingPathComponent("LiveCaption", isDirectory: true)
        audioMode = AudioMode(rawValue: defaults.string(forKey: "audioMode") ?? "") ?? .both
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "zh-Hans"
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 14
        translationFontSize = defaults.object(forKey: "translationFontSize") as? Double ?? 14
        opacity = defaults.object(forKey: "opacity") as? Double ?? 0.82
        if let savedMode = defaults.string(forKey: "displayMode"),
           let mode = CaptionDisplayMode(rawValue: savedMode) {
            displayMode = mode
        } else {
            displayMode = (defaults.object(forKey: "showOriginal") as? Bool ?? true)
                ? .captionsAndTranslation : .translationOnly
        }
        whisperModel = WhisperModel(rawValue: defaults.string(forKey: "whisperModel") ?? "") ?? .balanced
        diarizationEnabled = defaults.bool(forKey: "diarizationEnabled")
        automaticSummary = defaults.object(forKey: "automaticSummary") as? Bool ?? true
        summaryProvider = SummaryProvider(rawValue: defaults.string(forKey: "summaryProvider") ?? "") ?? .local
        customSummaryCLIPath = defaults.string(forKey: "customSummaryCLIPath") ?? ""
        customSummaryCLIArguments = defaults.string(forKey: "customSummaryCLIArguments") ?? ""
        autoHideEnabled = defaults.object(forKey: "autoHideEnabled") as? Bool ?? true
        sleepDelayMinutes = defaults.object(forKey: "sleepDelayMinutes") as? Double ?? 3
        showInDock = defaults.bool(forKey: "showInDock")
        captureObservation = capture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        whisperObservation = whisper.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        [recording.objectWillChange, diarization.objectWillChange, summary.objectWillChange].forEach { publisher in
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &serviceObservations)
        }
        capture.onSamples = { [weak self] source, samples in
            guard let self else { return }
            self.whisper.append(samples, from: source)
            self.recording.append(samples, source: source)
            if self.diarizationEnabled { self.diarization.append(samples, source: source) }
        }
        whisper.onTranscript = { [weak self] source, text, language in
            self?.receive(source: source, text: text, language: language, isFinal: true)
        }
        diarization.onSpeakerTurn = { [weak self] source in
            self?.whisper.finishSegment(for: source)
        }
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        recording.restoreLatestResult(in: saveDirectory)
        whisper.refreshState(for: whisperModel)
        if diarizationEnabled { Task { await diarization.prepare() } }
        isInitializing = false
        applyActivationPolicy()
    }

    private func saveSettings() {
        guard !isInitializing else { return }
        let defaults = UserDefaults.standard
        defaults.set(audioMode.rawValue, forKey: "audioMode")
        defaults.set(targetLanguage, forKey: "targetLanguage")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(translationFontSize, forKey: "translationFontSize")
        defaults.set(opacity, forKey: "opacity")
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        defaults.set(whisperModel.rawValue, forKey: "whisperModel")
        defaults.set(diarizationEnabled, forKey: "diarizationEnabled")
        defaults.set(automaticSummary, forKey: "automaticSummary")
        defaults.set(summaryProvider.rawValue, forKey: "summaryProvider")
        defaults.set(customSummaryCLIPath, forKey: "customSummaryCLIPath")
        defaults.set(customSummaryCLIArguments, forKey: "customSummaryCLIArguments")
        defaults.set(autoHideEnabled, forKey: "autoHideEnabled")
        defaults.set(sleepDelayMinutes, forKey: "sleepDelayMinutes")
        defaults.set(showInDock, forKey: "showInDock")
        defaults.set(saveDirectory.path, forKey: "saveDirectory")
    }

    private func applyActivationPolicy() {
        guard !isInitializing else { return }
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        DispatchQueue.main.async {
            _ = NSApp.setActivationPolicy(policy)
        }
    }

    func toggleCapture() {
        guard !recording.isRecording, !whisper.isBusy, !isSwitchingAudioMode,
              !capture.isTransitioning else { return }
        if capture.isRunning {
            autoHideTask?.cancel()
            Task {
                await capture.stop()
                whisper.reset()
            }
        } else {
            Task {
                do {
                    try await whisper.prepare(model: whisperModel)
                    await capture.start(mode: audioMode)
                    if capture.isRunning { scheduleAutoHide() }
                } catch {
                    // Model state contains the user-facing error.
                }
            }
        }
    }

    func toggleCaptionVisibility() {
        switch (displayMode.showsCaptions, displayMode.showsTranslation) {
        case (true, true): displayMode = .translationOnly
        case (true, false): displayMode = .hidden
        case (false, true): displayMode = .captionsAndTranslation
        case (false, false): displayMode = .captionsOnly
        }
    }

    func setCaptionVisibility(_ isVisible: Bool) {
        guard displayMode.showsCaptions != isVisible else { return }
        toggleCaptionVisibility()
    }

    func toggleTranslationVisibility() {
        switch (displayMode.showsCaptions, displayMode.showsTranslation) {
        case (true, true): displayMode = .captionsOnly
        case (true, false): displayMode = .captionsAndTranslation
        case (false, true): displayMode = .hidden
        case (false, false): displayMode = .translationOnly
        }
    }

    func setTranslationVisibility(_ isVisible: Bool) {
        guard displayMode.showsTranslation != isVisible else { return }
        toggleTranslationVisibility()
    }

    private func applyAudioModeChange() {
        guard !isInitializing else { return }
        if recording.isRecording {
            do {
                try recording.updateMode(audioMode)
            } catch {
                return
            }
        }
        guard capture.isRunning, !isSwitchingAudioMode else { return }
        isSwitchingAudioMode = true
        let selectedMode = audioMode
        Task {
            await capture.stop()
            await capture.start(mode: selectedMode)
            isSwitchingAudioMode = false
            if capture.isRunning { scheduleAutoHide() }
        }
    }

    private func applyWhisperModelChange() {
        guard !isInitializing else { return }
        guard capture.isRunning else {
            whisper.refreshState(for: whisperModel)
            return
        }
        let selectedModel = whisperModel
        whisper.reset()
        Task {
            do {
                try await whisper.prepare(model: selectedModel)
            } catch {
                // WhisperService exposes download or loading errors in Settings.
            }
        }
    }

    func toggleRecording() {
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        Task {
            defer { isStoppingRecording = false }
            if recording.isRecording {
                let resumeCaptions = !captureStartedForRecording && capture.isRunning
                autoHideTask?.cancel()
                await capture.stop()
                await whisper.flush()
                let result = await recording.stop()
                if captureStartedForRecording {
                    whisper.reset()
                    captureStartedForRecording = false
                }
                if resumeCaptions { await capture.start(mode: audioMode) }
                if automaticSummary, let transcript = result?.transcript {
                    _ = await summary.generate(from: transcript,
                                               provider: summaryProvider,
                                               customExecutablePath: customSummaryCLIPath,
                                               customArguments: customSummaryCLIArguments)
                }
                return
            }

            do {
                try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
                if !capture.isRunning {
                    try await whisper.prepare(model: whisperModel)
                    await capture.start(mode: audioMode)
                    guard capture.isRunning else { return }
                    captureStartedForRecording = true
                }
                try recording.start(mode: audioMode,
                                    directory: saveDirectory,
                                    includeSpeakers: diarizationEnabled,
                                    includeTranslations: displayMode.showsTranslation)
                if diarizationEnabled {
                    diarization.reset()
                    Task { await diarization.prepare() }
                }
            } catch {
                // RecordingService and WhisperService expose actionable errors in the UI.
            }
        }
    }

    private var isStoppingRecording = false

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = L("选择录音和文本的保存位置")
        panel.prompt = L("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirectory = url
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        recording.restoreLatestResult(in: saveDirectory)
        saveSettings()
    }

    func chooseSummaryCLI() {
        let panel = NSOpenPanel()
        panel.title = L("选择用于总结的命令行程序")
        panel.prompt = L("选择")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !customSummaryCLIPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: customSummaryCLIPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customSummaryCLIPath = url.path
    }

    func openLastRecording() {
        if let folder = recording.lastResult?.folder {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.open(saveDirectory)
        }
    }

    func showCaptionWindow() {
        guard let window = captionWindow else { return }
        windowTransitionGeneration += 1
        if window.isVisible {
            window.alphaValue = opacity
            isCaptionWindowVisible = true
            return
        }
        isCaptionWindowVisible = true
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = opacity
        }
    }

    func hideCaptionWindow() {
        guard let window = captionWindow, window.isVisible else { return }
        windowTransitionGeneration += 1
        isCaptionWindowVisible = false
        let generation = windowTransitionGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard self?.windowTransitionGeneration == generation else { return }
                window?.orderOut(nil)
                window?.alphaValue = self?.opacity ?? 1
            }
        })
    }

    private func receive(source: AudioSource, text: String, language: String, isFinal: Bool) {
        showCaptionWindow()
        scheduleAutoHide()
        let timestamp = recording.elapsed()
        let speaker = diarizationEnabled ? diarization.speaker(for: source) : nil
        if isFinal,
           let existingLineID = suppressRecentDuplicate(source: source,
                                                        text: text,
                                                        language: language) {
            if let timestamp {
                recording.appendTranscript(SessionTranscriptEntry(timestamp: timestamp,
                                                                  source: source,
                                                                  speaker: speaker,
                                                                  original: text,
                                                                  translated: ""),
                                           lineID: existingLineID)
            }
            return
        }
        let id: UUID
        if let active = latestIDs[source], let index = lines.firstIndex(where: { $0.id == active }) {
            lines[index].original = text
            lines[index].detectedLanguage = language
            lines[index].translationNotNeeded = Self.languagesMatch(language, targetLanguage)
            lines[index].isFinal = isFinal
            lines[index].speaker = speaker
            lines[index].recordingTimestamp = timestamp
            id = active
        } else {
            let line = CaptionLine(source: source, original: text,
                                   detectedLanguage: language,
                                   translationNotNeeded: Self.languagesMatch(language, targetLanguage),
                                   speaker: speaker,
                                   recordingTimestamp: timestamp, isFinal: isFinal)
            lines.append(line)
            latestIDs[source] = line.id
            id = line.id
        }
        if isFinal { latestIDs[source] = nil }
        if isFinal {
            recentRecognitions.removeAll { Date().timeIntervalSince($0.receivedAt) > 12 }
            recentRecognitions.append(RecentRecognition(source: source,
                                                       text: text,
                                                       lineID: id,
                                                       receivedAt: Date()))
        }
        if isFinal, let timestamp {
            recording.appendTranscript(SessionTranscriptEntry(timestamp: timestamp,
                                                              source: source,
                                                              speaker: speaker,
                                                              original: text,
                                                              translated: ""),
                                       lineID: id)
        }
        if lines.count > 8 { lines.removeFirst(lines.count - 8) }
        if displayMode.showsTranslation {
            if !Self.languagesMatch(language, targetLanguage) {
                enqueueTranslation(lineID: id, text: text, sourceLanguage: language)
            }
        }
    }

    private func suppressRecentDuplicate(source: AudioSource,
                                         text: String,
                                         language: String) -> UUID? {
        let now = Date()
        recentRecognitions.removeAll { now.timeIntervalSince($0.receivedAt) > 12 }
        guard let recentIndex = recentRecognitions.lastIndex(where: { recent in
            let isCrossSourceEcho = audioMode == .both && recent.source != source
            let isSameSourceRepeat = recent.source == source
            guard isCrossSourceEcho || isSameSourceRepeat else { return false }
            return TranscriptSimilarity.isLikelyDuplicate(recent.text, text,
                                                          threshold: isCrossSourceEcho ? 0.72 : 0.76)
        }) else { return nil }

        let recent = recentRecognitions[recentIndex]
        if text.count > recent.text.count,
           let lineIndex = lines.firstIndex(where: { $0.id == recent.lineID }) {
            lines[lineIndex].original = text
            lines[lineIndex].translated = ""
            lines[lineIndex].detectedLanguage = language
            lines[lineIndex].translationNotNeeded = Self.languagesMatch(language, targetLanguage)
            recentRecognitions[recentIndex].text = text
            if displayMode.showsTranslation,
               !Self.languagesMatch(language, targetLanguage) {
                enqueueTranslation(lineID: recent.lineID,
                                   text: text,
                                   sourceLanguage: language)
            }
        }
        return recent.lineID
    }

    static func languagesMatch(_ source: String, _ target: String) -> Bool {
        func family(_ identifier: String) -> String {
            let base = identifier
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first
                .map(String.init) ?? identifier.lowercased()
            return ["zh", "zho", "chi", "cmn"].contains(base) ? "zh" : base
        }
        let sourceFamily = family(source)
        return sourceFamily != "und" && !sourceFamily.isEmpty && sourceFamily == family(target)
    }

    private var captionWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "LiveCaptionFloatingPanel" }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard autoHideEnabled, capture.isRunning else { return }
        let delay = max(0.5, sleepDelayMinutes) * 60
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.hideCaptionWindow()
        }
    }

    func translateCurrent(using session: TranslationSession) async {
        guard let job = translationJob else { return }
        do {
            let response = try await session.translate(job.text)
            if let index = lines.firstIndex(where: { $0.id == job.id }),
               lines[index].original == job.text {
                lines[index].translated = response.targetText
            }
            recording.updateTranslation(lineID: job.id,
                                        original: job.text,
                                        translated: response.targetText)
            finishTranslation(job, error: nil)
        } catch {
            finishTranslation(job, error: error.localizedDescription)
        }
    }

    func requestTranslationPack(for job: TranslationJob) {
        guard translationJob?.id == job.id else { return }
        translationPackRequest = TranslationPackRequest(sourceLanguage: job.sourceLanguage,
                                                        targetLanguage: job.targetLanguage)
        translationError = "需要在设置中下载翻译语言包"
    }

    func translationPackInstalled() {
        translationPackRequest = nil
        translationError = nil
        translationRetryGeneration += 1
    }

    func translationPackDownloadFailed(_ message: String) {
        translationError = "语言包下载失败：\(message)"
    }

    func rejectTranslation(_ job: TranslationJob, message: String) {
        finishTranslation(job, error: message)
    }

    private func startNextTranslationIfNeeded() {
        guard translationJob == nil, !translationQueue.isEmpty else { return }
        translationError = nil
        translationJob = translationQueue.removeFirst()
    }

    private func enqueueTranslation(lineID: UUID, text: String, sourceLanguage: String) {
        if translationJob?.id == lineID, translationJob?.text == text { return }
        translationQueue.removeAll { $0.id == lineID }
        translationQueue.append(TranslationJob(id: lineID,
                                               text: text,
                                               sourceLanguage: sourceLanguage,
                                               targetLanguage: targetLanguage))
        startNextTranslationIfNeeded()
    }

    private func finishTranslation(_ job: TranslationJob, error: String?) {
        guard translationJob?.id == job.id else { return }
        translationError = error.map { "翻译失败：\($0)" }
        translationJob = nil
        DispatchQueue.main.async { [weak self] in
            self?.startNextTranslationIfNeeded()
        }
    }
}
