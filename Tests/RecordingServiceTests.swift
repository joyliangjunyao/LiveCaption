import Foundation
import AVFoundation
import XCTest
@testable import LiveCaption

final class RecordingServiceTests: XCTestCase {
    func testStopDrainsCapturedFramesExactlyOnce() {
        let queue = PendingAudioSamples()
        queue.append([1, 2], source: .microphone)
        queue.append([3], source: .system)
        let drained = queue.takeAll()
        XCTAssertEqual(drained.map { $0.1 }, [[1, 2], [3]])
        XCTAssertTrue(queue.takeAll().isEmpty)
    }
    func testBackloggedAudioKeepsEveryUnprocessedSample() {
        let samples = (0..<120_000).map(Float.init)
        let remaining = WhisperService.remainingSamples(samples, chunkSize: 48_000, overlapSize: 6_400)
        XCTAssertEqual(remaining, Array(samples[41_600...]))
    }

    func testShortTailKeepsAudioAndPadsOnlyWithSilence() {
        let input: [Float] = [0.2, 0.3, 0.4]
        let padded = WhisperService.paddedTail(input)
        XCTAssertEqual(Array(padded.prefix(3)), input)
        XCTAssertEqual(padded.count, 8_000)
        XCTAssertTrue(padded.dropFirst(3).allSatisfy { $0 == 0 })
    }

