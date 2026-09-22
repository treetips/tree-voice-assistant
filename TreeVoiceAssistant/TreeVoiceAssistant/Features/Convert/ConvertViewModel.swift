import AVFoundation
import Foundation

/// 音声変換画面のフォーム状態。`settings.json` の `convert` セクションに保存する。
/// 実行状態は共有の `ConvertJobStore` が持つ。
@Observable
@MainActor
final class ConvertViewModel {
    var audioFileURL: URL? {
        didSet { save() }
    }
    var audioFileName: String = "" {
        didSet { save() }
    }
    var whisperModel: String = WhisperModel.default.rawValue {
        didSet { save() }
    }
    var transcriptionText: String = "" {
        didSet { save() }
    }
    var outputFolderPath: String = "" {
        didSet {
            validateOutputFolder()
            save()
        }
    }
    var outputFolderHasError = false
    var ttsModel: String = TTSModel.default.rawValue {
        didSet { save() }
    }
    var speechText: String = "" {
        didSet { save() }
    }

    private let store: SettingsStore
    private let jobStore: ConvertJobStore
    private let transcriptionEngine: any TranscriptionEngine
    private let synthesizerEngine: any SpeechSynthesizer
    private let notifier: CompletionNotifier
    private var audioPlayer: AVAudioPlayer?
    private var transcriptionTask: Task<Void, Never>?
    private var synthesisTask: Task<Void, Never>?
    /// 実行世代。取り消し・再実行で古い完了処理を無効化する。
    private var transcriptionGen = 0
    private var synthesisGen = 0

    init(
        jobStore: ConvertJobStore,
        store: SettingsStore? = nil,
        transcription: (any TranscriptionEngine)? = nil,
        synthesizer: (any SpeechSynthesizer)? = nil
    ) {
        self.jobStore = jobStore
        let paths = AppPaths()
        let settingsStore = store ?? SettingsStore(paths: paths)
        self.store = settingsStore
        // 実行のたびに作り直すとモデルの解決・読み込みを繰り返すため共有する。
        self.transcriptionEngine = transcription ?? WhisperKitEngine()
        self.synthesizerEngine = synthesizer ?? MLXAudioTTSService()
        self.notifier = CompletionNotifier(store: settingsStore)
        load()
    }

    /// 文字起こし実行の可否。入力音声があり、実行中でなければ可能。
    var canRunTranscription: Bool {
        audioFileURL != nil && !jobStore.isRunning
    }

    /// 音声合成実行の可否。参照音声・出力フォルダが正常で、文章があり、実行中でなければ可能。
    var canRunSynthesis: Bool {
        audioFileURL != nil && !outputFolderPath.isEmpty && !outputFolderHasError
            && !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !jobStore.isRunning
    }

    /// 再生の可否。合成済みファイルがあり、実行中でなければ可能。
    var canPlay: Bool {
        jobStore.outputFileURL != nil && !jobStore.isRunning
    }

    /// ドロップ・選択されたURLから音声ファイル1件を受け付ける。
    func acceptAudioURLs(_ urls: [URL]) {
        guard !jobStore.isRunning else { return }
        guard let url = urls.first(where: { SupportedAudio.isAudio($0) }) else { return }
        audioFileURL = url
        audioFileName = url.lastPathComponent
        jobStore.lastRunSucceeded = nil
        jobStore.resultMessage = ""
    }

    /// 文字起こし実行。重い推論はメインスレッド外で行い、状態更新だけ戻す。
    /// タスクがViewModelを保持するため、画面を切り替えても状態は最後まで解決する。
    func runTranscription() {
        guard canRunTranscription, let source = audioFileURL else { return }
        transcriptionGen += 1
        let gen = transcriptionGen
        transcriptionTask?.cancel()
        jobStore.isTranscribing = true
        jobStore.resultMessage = ""
        let modelID = WhisperModel(rawValue: whisperModel)?.argmaxModelID
            ?? WhisperModel.default.argmaxModelID
        let engine = transcriptionEngine
        let cancelledMessage = msg("v.cancelled")
        transcriptionTask = Task.detached {
            do {
                let text = try await engine.transcribe(audioURL: source, modelID: modelID)
                await MainActor.run {
                    self.finishTranscription(gen: gen, text: text, errorMessage: nil)
                }
            } catch {
                let message = error is CancellationError ? cancelledMessage : error.localizedDescription
                await MainActor.run {
                    self.finishTranscription(gen: gen, text: nil, errorMessage: message)
                }
            }
        }
    }

    /// 文字起こし実行を取り消す。
    func cancelTranscription() {
        transcriptionGen += 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        jobStore.isTranscribing = false
        jobStore.lastRunSucceeded = nil
        jobStore.resultMessage = msg("v.cancelled")
    }

