# Irodori-TTS併設 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 変換画面のTTSプルダウンでQwen2件とIrodori2件を選べ、Irodori選択時はcaption必須・事前文字起こし必須で直接合成できる。

**Architecture:** `tools/tts`と`tools/tts-irodori`のuv環境を分離し、`ConvertViewModel`でエンジンを分岐する。`TTSRequest`に`caption`を追加しQwen側は無視する。

**Tech Stack:** SwiftUI / Swift Testing / uv管理Python（Irodori-TTSのinfer.py、torch cpu）

**Spec:** `docs/superpowers/specs/2026-10-01-irodori-tts-design.md`

## Global Constraints

- TTS実行環境は同梱せず初回実行時に調達する（Qwenと同様の方針）。
- `tools/tts`（mlx-audio）と`tools/tts-irodori`（Irodori）を混載しない。
- Irodori選択時は`transcriptionText`非空かつ`captionText`非空でないと実行不可。文字起こし文のcaptionへの自動転記はしない。
- Qwen選択時の動作・保存済み設定の読み込み互換を保つ。
- 変更後はlint→フォーマット→ビルド→関連単体テストを実行する。
- git操作はユーザーの指示なしに行わない。

## Review Focus

- Irodori選択時にcaption空欄で実行ボタンが有効になる → 無効のままであること。
- Irodori選択時に文字起こし未実施で実行ボタンが有効になる → 無効のままであること。
- Qwen選択時にcaption欄が表示される → 表示されないこと。
- 旧settings.json（captionなし）が読めなくなる → 既定値で読めること。
- プルダウン切替時に前回選択が保存・復元されない → 保存・復元されること。

---

### Task 1: TTSモデル列挙とリクエスト拡張

**Files:**
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Core/Models.swift:46-62`
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Core/EngineProtocols.swift:8-15`
- Modify: `TreeVoiceAssistant/TreeVoiceAssistantTests/WhisperMappingTests.swift:26-31`

**Interfaces:**
- Consumes: なし（既存の`TTSModel`、`TTSRequest`を拡張する）。
- Produces: `TTSModel.irodoriV41Small`、`TTSModel.irodoriV41SmallMF`、`TTSModel.irodoriHFCheckpoint: String?`、`TTSModel.isIrodori: Bool`、`TTSRequest.caption: String?`。Task 2・3が利用する。

- [ ] **Step 1: Write the failing test**

`TreeVoiceAssistant/TreeVoiceAssistantTests/WhisperMappingTests.swift`の`ttsModelIDs()`に次を追加する。

```swift
#expect(TTSModel.irodoriV41Small.irodoriHFCheckpoint == "Aratako/Irodori-TTS-v4.1-Small")
#expect(TTSModel.irodoriV41SmallMF.irodoriHFCheckpoint == "Aratako/Irodori-TTS-v4.1-Small-MF")
#expect(TTSModel.qwen17B.irodoriHFCheckpoint == nil)
#expect(TTSModel.irodoriV41Small.isIrodori == true)
#expect(TTSModel.qwen17B.isIrodori == false)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/WhisperMappingTests 2>&1 | tail -5`
Expected: FAIL（`irodoriV41Small`が未定義のためコンパイルエラー）。

- [ ] **Step 3: Write minimal implementation**

`Core/Models.swift`の`TTSModel`を次にする。

```swift
enum TTSModel: String, Hashable, Identifiable, CaseIterable {
    case qwen17B = "Qwen3-TTS-12Hz-1.7B"
    case qwen06B = "Qwen3-TTS-12Hz-0.6B"
    case irodoriV41Small = "Irodori-TTS-v4.1-Small"
    case irodoriV41SmallMF = "Irodori-TTS-v4.1-Small-MF"

    var id: String { rawValue }

    static var `default`: TTSModel { .qwen17B }

    var mlxAudioModelID: String {
        switch self {
        case .qwen17B: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit"
        case .qwen06B: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
        case .irodoriV41Small, .irodoriV41SmallMF: return ""
        }
    }

    var isIrodori: Bool {
        switch self {
        case .irodoriV41Small, .irodoriV41SmallMF: return true
        case .qwen17B, .qwen06B: return false
        }
    }

    var irodoriHFCheckpoint: String? {
        switch self {
        case .irodoriV41Small: return "Aratako/Irodori-TTS-v4.1-Small"
        case .irodoriV41SmallMF: return "Aratako/Irodori-TTS-v4.1-Small-MF"
        case .qwen17B, .qwen06B: return nil
        }
    }
}
```

