import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }
    static var current: Self {
        if let saved = UserDefaults.standard.string(forKey: "interfaceLanguage"),
           let language = Self(rawValue: saved) { return language }
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh") {
                return preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK") ? .traditionalChinese : .simplifiedChinese
            }
            if let match = allCases.first(where: { preferred.hasPrefix($0.rawValue) }) { return match }
        }
        return .english
    }
}

/// UI copy only. Never pass recognized speech, file paths or exported documents here.
func L(_ text: String, language: InterfaceLanguage = .current) -> String {
    guard language != .simplifiedChinese else { return text }
    if language == .traditionalChinese {
        return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }
    let dictionary = language == .english ? InterfaceCopy.english : InterfaceCopy.other[language, default: [:]]
    if let translated = dictionary[text] { return translated }
    // Status messages combine translated labels with model names, progress and
    // system errors. Longest phrases first prevent partial-label collisions.
    return dictionary.sorted { $0.key.count > $1.key.count }.reduce(text) { result, pair in
        result.replacingOccurrences(of: pair.key, with: pair.value)
    }
}

enum InterfaceCopy {
    static let other = AdditionalInterfaceCopy.translations
    static let english: [String: String] = [
        "继续": "Continue", "退出 LiveCaption": "Quit LiveCaption", "正在加载 ": "Loading ",
        "界面语言": "Interface language", "语言": "Language",
        "界面语言与字幕翻译目标语言分别设置。": "Interface language is independent of the translation target.",
        "剪切": "Cut", "复制": "Copy", "粘贴": "Paste", "全选": "Select All",
        "字幕": "Captions", "说话人": "Speakers", "翻译语言": "Translation language",
        "说话人断句": "Split by speaker", "输入来源": "Audio source", "开启": "On", "关闭": "Off",
        "不显示": "Off", "不显示翻译": "Translation off", "暂停识别": "Pause recognition",
        "开始识别": "Start recognition", "停止识别": "Stop recognition",
        "停止录音": "Stop recording", "开始录音": "Start recording", "输入": "Input", "翻译": "Translation",
        "设置": "Settings", "设置…": "Settings…", "退出 LiveCaption_ZH-CN": "Quit LiveCaption_ZH-CN",
        "正在停止识别…": "Stopping recognition…", "正在启动识别…": "Starting recognition…",
        "正在下载并加载说话人模型…": "Downloading and loading speaker model…",
        "翻译中…": "Translating…", "识别准备失败，请在设置中查看模型状态": "Unable to prepare recognition. Check model status in Settings.",
        "正在准备识别…": "Preparing recognition…", "等待语音…": "Waiting for speech…",
        "双击浮窗开始识别": "Double-click to start captions",
        "显示内容": "Show", "原文字号": "Caption size", "译文字号": "Translation size",
        "悬浮窗": "Floating window", "透明度": "Opacity", "无字幕时自动隐藏": "Hide when inactive",
        "等待时间": "Idle timeout", " 分钟": " min",
        "隐藏后仍会继续监听；识别到新的语音时，字幕窗会自动淡入。": "Listening continues while hidden. New speech brings the window back.",
        "直接拖动窗口可调整位置，拖动边缘可调整尺寸。": "Drag the window to move it; drag its edges to resize.",
        "系统": "System", "在 Dock 与强制退出中显示": "Show in Dock and Force Quit",
        "关闭时仅保留顶部菜单栏图标；开启后可在系统的强制退出窗口中找到 LiveCaption。": "When off, only the menu bar icon remains. Enable to show LiveCaption in Force Quit.",
        "音频": "Audio", "翻译语言包": "Translation language packs", "需要下载": "Download required",
        "下载语言包": "Download language pack", "请在系统窗口中确认下载": "Confirm the download in the system dialog.",
        "语言包由 macOS Translation 下载和管理；确认窗口会固定显示在设置窗口中。": "macOS Translation manages language packs. Its confirmation dialog appears in Settings.",
        "录音": "Recording", "按说话人断句": "Split captions by speaker",
        "停止录音后自动生成总结": "Summarize after recording", "总结方式": "Summary provider",
        "程序": "Executable", "选择…": "Choose…", "更换…": "Change…",
        "启动参数（可选）": "Arguments (optional)",
        "应用会把总结要求和字幕文本通过标准输入交给该程序，并读取其标准输出作为总结。": "The program receives the instructions and transcript on standard input and returns a summary on standard output.",
        "保存位置": "Save location",
        "选择“两者”时，电脑音频和麦克风会分别保存为两个 WAV 文件。CLI 只接收字幕文本，不接收音频；是否联网由所选 CLI 自身决定。": "Both sources are saved as separate WAV files. CLI providers receive text only; network use depends on the selected program.",
        "识别模型": "Recognition model",
        "模型首次使用时下载，之后完全离线运行。高精度模型更准确，但占用更多内存。": "Models download on first use and then run offline. The high-accuracy model uses more memory.",
        "语言包已准备完成": "Language pack ready", "打开录音文件夹": "Open recordings folder",
        "打开最近录音": "Open latest recording", "隐藏字幕窗": "Hide caption window", "显示字幕窗": "Show caption window",
        "电脑音频": "System audio", "麦克风": "Microphone", "两者": "Both",
        "仅字幕": "Captions only", "字幕＋翻译": "Captions + translation", "仅翻译": "Translation only",
        "本机智能": "On-device", "自定义 CLI": "Custom CLI", "简体中文": "Simplified Chinese",
        "平衡 · 181 MB": "Balanced · 181 MB", "高精度 · 547 MB": "High accuracy · 547 MB",
        "选择录音和文本的保存位置": "Choose where to save recordings and transcripts",
        "选择用于总结的命令行程序": "Choose a summary command-line program", "选择": "Choose",
        "暂时无法确定原文语言": "Source language is not yet known",
        "系统不支持该语言的翻译": "Translation is not supported for this language",
        "无法确认翻译语言包状态": "Unable to check language pack status",
        "缺少录音权限，请在系统设置的隐私与安全性中授权。": "Recording permission is missing. Enable it in System Settings > Privacy & Security.",
        "没有找到可采集的显示器。": "No display is available for capture.",
        "使用 Apple 本机智能模型；不可用时自动生成基础总结。": "Uses Apple's on-device model, with a basic extractive summary as fallback.",
        "请选择一个命令行程序。": "Choose a command-line program.",
        "已连接自定义 CLI；其联网和数据处理方式由该程序决定。": "Custom CLI connected. That program controls network access and data handling.",
        "所选文件无法执行，使用时会自动回退到本机总结。": "This file is not executable. On-device summarization will be used instead.",
        "模型尚未下载，点击开始后自动下载": "Model missing; start recognition to download",
        "模型已下载，点击开始加载": "Model downloaded; start recognition to load",
        "正在下载 Whisper 模型…": "Downloading Whisper model…", "正在加载 Whisper…": "Loading Whisper…",
        "Whisper 已就绪": "Whisper ready", "模型无法加载": "Unable to load model", "Whisper 推理失败": "Whisper inference failed",
        "当前下载源不支持断点续传": "This download source does not support resume",
        "模型校验失败，已清除损坏下载，请重试": "Model verification failed. Corrupt download removed; retry.",
        "需要在设置中下载翻译语言包": "Download a translation language pack in Settings",
        "正在续传": "Resuming", "正在下载": "Downloading", "正在连接并下载": "Connecting and downloading",
        " 已就绪": " ready", " 已下载，点击开始加载": " downloaded; start to load",
        " 已保存 ": " saved ", "，点击开始继续下载": "; start to resume",
        " 尚未下载，点击开始后自动下载": " not downloaded; start to download",
        "Whisper 错误：": "Whisper error: ", "模型下载暂停：": "Model download paused: ",
        "；已保留 ": "; saved ", "，再次点击开始会继续": "; start again to resume",
        "下载未完成：": "Download incomplete: ", "翻译失败：": "Translation failed: ",
        "语言包下载失败：": "Language pack download failed: ", "输入来源：": "Audio source: ",
        "切换录音来源失败：": "Unable to switch recording source: ", "文本保存失败：": "Unable to save transcript: ",
        "录音写入失败：": "Audio write failed: ", "。已识别文本仍会保存。": ". Recognized text will still be saved.",
        "字幕自动保存失败：": "Transcript autosave failed: ", "说话人模型加载失败：": "Speaker model loading failed: ",
        "说话人识别失败：": "Speaker identification failed: ", "失败": "Failed",
        "已检测到 ": "Detected ", "。总结时会联网发送字幕文本，不发送音频。": ". Summarization sends transcript text online, not audio.",
        "未检测到 ": "Not found: ", "，使用时会自动回退到本机总结。": "; on-device summarization will be used instead."
    ]
    static let fragments = english.sorted { $0.key.count > $1.key.count }
}
