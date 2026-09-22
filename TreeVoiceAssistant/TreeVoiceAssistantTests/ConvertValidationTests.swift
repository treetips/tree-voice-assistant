import Foundation
import Testing

@testable import TreeVoiceAssistant

/// テスト用の仮エンジン。
struct FakeTranscriptionEngine: TranscriptionEngine {
    var text: String = "仮の文字起こし"
    var error: (any Error & Sendable)?

    func transcribe(audioURL: URL, modelID: String) async throws -> String {
        if let error { throw error }
        return text
    }
}

/// テスト用の仮合成。無音wavを置く。
struct FakeSynthesizer: SpeechSynthesizer {
    func synthesize(request: TTSRequest) async throws -> URL {
        try FileManager.default.createDirectory(
            at: request.outputDirectory, withIntermediateDirectories: true)
        let url = request.outputDirectory
            .appendingPathComponent(MLXAudioTTSService.timestampFileName(), isDirectory: false)
        try silentWavData().write(to: url, options: .atomic)
        return url
    }
}

/// テスト用の終わらない合成。取り消されると `CancellationError` で終わる。
struct HangingSynthesizer: SpeechSynthesizer {
    func synthesize(request: TTSRequest) async throws -> URL {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}

/// 8000Hzモノラル16bit・0.1秒の無音wav。
func silentWavData() -> Data {
    let rate: UInt32 = 8000
    let samples: UInt32 = 800
    var data = Data()
    func append(_ string: String) { data.append(contentsOf: string.utf8) }
    func appendU32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    func appendU16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    append("RIFF")
    appendU32(36 + samples * 2)
    append("WAVEfmt ")
    appendU32(16)
    appendU16(1)
    appendU16(1)
    appendU32(rate)
    appendU32(rate * 2)
    appendU16(2)
    appendU16(16)
    append("data")
    appendU32(samples * 2)
    data.append(contentsOf: [UInt8](repeating: 0, count: Int(samples) * 2))
    return data
}

@Suite("ConvertValidation")
struct ConvertValidationTests {
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

    @Test("初期状態は実行できない")
    @MainActor
    func initialCannotRun() throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        #expect(viewModel.canRunTranscription == false)
        #expect(viewModel.canRunSynthesis == false)
        #expect(viewModel.canPlay == false)
    }

    @Test("音声以外は受け付けない")
    @MainActor
    func rejectsNonAudio() throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([URL(fileURLWithPath: "/tmp/note.txt")])
        #expect(viewModel.audioFileURL == nil)
        #expect(viewModel.canRunTranscription == false)
    }

    @Test("文字起こしで文章が埋まる")
    @MainActor
    func transcriptionFillsText() async throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(text: "こんにちは"), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        #expect(viewModel.canRunTranscription == true)
        viewModel.runTranscription()
        #expect(jobStore.isTranscribing == true)
        while jobStore.isTranscribing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.transcriptionText == "こんにちは")
        #expect(viewModel.speechText.isEmpty)
        #expect(jobStore.lastRunSucceeded == true)
    }

    @Test("合成で出力が再生可能になる")
    @MainActor
    func synthesisEnablesPlay() async throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.speechText = "よむ"
        #expect(viewModel.canRunSynthesis == true)
        viewModel.runSynthesis()
        while jobStore.isSynthesizing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(jobStore.lastRunSucceeded == true)
        #expect(viewModel.canPlay == true)
    }

    @Test("入力しても自動では始まらない（手動実行のみ）")
    @MainActor
    func noAutoStart() async throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: FakeSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.transcriptionText = "台本"
        viewModel.speechText = "よむ"
        try await Task.sleep(for: .milliseconds(50))
        #expect(jobStore.isTranscribing == false)
        #expect(jobStore.isSynthesizing == false)
        #expect(jobStore.lastRunSucceeded == nil)
    }

    @Test("合成実行は取り消せる")
    @MainActor
    func synthesisCancel() async throws {
        let jobStore = ConvertJobStore()
        let viewModel = ConvertViewModel(
            jobStore: jobStore, store: try makeStore(),
            transcription: FakeTranscriptionEngine(), synthesizer: HangingSynthesizer())
        viewModel.acceptAudioURLs([try makeAudio()])
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.speechText = "よむ"
        viewModel.runSynthesis()
        #expect(jobStore.isSynthesizing == true)
        viewModel.cancelSynthesis()
        #expect(jobStore.isSynthesizing == false)
        #expect(jobStore.lastRunSucceeded == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(jobStore.isSynthesizing == false)
        #expect(jobStore.lastRunSucceeded == nil)
    }
}