`Core/EngineProtocols.swift`の`TTSRequest`に`caption`を追加する。

```swift
struct TTSRequest: Sendable, Equatable {
    var model: String
    var refAudioURL: URL
    var refText: String
    var text: String
    var outputDirectory: URL
    var caption: String? = nil
}
```

既存の初期化箇所は引数追加なしで通る（既定値`nil`のため）。

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/WhisperMappingTests 2>&1 | tail -5`
Expected: PASS。

- [ ] **Step 5: 検証**

Run: `xcodebuild build -scheme TreeVoiceAssistant -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED。

### Task 2: IrodoriTTSServiceの新設

**Files:**
- Create: `TreeVoiceAssistant/TreeVoiceAssistant/Services/IrodoriTTSService.swift`
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Services/AppPaths.swift:63-66`
- Test: `TreeVoiceAssistant/TreeVoiceAssistantTests/IrodoriTTSServiceTests.swift`（新規）

**Interfaces:**
- Consumes: Task 1の`TTSRequest.caption`。
- Produces: `IrodoriTTSService: SpeechSynthesizer`、`AppPaths.ttsIrodoriURL`、`IrodoriTTSService.generateArguments(request:projectDirectory:sourceDirectory:outputDirectory:)`。Task 3が利用する。

- [ ] **Step 1: Write the failing test**

`TreeVoiceAssistant/TreeVoiceAssistantTests/IrodoriTTSServiceTests.swift`を新規作成する。

```swift
import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("IrodoriTTSService")
struct IrodoriTTSServiceTests {
    @Test("infer.pyの引数を組み立てる")
    func arguments() throws {
        let ref = URL(fileURLWithPath: "/tmp/ref.wav", isDirectory: false)
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let proj = URL(fileURLWithPath: "/tmp/tts-irodori", isDirectory: true)
        let src = URL(fileURLWithPath: "/tmp/tts-irodori/src", isDirectory: true)
        let request = TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small",
            refAudioURL: ref,
            refText: "無視される",
            text: "よむ",
            outputDirectory: out,
            caption: "落ち着いた声"
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(args.contains("infer.py"))
        #expect(args.contains("Aratako/Irodori-TTS-v4.1-Small"))
        #expect(args.contains("/tmp/ref.wav"))
        #expect(args.contains("落ち着いた声"))
        #expect(!args.contains("--ref_text"))
    }

