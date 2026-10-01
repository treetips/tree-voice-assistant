import Foundation
import Testing

@testable import TreeVoiceAssistant

/// テスト用の終わらない文字起こし。実行中を報告してから止まる。
struct HangingTranscriptionEngine: TranscriptionEngine {
    func transcribe(
        audioURL: URL, modelID: String, onStage: @escaping @Sendable (EngineStage) -> Void
    ) async throws -> String {
        onStage(.running)
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}

/// テスト用の要求記録つき合成。無音wavを置く。
final class CapturingSynthesizer: SpeechSynthesizer, @unchecked Sendable {
    var captured: TTSRequest?
    func synthesize(
        request: TTSRequest, onStage: @escaping @Sendable (EngineStage) -> Void
    ) async throws -> URL {
        captured = request
        try FileManager.default.createDirectory(
            at: request.outputDirectory, withIntermediateDirectories: true)
        let url = request.outputDirectory
            .appendingPathComponent(MLXAudioTTSService.timestampFileName(), isDirectory: false)
        try silentWavData().write(to: url, options: .atomic)
        return url
    }
}

@Suite("ConvertStages")
struct ConvertStagesTests {
    func makeStore() throws -> SettingsStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(fileURL: dir.appendingPathComponent("settings.json", isDirectory: false))
    }