    @MainActor
    func testTranscriptIsSavedBeforeRecordingStops() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = RecordingService()
        try recorder.start(mode: .system, directory: root, includeSpeakers: false)
        recorder.appendTranscript(SessionTranscriptEntry(timestamp: 1, source: .system,
                                                        speaker: nil, original: "已识别内容", translated: ""))
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let file = try XCTUnwrap(folders.first).appendingPathComponent("字幕记录.txt")
        for _ in 0..<100 {
            if (try? String(contentsOf: file, encoding: .utf8))?.contains("已识别内容") == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("已识别内容"))
        _ = await recorder.stop()
    }
    @MainActor
    func testCustomCLIUsesStandardInputAndOutputContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveCaptionCustomCLI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appendingPathComponent("字幕记录.txt")
        try "[00:00:01] 测试者  明天下午三点提交报告。".write(
            to: transcript, atomically: true, encoding: .utf8)

        let service = SummaryService()
        let generated = await service.generate(from: transcript,
                                               provider: .customCLI,
                                               customExecutablePath: "/bin/cat")

        let summaryURL = try XCTUnwrap(generated)
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(summary.contains("明天下午三点提交报告"))
        XCTAssertEqual(service.statusMessage, "自定义 CLI 总结已保存")
    }

    @MainActor
    func testConfiguredCLISummaryProviders() async throws {
        guard ProcessInfo.processInfo.environment["LIVECAPTION_RUN_CLI_TESTS"] == "1" else {
            throw XCTSkip("CLI integration test is opt-in")
        }
        for provider in [SummaryProvider.codexCLI, .claudeCLI] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LiveCaptionCLI-\(provider.rawValue)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let transcript = root.appendingPathComponent("字幕记录.txt")
            try "[00:00:01] 测试者  明天下午三点提交测试报告。".write(
                to: transcript, atomically: true, encoding: .utf8)

            let service = SummaryService()
            let generated = await service.generate(from: transcript, provider: provider)
            XCTAssertNotNil(generated)
            XCTAssertEqual(service.statusMessage, "\(provider.title) 总结已保存")
        }
    }

    func testMicrophoneResamplerAccepts44100HzInput() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 44_100,
                                                channels: 1,
                                                interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                channel[index] = sin(Float(index) * 0.05)
            }
        }

        let samples = AudioResampler().samples(from: buffer)
        XCTAssertGreaterThan(samples.count, 1_400)
        XCTAssertLessThan(samples.count, 1_700)
    }

    @MainActor
    func testChineseLanguageIdentifiersDoNotTriggerTranslation() {
        XCTAssertTrue(CaptionViewModel.languagesMatch("zh", "zh-Hans"))
        XCTAssertTrue(CaptionViewModel.languagesMatch("zh_CN", "zh-Hans"))
        XCTAssertTrue(CaptionViewModel.languagesMatch("cmn", "zh-CN"))
        XCTAssertFalse(CaptionViewModel.languagesMatch("en", "zh-Hans"))
        XCTAssertFalse(CaptionViewModel.languagesMatch("und", "zh-Hans"))
    }

    @MainActor
    func testRecordingWritesTwoAudioTracksAndTimestampedTranscript() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveCaptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = RecordingService()
        try service.start(mode: .system,
                          directory: root,
                          includeSpeakers: true,
                          includeTranslations: true)
        service.append([Float](repeating: 0.1, count: 16_000), source: .system)
        try service.updateMode(.both)
        service.append([Float](repeating: 0.1, count: 16_000), source: .microphone)
        let lineID = UUID()
        service.appendTranscript(SessionTranscriptEntry(timestamp: 3.4,
                                                        source: .system,
                                                        speaker: "说话人 2",
                                                        original: "测试内容",
                                                        translated: ""),
                                 lineID: lineID)
        service.appendTranscript(SessionTranscriptEntry(timestamp: 3.8,
                                                        source: .microphone,
                                                        speaker: "我",
                                                        original: "测试内容",
                                                        translated: "Test content"))

        let stopped = await service.stop()
        let result = try XCTUnwrap(stopped)
        XCTAssertEqual(result.audioFiles.count, 2)
        for url in result.audioFiles {
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 44)
        }
        let transcript = try String(contentsOf: result.transcript, encoding: .utf8)
        XCTAssertTrue(transcript.contains("[00:00:03] 说话人 2  测试内容"))
        XCTAssertFalse(transcript.contains("翻译：Test content"))
        XCTAssertEqual(transcript.components(separatedBy: "测试内容").count - 1, 1)

        let translatedURL = try XCTUnwrap(result.translatedTranscript)
        service.updateTranslation(lineID: lineID,
                                  original: "测试内容",
                                  translated: "Test content")
        let translatedTranscript = try String(contentsOf: translatedURL, encoding: .utf8)
        XCTAssertTrue(translatedTranscript.contains("翻译：Test content"))
    }

    func testTranscriptSimilarityHandlesMinorCorrections() {
        XCTAssertTrue(TranscriptSimilarity.isLikelyDuplicate(
            "Welcome everyone to today's meeting.",
            "Welcome, everyone, to today's meeting!",
            threshold: 0.82
        ))
        XCTAssertFalse(TranscriptSimilarity.isLikelyDuplicate(
            "Welcome everyone to today's meeting.",
            "The project deadline is next Friday.",
            threshold: 0.72
        ))
    }

    func testWhisperOverlapRemovalIgnoresPunctuationAndCase() {
        let result = TranscriptSimilarity.removingLeadingOverlap(
            previous: "Welcome, everyone! THIS is a test.",
            current: "This is a test — and now we continue."
        )
        XCTAssertEqual(result, "— and now we continue.")
    }

    @MainActor
    func testLatestRecordingIsRestoredAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveCaptionRestore-\(UUID().uuidString)", isDirectory: true)
        let older = root.appendingPathComponent("LiveCaption_older", isDirectory: true)
        let newer = root.appendingPathComponent("LiveCaption_newer", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "older".write(to: older.appendingPathComponent("字幕记录.txt"), atomically: true, encoding: .utf8)
        try "newer".write(to: newer.appendingPathComponent("字幕记录.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                              ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)],
                                              ofItemAtPath: newer.path)

        let service = RecordingService()
        service.restoreLatestResult(in: root)

        XCTAssertEqual(service.lastResult?.folder.lastPathComponent, newer.lastPathComponent)
        XCTAssertEqual(service.lastResult?.transcript.lastPathComponent, "字幕记录.txt")
        XCTAssertEqual(try service.lastResult?.transcript.resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier as? NSObject,
                       try newer.appendingPathComponent("字幕记录.txt")
            .resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject)
    }

    @MainActor
    func testSummaryAlwaysProducesAFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveCaptionSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appendingPathComponent("字幕记录.txt")
        try """
        LiveCaption 字幕记录

        [00:00:01] 说话人 1  我们需要在周五前完成界面。
        [00:00:05] 说话人 2  决定由小王负责测试。
        """.write(to: transcript, atomically: true, encoding: .utf8)

        let service = SummaryService()
        let generated = await service.generate(from: transcript, provider: .local)
        let summaryURL = try XCTUnwrap(generated)
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(summary.contains("录音总结"))
        XCTAssertTrue(summary.contains("周五"))
    }
}