    @Test("captionが空なら--captionを付けない")
    func noCaptionFlag() throws {
        let ref = URL(fileURLWithPath: "/tmp/ref.wav", isDirectory: false)
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let proj = URL(fileURLWithPath: "/tmp/tts-irodori", isDirectory: true)
        let src = URL(fileURLWithPath: "/tmp/tts-irodori/src", isDirectory: true)
        let request = TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small",
            refAudioURL: ref,
            refText: "",
            text: "よむ",
            outputDirectory: out,
            caption: nil
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(!args.contains("--caption"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/IrodoriTTSServiceTests 2>&1 | tail -5`
Expected: FAIL（`IrodoriTTSService`未定義のためコンパイルエラー）。

- [ ] **Step 3: Write minimal implementation**

`Services/AppPaths.swift`に次を追加する。

```swift
/// Irodori実行環境の配置先。`<基準>/tools/tts-irodori`（pyproject＋.venv＋src）。
var ttsIrodoriURL: URL {
    toolsURL.appendingPathComponent("tts-irodori", isDirectory: true)
}
```

`Services/IrodoriTTSService.swift`を新規作成する。`MLXAudioTTSService`と同形にし、出力改名規則（JSTの`${yyyyMMddHHmmss}.wav`）は`MLXAudioTTSService`の静的関数を再利用する。

```swift
import Foundation

/// 外部プロセス版のIrodori音声合成。`uv`管理のPython環境で
/// Irodori-TTSの`infer.py`を実行し、`--ref-wav`＋`--caption`で合成する。
/// `tools/tts`（mlx-audio）とは別環境`tools/tts-irodori`を使う。
final class IrodoriTTSService: SpeechSynthesizer, @unchecked Sendable {
    static let repoURL = "https://github.com/Aratako/Irodori-TTS"
    static let repoPinnedRevision = "main"

    static func pyprojectContent() -> String {
        """
        [project]
        name = "tree-voice-tts-irodori"
        version = "0.1.0"
        requires-python = ">=3.10"
        dependencies = [
            "irodori-tts",
        ]

        [dependency-sources]
        irodori-tts = { git = "\(repoURL)", rev = "\(repoPinnedRevision)" }

        [tool.uv.sources]
        torch = { index = "pytorch-cpu", extra = "cpu", marker = "sys_platform == 'linux' or sys_platform == 'win32'" }
        torchaudio = { index = "pytorch-cpu", extra = "cpu", marker = "sys_platform == 'linux' or sys_platform == 'win32'" }

        [[tool.uv.index]]
        name = "pytorch-cpu"
        url = "https://download.pytorch.org/whl/cpu"
        explicit = true

        [project.optional-dependencies]
        cpu = [
            "torch>=2.10.0,<2.11.0",
            "torchao>=0.16.0,<0.17.0",
            "torchaudio>=2.10.0,<2.11.0",
            "torchcodec>=0.10.0,<0.11.0",
        ]
        """
    }

    private let paths: AppPaths
    private let installer: UVInstaller
    private let command: RunCommand

    init(paths: AppPaths = AppPaths(), installer: UVInstaller? = nil, command: RunCommand? = nil) {
        self.paths = paths
        let run: RunCommand = command ?? { executable, args, workingDirectory in
            try await ProcessRunner().runCancellable(
                executable, args: args, workingDirectory: workingDirectory)
        }
        self.command = run
        self.installer = installer ?? UVInstaller(paths: paths, command: run)
    }

    func synthesize(request: TTSRequest) async throws -> URL {
        try Task.checkCancellation()
        let uvPath = try await installer.uvExecutable()
        let sourceDirectory = try await ensureEnvironment(uvPath: uvPath)
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let productDir = fileManager.temporaryDirectory
            .appendingPathComponent("tree-voice-irodori-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: productDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: productDir) }
        let args = Self.generateArguments(
            request: request,
            projectDirectory: paths.ttsIrodoriURL,
            sourceDirectory: sourceDirectory,
            outputDirectory: productDir)
        do {
            _ = try await command(uvPath, args, nil)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
        try Task.checkCancellation()
        guard let produced = MLXAudioTTSService.newestWav(in: productDir) else {
            throw AppError.fileNotFound(path: productDir.appendingPathComponent("result*.wav").path)
        }
        try fileManager.createDirectory(
            at: request.outputDirectory, withIntermediateDirectories: true)
        let destination = request.outputDirectory
            .appendingPathComponent(MLXAudioTTSService.timestampFileName(), isDirectory: false)
        try MLXAudioTTSService.moveOrCopy(item: produced, to: destination)
        return destination
    }

    static func generateArguments(
        request: TTSRequest, projectDirectory: URL, sourceDirectory: URL, outputDirectory: URL
    ) -> [String] {
        var args = [
            "run", "--project", projectDirectory.path, "--extra", "cpu",
            "python", sourceDirectory.appendingPathComponent("infer.py", isDirectory: false).path,
            "--hf-checkpoint", request.model,
            "--text", request.text,
            "--ref-wav", request.refAudioURL.path,
            "--output-wav", outputDirectory.appendingPathComponent("result.wav", isDirectory: false).path,
            "--model-device", "auto",
        ]
        if let caption = request.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty
        {
            args += ["--caption", caption]
        }
        return args
    }

    private func ensureEnvironment(uvPath: String) async throws -> URL {
        let toolsDir = paths.ttsIrodoriURL
        try FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        let checkoutDir = toolsDir.appendingPathComponent("Irodori-TTS", isDirectory: true)
        let inferPy = checkoutDir.appendingPathComponent("infer.py", isDirectory: false)
        if !FileManager.default.fileExists(atPath: inferPy.path) {
            do {
                _ = try await command(
                    "/usr/bin/git",
                    ["clone", "--depth", "1", "--branch", "main", Self.repoURL, checkoutDir.path], nil)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                throw AppError.gitMissing
            }
        }
        let pyproject = toolsDir.appendingPathComponent("pyproject.toml", isDirectory: false)
        let expected = Self.pyprojectContent()
        if (try? String(contentsOf: pyproject, encoding: .utf8)) != expected {
            try expected.write(to: pyproject, atomically: true, encoding: .utf8)
        }
        do {
            _ = try await command(uvPath, ["sync", "--extra", "cpu"], toolsDir.path)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
        return checkoutDir
    }
}
```

注意: ホストに`git`が無い場合は`AppError.gitMissing`を使う。`AppError`の既存ケース一覧を確認し、無ければ`case gitMissing`を追加する。この追加もこのタスク内で行う。

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/IrodoriTTSServiceTests 2>&1 | tail -5`
Expected: PASS。

- [ ] **Step 5: 検証**

Run: `xcodebuild build -scheme TreeVoiceAssistant -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED。

### Task 3: ViewModelの分岐と実行条件・永続化

**Files:**
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Services/SettingsStore.swift:3-20`
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Features/Convert/ConvertViewModel.swift`
- Test: `TreeVoiceAssistant/TreeVoiceAssistantTests/ConvertValidationTests.swift`（追加）

**Interfaces:**
- Consumes: Task 1の`isIrodori`・`irodoriHFCheckpoint`、Task 2の`IrodoriTTSService`。
- Produces: `ConvertViewModel.captionText`、`ConvertViewModel.isIrodoriSelected`。Task 4が利用する。

- [ ] **Step 1: Write the failing test**

`ConvertValidationTests.swift`に次を追加する。

```swift
@Test("Irodori選択時はcaptionと文字起こしが必須")
@MainActor
func irodoriRequiresCaptionAndTranscription() throws {
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
    #expect(viewModel.canRunSynthesis == false)
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
    {"settings":{"showOsNotification":false,"playSound":false,"successSound":"","errorSound":"","language":"","appearance":"auto","fontSize":"standard","wallpaper":"none","wallpaperOpacity":1.0,"wallpaperBackgroundColor":"#1E1E1E"},"convert":{"whisperModel":"x","transcriptionText":"","ttsModel":"y","speechText":""}}
    """
    let decoded = try JSONDecoder().decode(AppSettingsFile.self, from: Data(json.utf8))
    #expect(decoded.convert.captionText == "")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/ConvertValidationTests 2>&1 | tail -5`
Expected: FAIL（`captionText`未定義のためコンパイルエラー）。

- [ ] **Step 3: Write minimal implementation**

`SettingsStore.swift`の`ConvertSettings`に`captionText`を追加する。旧設定互換のため`init(from:)`で`decodeIfPresent`を使う。

```swift
struct ConvertSettings: Codable, Equatable {
    var whisperModel: String
    var transcriptionText: String
    var outputFolderPath: String?
    var ttsModel: String
    var speechText: String
    var captionText: String

    enum CodingKeys: String, CodingKey {
        case whisperModel
        case transcriptionText
        case outputFolderPath
        case ttsModel
        case speechText
        case captionText
    }

    init(
        whisperModel: String, transcriptionText: String, outputFolderPath: String?,
        ttsModel: String, speechText: String, captionText: String = ""
    ) {
        self.whisperModel = whisperModel
        self.transcriptionText = transcriptionText
        self.outputFolderPath = outputFolderPath
        self.ttsModel = ttsModel
        self.speechText = speechText
        self.captionText = captionText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whisperModel = try container.decode(String.self, forKey: .whisperModel)
        transcriptionText = try container.decode(String.self, forKey: .transcriptionText)
        outputFolderPath = try container.decodeIfPresent(String.self, forKey: .outputFolderPath)
        ttsModel = try container.decode(String.self, forKey: .ttsModel)
        speechText = try container.decode(String.self, forKey: .speechText)
        captionText = try container.decodeIfPresent(String.self, forKey: .captionText) ?? ""
    }

    static func defaults() -> ConvertSettings {
        ConvertSettings(
            whisperModel: WhisperModel.default.rawValue,
            transcriptionText: "",
            outputFolderPath: nil,
            ttsModel: TTSModel.default.rawValue,
            speechText: "",
            captionText: ""
        )
    }
}
```

`ConvertViewModel.swift`に`captionText`を追加し、`didSet`で`save()`する。`speechText`と同形にする。

```swift
var captionText: String = "" {
    didSet { save() }
}
```

`isIrodoriSelected`を追加する。

```swift
var isIrodoriSelected: Bool {
    TTSModel(rawValue: ttsModel)?.isIrodori ?? false
}
```

`canRunSynthesis`を次にする。

```swift
var canRunSynthesis: Bool {
    guard audioFileURL != nil, !outputFolderPath.isEmpty, !outputFolderHasError,
        !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !jobStore.isRunning
    else { return false }
    if isIrodoriSelected {
        guard !transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
    }
    return true
}
```

`runSynthesis()`のモデル解決と要求組み立てを次にする。

```swift
let selected = TTSModel(rawValue: ttsModel) ?? TTSModel.default
let modelID: String
let caption: String?
if selected.isIrodori {
    modelID = selected.irodoriHFCheckpoint ?? "Aratako/Irodori-TTS-v4.1-Small"
    caption = captionText
} else {
    modelID = selected.mlxAudioModelID
    caption = nil
}
let engine: any SpeechSynthesizer = selected.isIrodori ? IrodoriTTSService() : synthesizerEngine
let request = TTSRequest(
    model: modelID,
    refAudioURL: refAudio,
    refText: transcriptionText,
    text: speechText,
    outputDirectory: URL(fileURLWithPath: outputFolderPath, isDirectory: true),
    caption: caption
)
```

`load()`と`save()`に`captionText`の復元・保存を追加する。

```swift
captionText = saved.captionText
```

```swift
updated.convert.captionText = captionText
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/ConvertValidationTests 2>&1 | tail -5`
Expected: PASS。

### Task 4: 変換画面のcaption欄

**Files:**
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Features/Convert/ConvertView.swift:227-300`
- Modify: `TreeVoiceAssistant/TreeVoiceAssistant/Resources/Localizable.xcstrings`（`v.label.caption`・`v.captionPlaceholder`の日英）

**Interfaces:**
- Consumes: Task 3の`captionText`・`isIrodoriSelected`。
- Produces: 画面表示。プルダウン自体は既存`ForEach(TTSModel.allCases)`のため自動で4件になる。

- [ ] **Step 1: caption欄を追加する**

`TtsSection`のモデル選択`GridRow`の次に次を追加する。Irodori選択時のみ表示する。

```swift
if viewModel.isIrodoriSelected {
    GridRow {
        Text(text("v.label.caption")).appFont(.headline)
        TextField(text("v.captionPlaceholder"), text: $viewModel.captionText)
            .appFont(.body)
            .disabled(jobStore.isSynthesizing)
            .gridCellColumns(1)
    }
}
```

`Localizable.xcstrings`に`v.label.caption`（日: `声の指定`、英: `Voice style`）と`v.captionPlaceholder`（日: `例: 落ち着いた低めの女性の声。丁寧で穏やかな話し方。`、英: `e.g. Calm female voice, polite and gentle.`）を追加する。既存キーの書式に合わせる。

- [ ] **Step 2: ビルドして目視する**

Run: `xcodebuild build -scheme TreeVoiceAssistant -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED。アプリを起動し、TTSプルダウンが4件、Irodori選択時のみcaption欄が出ることを目視する。

### Task 5: ADRと最終検証

**Files:**
- Create: `docs/adr/010-irodori-tts.md`
- Modify: `docs/adr/INDEX.md:9`（1行追加）

- [ ] **Step 1: ADRを作成する**

`docs/adr/010-irodori-tts.md`を作成する。次の内容にする。

```markdown
# Irodori-TTSの併設（外部プロセス版）

- 音声合成にIrodori-TTSを追加し、Qwen3-TTSと併設した。
  - プルダウン: Qwen3-TTS-12Hz-1.7B／0.6B、Irodori-TTS-v4.1-Small／v4.1-Small-MF。
  - Irodoriは`uv`管理の別環境`tools/tts-irodori`で`infer.py`を実行する
   （`--hf-checkpoint`・`--text`・`--ref-wav`・`--caption`・`--output-wav`）。
  - `tools/tts`（mlx-audio）とは混載しない。依存衝突を避けるため。
  - Irodori選択時はcaption必須・事前文字起こし必須。`--ref_text`は渡さない。
  - v4-Large・量子化バリアント・v2/v3系は対象外。
- 次の番号が空いていない場合は最新の連番を使う。
```

`docs/adr/INDEX.md`の表に`| 010 | Irodori-TTSの併設 | Accepted | 合成方式 |`を追加する。既存の採番と衝突する場合は番号をずらす。

- [ ] **Step 2: lintを実行する**

Run: リポジトリ既定のlintコマンド（`AGENTS.md`の手順に従う）。
Expected: 指摘なし。指摘があれば修正する。

- [ ] **Step 3: フォーマットする**

Run: リポジトリ既定のフォーマッター。
Expected: 差分が整形のみであること。

- [ ] **Step 4: ビルドする**

Run: `xcodebuild build -scheme TreeVoiceAssistant -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: 関連テストを実行する**

Run: `xcodebuild test -scheme TreeVoiceAssistant -destination 'platform=macOS' -only-testing:TreeVoiceAssistantTests/WhisperMappingTests -only-testing:TreeVoiceAssistantTests/IrodoriTTSServiceTests -only-testing:TreeVoiceAssistantTests/ConvertValidationTests 2>&1 | tail -5`
Expected: 全PASS。