    func makeAudio() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("voice.wav", isDirectory: false)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    @Test("Irodori選択時は文字起こしが必須でcaptionは任意")
    @MainActor
    func irodoriRequiresTranscriptionCaptionOptional() throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.ttsModel = TTSModel.irodoriV41Small.rawValue
        viewModel.speechText = "よむ"
        #expect(viewModel.canRunSynthesis == false)
        viewModel.transcriptionText = "起こし済み"
        #expect(viewModel.canRunSynthesis == true)
        viewModel.captionText = "落ち着いた声"
        #expect(viewModel.canRunSynthesis == true)
    }

    @Test("Qwen選択時はcaptionなしで実行できる")
    @MainActor
    func qwenRunsWithoutCaption() throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.ttsModel = TTSModel.qwen17B.rawValue
        viewModel.speechText = "よむ"
        #expect(viewModel.canRunSynthesis == true)
    }

    @Test("captionなしの旧設定が読める")
    func oldSettingsDecode() throws {
        let json = """
            {"settings":{"showOsNotification":false,"playSound":false,"successSound":"","errorSound":"",\
            "language":"","appearance":"auto","fontSize":"standard","wallpaper":"none",\
            "wallpaperOpacity":1.0,"wallpaperBackgroundColor":"#1E1E1E"},\
            "convert":{"whisperModel":"x","transcriptionText":"","ttsModel":"y","speechText":""}}
            """
        let decoded = try JSONDecoder().decode(AppSettingsFile.self, from: Data(json.utf8))
        #expect(decoded.convert.captionText == "")
    }

    @Test("Irodori経路はcaption付き要求を送る")
    @MainActor
    func irodoriSendsCaption() async throws {
        let captor = CapturingSynthesizer()
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer(),
            irodori: captor)
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.ttsModel = TTSModel.irodoriV41SmallMF.rawValue
        viewModel.transcriptionText = "起こし済み"
        viewModel.captionText = "落ち着いた声"
        viewModel.speechText = "よむ"
        viewModel.runSynthesis()
        while jobStore.isSynthesizing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(jobStore.lastRunSucceeded == true)
        #expect(captor.captured?.caption == "落ち着いた声")
        #expect(captor.captured?.model == "Aratako/Irodori-TTS-v4.1-Small-MF")
    }

    @Test("Irodori選択とcaptionが保存・復元される")
    @MainActor
    func irodoriSelectionPersists() throws {
        let store = try makeStore()
        let first = ConvertViewModel(
            jobStore: ConvertJobStore(), store: store,
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        first.ttsModel = TTSModel.irodoriV41SmallMF.rawValue
        first.captionText = "落ち着いた声"
        first.flushSaves()
        let second = ConvertViewModel(
            jobStore: ConvertJobStore(), store: store,
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        #expect(second.ttsModel == TTSModel.irodoriV41SmallMF.rawValue)
        #expect(second.captionText == "落ち着いた声")
    }

    @Test("未取得モデルは警告対象になる")
    @MainActor
    func modelCacheFlags() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true)
        let checker = ModelCacheChecker(
            modelsURL: support.appendingPathComponent("models", isDirectory: true),
            appSupportURL: support,
            legacyDocumentsURL: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHubURL: base.appendingPathComponent("hub", isDirectory: true))
        let viewModel = ConvertViewModel(
            jobStore: ConvertJobStore(), store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer(),
            cacheChecker: checker)
        #expect(viewModel.whisperCached == false)
        viewModel.ttsModel = TTSModel.irodoriV41Small.rawValue
        #expect(viewModel.ttsCached == false)
        viewModel.ttsModel = TTSModel.qwen17B.rawValue
        #expect(viewModel.ttsCached == false)
    }

    @Test("合成段階が伝わる")
    @MainActor
    func synthesisStages() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true)
        let checker = ModelCacheChecker(
            modelsURL: support.appendingPathComponent("models", isDirectory: true),
            appSupportURL: support,
            legacyDocumentsURL: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHubURL: base.appendingPathComponent("hub", isDirectory: true))
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: HangingSynthesizer(),
            cacheChecker: checker)
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.ttsModel = TTSModel.qwen17B.rawValue
        viewModel.speechText = "よむ"
        viewModel.runSynthesis()
        #expect(jobStore.synthesisStage == .preparingModel)
        var waits = 0
        while jobStore.synthesisStage != .running, waits < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        #expect(jobStore.synthesisStage == .running)
        viewModel.cancelSynthesis()
        #expect(jobStore.synthesisStage == .idle)
    }

    @Test("取得済みは実行中から始まる")
    @MainActor
    func cachedStartsRunning() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let hub = support.appendingPathComponent("models/hf-hub", isDirectory: true)
        try FileManager.default.createDirectory(
            at: hub.appendingPathComponent(
                "models--mlx-community--Qwen3-TTS-12Hz-1.7B-Base-6bit", isDirectory: true),
            withIntermediateDirectories: true)
        let checker = ModelCacheChecker(
            modelsURL: support.appendingPathComponent("models", isDirectory: true),
            appSupportURL: support,
            legacyDocumentsURL: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHubURL: base.appendingPathComponent("hub", isDirectory: true))
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: HangingSynthesizer(),
            cacheChecker: checker)
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.ttsModel = TTSModel.qwen17B.rawValue
        viewModel.speechText = "よむ"
        viewModel.runSynthesis()
        #expect(jobStore.synthesisStage == .running)
        viewModel.cancelSynthesis()
    }

    @Test("文字起こし段階が伝わる")
    @MainActor
    func transcriptionStages() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true)
        let checker = ModelCacheChecker(
            modelsURL: support.appendingPathComponent("models", isDirectory: true),
            appSupportURL: support,
            legacyDocumentsURL: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHubURL: base.appendingPathComponent("hub", isDirectory: true))
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: HangingTranscriptionEngine(), synthesizer: FakeSynthesizer(),
            cacheChecker: checker)
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.runTranscription()
        #expect(jobStore.transcriptionStage == .preparingModel)
        var waits = 0
        while jobStore.transcriptionStage != .running, waits < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        #expect(jobStore.transcriptionStage == .running)
        viewModel.cancelTranscription()
        #expect(jobStore.transcriptionStage == .idle)
    }

    @Test("実行時に旧場所を移す")
    @MainActor
    func runMigratesLegacy() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true)
        let checker = ModelCacheChecker(
            modelsURL: support.appendingPathComponent("models", isDirectory: true),
            appSupportURL: support,
            legacyDocumentsURL: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHubURL: base.appendingPathComponent("hub", isDirectory: true))
        let legacy = base.appendingPathComponent(
            "Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny",
            isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        #expect(checker.isWhisperCached("tiny") == false)
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: HangingTranscriptionEngine(), synthesizer: FakeSynthesizer(),
            cacheChecker: checker)
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.runTranscription()
        #expect(checker.isWhisperCached("tiny") == true)
        viewModel.cancelTranscription()
    }

}
