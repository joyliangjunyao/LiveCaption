import Foundation

/// Standalone localization smoke test; no microphone, model or user preferences needed.
@main
enum InterfaceLanguageCheck {
    static func main() {
        let obsolete = Set(["退出中文版", "退出 LiveCaption_ZH-CN"])
        let expectedKeys = Set(InterfaceCopy.english.keys).subtracting(obsolete)
        for language in InterfaceLanguage.allCases {
            if language != .simplifiedChinese && language != .traditionalChinese && language != .english {
                let table = InterfaceCopy.other[language, default: [:]]
                let missing = expectedKeys.subtracting(table.keys)
                precondition(missing.isEmpty, "Missing \(language): \(missing.sorted())")
                precondition(table.values.allSatisfy { !$0.isEmpty })
            }
            for key in expectedKeys {
                precondition(!L(key, language: language).isEmpty)
            }
            precondition(L("Whisper", language: language) == "Whisper")
            print("PASS \(language.rawValue): \(expectedKeys.count) UI messages")
        }
        precondition(L("设置", language: .traditionalChinese) == "設置")
        precondition(L("设置", language: .english) == "Settings")
        precondition(L("高精度 · 547 MB 已下载，点击开始加载", language: .german)
            == "Hohe Genauigkeit · 547 MB heruntergeladen; zum Laden starten")
        precondition(L("继续", language: .japanese) == "続ける")
        print("PASS composed status, Traditional Chinese conversion, unchanged model names")
    }
}
