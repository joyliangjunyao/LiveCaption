import AppKit
import SwiftUI
import Translation

private enum CaptionWindowMetrics {
    static let minimumWidth: CGFloat = 340
    static let minimumHeight: CGFloat = 108
}

private enum CompactToolbarPopover: Equatable {
    case audio
    case caption
    case translation
    case speaker
}

struct CaptionPanel: View {
    @ObservedObject var model: CaptionViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var compactToolbarPopover: CompactToolbarPopover?
    @State private var isPointerInsidePanel = false
    @AppStorage("hasChosenInterfaceLanguage") private var hasChosenLanguage = false
    @State private var showLanguageChoice = false

    var body: some View {
        VStack(spacing: 0) {
            if model.showControls { controls }
            captions
        }
        .overlay {
            if model.lines.isEmpty {
                Text(L(emptyCaptionMessage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasCaptionError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .allowsHitTesting(false)
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(max(0, 1 - model.opacity) * 0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
        .frame(minWidth: CaptionWindowMetrics.minimumWidth,
               minHeight: CaptionWindowMetrics.minimumHeight)
        .translationTask(translationConfiguration) { session in
            await model.translateCurrent(using: session)
        }
        .onChange(of: model.translationJob) { _, job in
            guard let job else { return }
            prepareTranslationConfiguration(for: job)
        }
        .onChange(of: model.translationRetryGeneration) { _, _ in
            if let job = model.translationJob {
                prepareTranslationConfiguration(for: job)
            }
        }
        .onHover { isInside in
            isPointerInsidePanel = isInside
            hideControlsTask?.cancel()
            if isInside {
                model.showControls = true
            } else {
                scheduleControlsHideIfNeeded()
            }
        }
        .onChange(of: compactToolbarPopover) { _, popover in
            hideControlsTask?.cancel()
            if popover != nil {
                model.showControls = true
            } else if !isPointerInsidePanel {
                scheduleControlsHideIfNeeded()
            }
        }
        .onDisappear { hideControlsTask?.cancel() }
        .onAppear { showLanguageChoice = !hasChosenLanguage }
        .sheet(isPresented: $showLanguageChoice) {
            VStack(alignment: .leading, spacing: 20) {
                Text("选择界面语言 / Choose interface language").font(.headline)
                Picker(L("界面语言"), selection: $model.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0) }
                }
                Button(L("继续")) {
                    hasChosenLanguage = true
                    showLanguageChoice = false
                }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(width: 420)
            .interactiveDismissDisabled()
        }
        .background(WindowConfigurator(opacity: model.opacity) {
            model.toggleCapture()
        })
    }

    private func prepareTranslationConfiguration(for job: TranslationJob) {
        Task {
            guard job.sourceLanguage != "und" else {
                model.rejectTranslation(job, message: "暂时无法确定原文语言")
                return
            }
            let source = Locale.Language(identifier: job.sourceLanguage)
            let target = Locale.Language(identifier: job.targetLanguage)
            let availability = await LanguageAvailability().status(from: source, to: target)
            guard model.translationJob?.id == job.id else { return }
            switch availability {
            case .installed:
                if var configuration = translationConfiguration,
                   configuration.source == source,
                   configuration.target == target {
                    configuration.invalidate()
                    translationConfiguration = configuration
                } else {
                    translationConfiguration = TranslationSession.Configuration(source: source,
                                                                                  target: target)
                }
            case .supported:
                model.requestTranslationPack(for: job)
            case .unsupported:
                model.rejectTranslation(job, message: "系统不支持该语言的翻译")
            @unknown default:
                model.rejectTranslation(job, message: "无法确认翻译语言包状态")
            }
        }
    }

    private func scheduleControlsHideIfNeeded() {
        guard compactToolbarPopover == nil else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard compactToolbarPopover == nil, !isPointerInsidePanel else { return }
                withAnimation(.easeIn(duration: 0.12)) {
                    model.showControls = false
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                Group {
                    if geometry.size.width < (model.interfaceLanguage == .simplifiedChinese || model.interfaceLanguage == .traditionalChinese ? 520 : 720) {
                        compactControls
                    } else {
                        expandedControls
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .frame(height: 24)
            if let status = controlStatus {
                Text(L(status))
                    .font(.caption)
                    .foregroundStyle(status.contains("失败") ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    private var expandedControls: some View {
        HStack(spacing: 10) {
            captureButton
            audioPicker
            Toggle(L("字幕"), isOn: captionVisibilityBinding)
                .toggleStyle(.checkbox)
            translationPicker
            Toggle(L("说话人"), isOn: $model.diarizationEnabled)
                .toggleStyle(.checkbox)
            Spacer(minLength: 4)
            recordButton
            utilityButtons
        }
        .frame(maxWidth: .infinity)
    }

    private var compactControls: some View {
        HStack(spacing: 15) {
            captureButton
            Button {
                compactToolbarPopover = .audio
            } label: {
                Image(systemName: audioModeIcon)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(L("输入来源：\(model.audioMode.rawValue)"))
            .disabled(model.whisper.isBusy || model.isSwitchingAudioMode || model.capture.isTransitioning)
            .popover(isPresented: compactPopoverBinding(for: .audio), arrowEdge: .bottom) {
                compactAudioOptions
            }

            Button {
                compactToolbarPopover = .caption
            } label: {
                Image(systemName: model.displayMode.showsCaptions ? "text.bubble.fill" : "text.bubble")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .help(L("字幕"))
            .popover(isPresented: compactPopoverBinding(for: .caption), arrowEdge: .bottom) {
                compactCaptionOptions
            }

            Button {
                compactToolbarPopover = .translation
            } label: {
                Image(systemName: model.displayMode.showsTranslation
                      ? "globe.fill" : "globe")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .help(L("翻译语言"))
            .popover(isPresented: compactPopoverBinding(for: .translation), arrowEdge: .bottom) {
                compactTranslationOptions
            }

            Button {
                compactToolbarPopover = .speaker
            } label: {
                Image(systemName: model.diarizationEnabled ? "person.2.fill" : "person.2")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .help(L("说话人断句"))
            .popover(isPresented: compactPopoverBinding(for: .speaker), arrowEdge: .bottom) {
                compactSpeakerOptions
            }

            Spacer(minLength: 0)
            recordButton
            utilityButtons
        }
        .frame(maxWidth: .infinity)
    }

    private func compactPopoverBinding(for popover: CompactToolbarPopover) -> Binding<Bool> {
        Binding {
            compactToolbarPopover == popover
        } set: { isPresented in
            if isPresented {
                compactToolbarPopover = popover
            } else if compactToolbarPopover == popover {
                compactToolbarPopover = nil
            }
        }
    }

    private var compactAudioOptions: some View {
        compactOptionPanel(title: "输入来源") {
            ForEach(AudioMode.allCases) { mode in
                compactOptionRow(mode.rawValue, selected: model.audioMode == mode) {
                    model.audioMode = mode
                }
            }
        }
    }

    private var compactTranslationOptions: some View {
        compactOptionPanel(title: "翻译语言") {
            compactOptionRow("不显示", selected: !model.displayMode.showsTranslation) {
                model.setTranslationVisibility(false)
            }
            Divider()
            ForEach(LanguageOption.supported) { language in
                compactOptionRow(language.name,
                                 selected: model.displayMode.showsTranslation
                                    && model.targetLanguage == language.id) {
                    model.targetLanguage = language.id
                    model.setTranslationVisibility(true)
                }
            }
        }
    }

    private var compactCaptionOptions: some View {
        compactOptionPanel(title: "字幕") {
            compactOptionRow("开启", selected: model.displayMode.showsCaptions) {
                model.setCaptionVisibility(true)
            }
            compactOptionRow("关闭", selected: !model.displayMode.showsCaptions) {
                model.setCaptionVisibility(false)
            }
        }
    }

    private var compactSpeakerOptions: some View {
        compactOptionPanel(title: "说话人断句") {
            compactOptionRow("开启", selected: model.diarizationEnabled) {
                model.diarizationEnabled = true
            }
            compactOptionRow("关闭", selected: !model.diarizationEnabled) {
                model.diarizationEnabled = false
            }
        }
    }

    private func compactOptionPanel<Content: View>(title: String,
                                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(title))
                .font(.headline)
                .padding(.horizontal, 4)
            Divider()
            content()
        }
        .padding(12)
        .frame(minWidth: 190)
    }

    private func compactOptionRow(_ title: String,
                                  selected: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button {
            action()
            compactToolbarPopover = nil
        } label: {
            HStack {
                Text(L(title))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var audioModeIcon: String {
        switch model.audioMode {
        case .system: "desktopcomputer"
        case .microphone: "mic"
        case .both: "waveform.badge.plus"
        }
    }

    private var captureButton: some View {
        Button(action: model.toggleCapture) {
            Image(systemName: model.capture.isRunning ? "pause.circle.fill" : "play.circle.fill")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .help(model.capture.isRunning ? L("暂停识别") : L("开始识别"))
        .disabled(model.recording.isRecording || model.whisper.isBusy
                  || model.isSwitchingAudioMode || model.capture.isTransitioning)
    }

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            Image(systemName: model.recording.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.recording.isRecording ? Color.red : Color.primary)
        .help(model.recording.isRecording ? L("停止录音") : L("开始录音"))
        .disabled(model.whisper.isBusy || model.isSwitchingAudioMode || model.capture.isTransitioning)
    }

    private var audioPicker: some View {
        Picker(L("输入"), selection: $model.audioMode) {
            ForEach(AudioMode.allCases) { Text(L($0.rawValue)).tag($0) }
        }
        .id(model.interfaceLanguage)
        .labelsHidden()
        .frame(width: model.interfaceLanguage == .simplifiedChinese || model.interfaceLanguage == .traditionalChinese ? 96 : 145)
        .disabled(model.whisper.isBusy || model.isSwitchingAudioMode || model.capture.isTransitioning)
    }

    private var captionVisibilityBinding: Binding<Bool> {
        Binding {
            model.displayMode.showsCaptions
        } set: { isVisible in
            model.setCaptionVisibility(isVisible)
        }
    }

    private var translationPicker: some View {
        Picker(L("翻译"), selection: translationSelection) {
            Text(L("不显示翻译")).tag(hiddenTranslationSelection)
            Divider()
            ForEach(LanguageOption.supported) { Text($0.name).tag($0.id) }
        }
        .id(model.interfaceLanguage)
        .labelsHidden()
        .frame(width: model.interfaceLanguage == .simplifiedChinese || model.interfaceLanguage == .traditionalChinese ? 105 : 185)
    }

    private var hiddenTranslationSelection: String { "__translation_hidden__" }

    private var translationSelection: Binding<String> {
        Binding {
            model.displayMode.showsTranslation ? model.targetLanguage : hiddenTranslationSelection
        } set: { selection in
            if selection == hiddenTranslationSelection {
                model.setTranslationVisibility(false)
            } else {
                model.targetLanguage = selection
                model.setTranslationVisibility(true)
            }
        }
    }

    private var utilityButtons: some View {
        Button(action: presentSettings) {
            Image(systemName: "slider.horizontal.3")
        }
            .help(L("设置"))
            .buttonStyle(.plain)
    }

    private func presentSettings() {
        NSApp.activate()
        openSettings()
        bringSettingsWindowForward()
    }

    private var controlStatus: String? {
        model.capture.errorMessage
            ?? (model.capture.isTransitioning
                ? (model.capture.isRunning ? "正在停止识别…" : "正在启动识别…")
                : nil)
            ?? model.recording.errorMessage
            ?? model.diarization.errorMessage
            ?? (model.diarization.isPreparing ? "正在下载并加载说话人模型…" : nil)
    }

    private var captions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            if model.displayMode.showsCaptions {
                                Text(CaptionTextFormatter.displayText(line.original))
                                    .font(.system(size: model.fontSize, weight: .semibold))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                            if model.displayMode.showsTranslation {
                                if line.translationNotNeeded {
                                    if !model.displayMode.showsCaptions {
                                        Text(CaptionTextFormatter.displayText(line.original))
                                            .font(.system(size: model.translationFontSize))
                                            .lineSpacing(3)
                                            .foregroundStyle(.white.opacity(0.82))
                                            .textSelection(.enabled)
                                    }
                                } else if line.translated.isEmpty {
                                    Text(L(model.translationError ?? "翻译中…"))
                                        .font(.system(size: model.translationFontSize))
                                        .foregroundStyle(model.translationError == nil ? Color.secondary : Color.red)
                                } else {
                                    Text(CaptionTextFormatter.displayText(line.translated))
                                        .font(.system(size: model.translationFontSize))
                                        .lineSpacing(3)
                                        .foregroundStyle(.white.opacity(0.82))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .id(line.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .onChange(of: model.lines) { _, lines in
                if let id = lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var hasCaptionError: Bool {
        if model.capture.errorMessage != nil { return true }
        return model.whisper.state.isFailure
    }

    private var emptyCaptionMessage: String {
        if let error = model.capture.errorMessage { return error }
        if model.whisper.state.isFailure { return "识别准备失败，请在设置中查看模型状态" }
        if model.whisper.isBusy { return "正在准备识别…" }
        if model.capture.isTransitioning {
            return model.capture.isRunning ? "正在停止识别…" : "正在启动识别…"
        }
        if model.capture.isRunning { return "等待语音…" }
        return "双击浮窗开始识别"
    }
}

struct SettingsView: View {
    @ObservedObject var model: CaptionViewModel
    @State private var translationDownloadRequest: TranslationPackRequest?
    @State private var translationDownloadGeneration = 0
    @State private var translationDownloadInProgress = false
    @State private var translationDownloadStatus: String?

    var body: some View {
        Form {
            Section(L("语言")) {
                Picker(L("界面语言"), selection: $model.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text(L("界面语言与字幕翻译目标语言分别设置。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("字幕")) {
                Picker(L("显示内容"), selection: $model.displayMode) {
                    ForEach(CaptionDisplayMode.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .id(model.interfaceLanguage)
                LabeledContent(L("原文字号")) { Slider(value: $model.fontSize, in: 14...42, step: 1) }
                LabeledContent(L("译文字号")) { Slider(value: $model.translationFontSize, in: 12...36, step: 1) }
            }
            Section(L("悬浮窗")) {
                LabeledContent(L("透明度")) { Slider(value: $model.opacity, in: 0.35...1) }
                Toggle(L("无字幕时自动隐藏"), isOn: $model.autoHideEnabled)
                LabeledContent(L("等待时间")) {
                    Stepper(value: $model.sleepDelayMinutes, in: 0.5...60, step: 0.5) {
                        Text(model.sleepDelayMinutes.formatted(.number.precision(.fractionLength(0...1))) + L(" 分钟"))
                            .monospacedDigit()
                    }
                }
                .disabled(!model.autoHideEnabled)
                Text(L("隐藏后仍会继续监听；识别到新的语音时，字幕窗会自动淡入。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("直接拖动窗口可调整位置，拖动边缘可调整尺寸。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("系统")) {
                Toggle(L("在 Dock 与强制退出中显示"), isOn: $model.showInDock)
                Text(L("关闭时仅保留顶部菜单栏图标；开启后可在系统的强制退出窗口中找到 LiveCaption。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("音频")) {
                Picker(L("输入来源"), selection: $model.audioMode) {
                    ForEach(AudioMode.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .id(model.interfaceLanguage)
                .disabled(model.whisper.isBusy || model.isSwitchingAudioMode || model.capture.isTransitioning)
            }
            if let request = model.translationPackRequest {
                Section(L("翻译语言包")) {
                    LabeledContent(L("需要下载")) {
                        Text(L(request.description))
                    }
                    Button(L("下载语言包")) {
                        translationDownloadStatus = "请在系统窗口中确认下载"
                        translationDownloadRequest = request
                        translationDownloadGeneration += 1
                        translationDownloadInProgress = true
                    }
                    .disabled(translationDownloadInProgress)
                    if let translationDownloadStatus {
                        Text(L(translationDownloadStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(L("语言包由 macOS Translation 下载和管理；确认窗口会固定显示在设置窗口中。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("录音")) {
                Toggle(L("按说话人断句"), isOn: $model.diarizationEnabled)
                Toggle(L("停止录音后自动生成总结"), isOn: $model.automaticSummary)
                Picker(L("总结方式"), selection: $model.summaryProvider) {
                    ForEach(SummaryProvider.allCases) { provider in
                        Text(L(provider.title)).tag(provider)
                    }
                }
                .id(model.interfaceLanguage)
                .disabled(model.summary.isSummarizing)
                if model.summaryProvider == .customCLI {
                    LabeledContent(L("程序")) {
                        Button(model.customSummaryCLIPath.isEmpty ? L("选择…") : L("更换…"),
                               action: model.chooseSummaryCLI)
                    }
                    if !model.customSummaryCLIPath.isEmpty {
                        Text(model.customSummaryCLIPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    TextField(L("启动参数（可选）"), text: $model.customSummaryCLIArguments)
                        .textFieldStyle(.roundedBorder)
                    Text(L("应用会把总结要求和字幕文本通过标准输入交给该程序，并读取其标准输出作为总结。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(L(model.summary.availabilityDescription(for: model.summaryProvider,
                                                           customExecutablePath: model.customSummaryCLIPath)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("保存位置")) {
                    Button(L("选择…"), action: model.chooseSaveDirectory)
                        .disabled(model.recording.isRecording)
                }
                Text(model.saveDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(L("选择“两者”时，电脑音频和麦克风会分别保存为两个 WAV 文件。CLI 只接收字幕文本，不接收音频；是否联网由所选 CLI 自身决定。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Whisper") {
                Picker(L("识别模型"), selection: $model.whisperModel) {
                    ForEach(WhisperModel.allCases) { Text(L($0.title)).tag($0) }
                }
                .id(model.interfaceLanguage)
                .disabled(model.whisper.isBusy)
                Text(L(model.whisper.statusLabel(for: model.whisperModel)))
                    .font(.caption)
                    .foregroundStyle(model.whisper.state.isFailure ? Color.red : Color.secondary)
                if let progress = model.whisper.downloadProgress, model.whisper.state == .downloading {
                    ProgressView(value: progress)
                }
                Text(L("模型首次使用时下载，之后完全离线运行。高精度模型更准确，但占用更多内存。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .background {
            TranslationDownloadHost(request: translationDownloadRequest,
                                    generation: translationDownloadGeneration) { generation, error in
                guard generation == translationDownloadGeneration else { return }
                translationDownloadInProgress = false
                if let error {
                    translationDownloadStatus = "下载未完成：\(error)"
                    model.translationPackDownloadFailed(error)
                    return
                }
                translationDownloadStatus = "语言包已准备完成"
                translationDownloadRequest = nil
                model.translationPackInstalled()
            }
        }
    }
}

private struct TranslationDownloadHost: View {
    let request: TranslationPackRequest?
    let generation: Int
    let completion: (Int, String?) -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var activeGeneration = 0

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onChange(of: generation) { _, newGeneration in
                guard newGeneration > 0, let request else { return }
                activeGeneration = newGeneration
                let source = Locale.Language(identifier: request.sourceLanguage)
                let target = Locale.Language(identifier: request.targetLanguage)
                if var configuration,
                   configuration.source == source,
                   configuration.target == target {
                    configuration.invalidate()
                    self.configuration = configuration
                } else {
                    configuration = TranslationSession.Configuration(source: source, target: target)
                }
            }
            .translationTask(configuration) { session in
                let sessionGeneration = activeGeneration
                guard sessionGeneration > 0 else { return }
                do {
                    try await session.prepareTranslation()
                    completion(sessionGeneration, nil)
                } catch is CancellationError {
                    return
                } catch {
                    completion(sessionGeneration, error.localizedDescription)
                }
            }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let opacity: Double
    let onDoubleClick: () -> Void

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var mouseMonitor: Any?
        var keyboardMonitor: Any?
        var captionWasLastClicked = false

        deinit {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if context.coordinator.configuredWindow === window {
                if window.isVisible { window.alphaValue = opacity }
                return
            }
            context.coordinator.configuredWindow = window
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.identifier = NSUserInterfaceItemIdentifier("LiveCaptionFloatingPanel")
            window.hasShadow = true
            window.alphaValue = opacity
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: CaptionWindowMetrics.minimumWidth,
                                           height: CaptionWindowMetrics.minimumHeight)
            let currentFrame = window.frame
            window.setFrame(NSRect(x: currentFrame.minX,
                                   y: currentFrame.maxY - CaptionWindowMetrics.minimumHeight,
                                   width: CaptionWindowMetrics.minimumWidth,
                                   height: CaptionWindowMetrics.minimumHeight), display: true)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            if let oldMonitor = context.coordinator.mouseMonitor {
                NSEvent.removeMonitor(oldMonitor)
            }
            let coordinator = context.coordinator
            context.coordinator.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window, weak coordinator] event in
                coordinator?.captionWasLastClicked = event.window === window
                guard event.window === window else { return event }
                NSApp.activate()
                window?.makeKey()
                guard event.clickCount == 2,
                      let contentView = window?.contentView else { return event }
                let point = contentView.convert(event.locationInWindow, from: nil)
                if let hitView = contentView.hitTest(point), hitView.blocksCaptionDoubleClick {
                    return event
                }
                Task { @MainActor in onDoubleClick() }
                return event
            }
            context.coordinator.keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window, weak coordinator] event in
                guard coordinator?.captionWasLastClicked == true,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "c",
                      let contentView = window?.contentView,
                      let selectedText = contentView.selectedCaptionText else { return event }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedText, forType: .string)
                return nil
            }
        }
    }
}

private extension NSView {
    var blocksCaptionDoubleClick: Bool {
        var view: NSView? = self
        while let current = view {
            if current is NSControl || current is NSTextView {
                return true
            }
            view = current.superview
        }
        return false
    }

    var selectedCaptionText: String? {
        if let textView = self as? NSTextView {
            let range = textView.selectedRange()
            if range.length > 0, NSMaxRange(range) <= (textView.string as NSString).length {
                return (textView.string as NSString).substring(with: range)
            }
        }
        for child in subviews {
            if let selection = child.selectedCaptionText { return selection }
        }
        return nil
    }
}

struct MenuBarMenu: View {
    @ObservedObject var model: CaptionViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.capture.isRunning ? L("停止识别") : L("开始识别")) {
            model.toggleCapture()
        }
        .disabled(model.recording.isRecording || model.capture.isTransitioning)
        Button(model.recording.isRecording ? L("停止录音") : L("开始录音")) {
            model.toggleRecording()
        }
        Divider()
        Button(model.recording.lastResult == nil ? L("打开录音文件夹") : L("打开最近录音")) {
            model.openLastRecording()
        }
        Button(model.isCaptionWindowVisible ? L("隐藏字幕窗") : L("显示字幕窗")) {
            if model.isCaptionWindowVisible {
                model.hideCaptionWindow()
            } else {
                openWindow(id: "caption")
                DispatchQueue.main.async { model.showCaptionWindow() }
            }
        }
        Divider()
        Button(L("设置…")) {
            NSApp.activate()
            openSettings()
            bringSettingsWindowForward()
        }
        Button(L("退出 LiveCaption_ZH-CN")) { NSApp.terminate(nil) }
    }
}

@MainActor
private func bringSettingsWindowForward() {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(120))
        NSApp.activate()
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
                || $0.title.localizedCaseInsensitiveContains("LiveCaption设置")
        }) else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
