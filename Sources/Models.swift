import Foundation

enum AudioMode: String, CaseIterable, Identifiable {
    case system = "电脑音频"
    case microphone = "麦克风"
    case both = "两者"
    var id: String { rawValue }
}

enum AudioSource: String {
    case system = "电脑"
    case microphone = "麦克风"
}

enum CaptionDisplayMode: String, CaseIterable, Identifiable {
    case hidden = "不显示"
    case captionsOnly = "仅字幕"
    case captionsAndTranslation = "字幕＋翻译"
    case translationOnly = "仅翻译"
    var id: String { rawValue }

    var showsCaptions: Bool { self == .captionsOnly || self == .captionsAndTranslation }
    var showsTranslation: Bool { self == .translationOnly || self == .captionsAndTranslation }
}

enum SummaryProvider: String, CaseIterable, Identifiable {
    case local = "local"
    case codexCLI = "codex-cli"
    case claudeCLI = "claude-cli"
    case customCLI = "custom-cli"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: "本机智能"
        case .codexCLI: "Codex CLI"
        case .claudeCLI: "Claude CLI"
        case .customCLI: "自定义 CLI"
        }
    }
}

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String

    static let supported = [
        LanguageOption(id: "zh-Hans", name: "简体中文"),
        LanguageOption(id: "en", name: "English"),
        LanguageOption(id: "ja", name: "日本語"),
        LanguageOption(id: "ko", name: "한국어"),
        LanguageOption(id: "fr", name: "Français"),
        LanguageOption(id: "de", name: "Deutsch"),
        LanguageOption(id: "es", name: "Español"),
        LanguageOption(id: "it", name: "Italiano"),
        LanguageOption(id: "pt", name: "Português"),
        LanguageOption(id: "ru", name: "Русский")
    ]
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case balanced = "small-q5_1"
    case accurate = "large-v3-turbo-q5_0"

    var id: String { rawValue }
    var title: String { self == .balanced ? "平衡 · 181 MB" : "高精度 · 547 MB" }
    var fileName: String { "ggml-\(rawValue).bin" }
    var minimumFileSize: Int { self == .balanced ? 180_000_000 : 550_000_000 }
    var expectedFileSize: Int64 { self == .balanced ? 190_085_487 : 574_041_195 }
    // SHA-256 from ggerganov/whisper.cpp Hugging Face LFS metadata.
    var sha256: String {
        self == .balanced
            ? "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
            : "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    }
    var downloadURLs: [URL] {
        var urls: [URL] = []
        if self == .accurate {
            urls.append(URL(string: "https://modelscope.cn/models/timeless/whispercpp/resolve/master/\(fileName)")!)
        }
        urls.append(URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(fileName)")!)
        urls.append(URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!)
        return urls
    }
}

enum CaptionTextFormatter {
    static func displayText(_ text: String) -> String {
        // Presentation only: do not split English abbreviations, URLs or decimals.
        text.components(separatedBy: "。").enumerated().map { index, part in
            index == 0 ? part : "。\n" + part.trimmingCharacters(in: .newlines)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CaptionLine: Identifiable, Equatable {
    let id = UUID()
    let source: AudioSource
    var original: String
    var translated: String = ""
    var detectedLanguage: String = ""
    var translationNotNeeded = false
    var speaker: String?
    var recordingTimestamp: TimeInterval?
    var isFinal: Bool = false
}

struct SessionTranscriptEntry: Sendable {
    let timestamp: TimeInterval
    let source: AudioSource
    let speaker: String?
    let original: String
    let translated: String
}

struct TranslationJob: Identifiable, Equatable {
    let id: UUID
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
}

struct TranslationPackRequest: Equatable {
    let sourceLanguage: String
    let targetLanguage: String

    var description: String {
        let locale = Locale(identifier: InterfaceLanguage.current.rawValue)
        let source = locale.localizedString(forLanguageCode: sourceLanguage) ?? sourceLanguage
        let target = locale.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
        return "\(source) → \(target)"
    }
}

enum TranscriptSimilarity {
    static func isLikelyDuplicate(_ first: String, _ second: String, threshold: Double) -> Bool {
        let left = normalized(first)
        let right = normalized(second)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        let shorter = min(left.count, right.count)
        let longer = max(left.count, right.count)
        if shorter >= 8,
           (left.contains(right) || right.contains(left)),
           Double(shorter) / Double(longer) >= 0.68 {
            return true
        }
        guard shorter >= 8 else { return false }
        let leftPairs = pairs(in: left)
        let rightPairs = pairs(in: right)
        guard !leftPairs.isEmpty, !rightPairs.isEmpty else { return false }
        let overlap = leftPairs.intersection(rightPairs).count
        let score = Double(2 * overlap) / Double(leftPairs.count + rightPairs.count)
        return score >= threshold
    }

    static func removingLeadingOverlap(previous: String, current: String) -> String {
        let previousNormalized = Array(normalized(previous))
        let currentCharacters = Array(current)
        var currentNormalized: [Character] = []
        var currentOffsets: [Int] = []
        for (offset, character) in currentCharacters.enumerated() {
            for normalizedCharacter in String(character).lowercased()
                where normalizedCharacter.isLetter || normalizedCharacter.isNumber {
                currentNormalized.append(normalizedCharacter)
                currentOffsets.append(offset)
            }
        }
        let maximum = min(120, previousNormalized.count, currentNormalized.count)
        guard maximum >= 4 else { return current }
        for count in stride(from: maximum, through: 4, by: -1) {
            if previousNormalized.suffix(count).elementsEqual(currentNormalized.prefix(count)) {
                let consumedCharacters = currentOffsets[count - 1] + 1
                return String(currentCharacters.dropFirst(consumedCharacters))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return current
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func pairs(in text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count > 1 else { return [] }
        return Set((0..<(characters.count - 1)).map {
            String(characters[$0...($0 + 1)])
        })
    }
}