    /// 文字起こしの後処理。現行世代の場合のみメインアクターで状態を更新する。
    private func finishTranscription(gen: Int, text: String?, errorMessage: String?) {
        guard gen == transcriptionGen else { return }
        if let text {
            transcriptionText = text
            jobStore.lastRunSucceeded = true
        } else {
            jobStore.lastRunSucceeded = false
            jobStore.resultMessage = errorMessage ?? ""
        }
        jobStore.isTranscribing = false
        transcriptionTask = nil
        Task { await notifyFinished() }
    }

    /// 音声合成実行（ファイル出力）。重い推論はメインスレッド外で行い、状態更新だけ戻す。
    /// 初回はモデルの取得に時間がかかるため、先にその旨を表示する。
    /// タスクがViewModelを保持するため、画面を切り替えても状態は最後まで解決する。
    func runSynthesis() {
        stopPlayback()
        guard canRunSynthesis, let refAudio = audioFileURL else { return }
        synthesisGen += 1
        let gen = synthesisGen
        synthesisTask?.cancel()
        jobStore.isSynthesizing = true
        jobStore.resultMessage = msg("v.stagePrepare")
        let modelID = TTSModel(rawValue: ttsModel)?.mlxAudioModelID ?? TTSModel.default.mlxAudioModelID
        let request = TTSRequest(
            model: modelID,
            refAudioURL: refAudio,
            refText: transcriptionText,
            text: speechText,
            outputDirectory: URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        )
        let engine = synthesizerEngine
        let cancelledMessage = msg("v.cancelled")
        synthesisTask = Task.detached {
            do {
                let url = try await engine.synthesize(request: request)
                await MainActor.run {
                    self.finishSynthesis(gen: gen, outputURL: url, errorMessage: nil)
                }
            } catch {
                let message = error is CancellationError ? cancelledMessage : error.localizedDescription
                await MainActor.run {
                    self.finishSynthesis(gen: gen, outputURL: nil, errorMessage: message)
                }
            }
        }
    }

    /// 音声合成実行を取り消す。モデルの取得中も中断される。
    func cancelSynthesis() {
        synthesisGen += 1
        synthesisTask?.cancel()
        synthesisTask = nil
        stopPlayback()
        jobStore.isSynthesizing = false
        jobStore.lastRunSucceeded = nil
        jobStore.resultMessage = msg("v.cancelled")
    }

    /// 音声合成の後処理。現行世代の場合のみメインアクターで状態を更新する。
    private func finishSynthesis(gen: Int, outputURL: URL?, errorMessage: String?) {
        guard gen == synthesisGen else { return }
        if let outputURL {
            jobStore.outputFileURL = outputURL
            jobStore.lastRunSucceeded = true
        } else {
            jobStore.lastRunSucceeded = false
            jobStore.resultMessage = errorMessage ?? ""
        }
        jobStore.isSynthesizing = false
        synthesisTask = nil
        Task { await notifyFinished() }
    }

    /// 再生中の音声を止める。
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// 合成済み音声を再生する。
    func playOutput() {
        guard canPlay, let url = jobStore.outputFileURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            jobStore.isPlaying = true
            player.play()
            Task {
                try? await Task.sleep(for: .seconds(player.duration))
                jobStore.isPlaying = false
            }
        } catch {
            jobStore.resultMessage = error.localizedDescription
        }
    }

    private func notifyFinished() async {
        if let player = await notifier.finish(
            allSuccess: jobStore.lastRunSucceeded ?? false,
            language: currentLanguage()
        ) {
            audioPlayer = player
            player.play()
        }
    }

    private func currentLanguage() -> String {
        (try? store.load(maxParallel: ProcessInfo.processInfo.processorCount).settings.language) ?? ""
    }

    private func msg(_ key: String) -> String {
        L10n.string(key, language: currentLanguage())
    }

    private func validateOutputFolder() {
        if outputFolderPath.isEmpty {
            outputFolderHasError = false
            return
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outputFolderPath, isDirectory: &isDir)
        outputFolderHasError = !(exists && isDir.boolValue)
    }

    private func load() {
        guard let file = try? store.load(maxParallel: ProcessInfo.processInfo.processorCount) else { return }
        let saved = file.convert
        whisperModel = saved.whisperModel
        transcriptionText = saved.transcriptionText
        outputFolderPath = saved.outputFolderPath ?? ""
        ttsModel = saved.ttsModel
        speechText = saved.speechText
        validateOutputFolder()
    }

    private func save() {
        guard let file = try? store.load(maxParallel: ProcessInfo.processInfo.processorCount) else { return }
        var updated = file
        updated.convert.whisperModel = whisperModel
        updated.convert.transcriptionText = transcriptionText
        updated.convert.outputFolderPath = outputFolderPath.isEmpty ? nil : outputFolderPath
        updated.convert.ttsModel = ttsModel
        updated.convert.speechText = speechText
        try? store.save(updated)
    }
}
