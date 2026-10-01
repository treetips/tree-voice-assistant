import Foundation

/// 外部プロセス版の音声合成。`uv` 管理のPython環境で
/// `mlx_audio.tts.generate` を実行し、参照音声の声で読み上げる（声クローン）。
/// 初回実行時に実行環境（.venv）とモデルを取得する。
final class MLXAudioTTSService: SpeechSynthesizer, @unchecked Sendable {
    /// 固定する `mlx-audio` の版。ホストの `git` を不要にするためPyPI版を使う。
    static let mlxAudioVersion = "0.5.1"

    /// TTS実行環境の `pyproject.toml`。シェル版の移植に相当する。
    static func pyprojectContent() -> String {
        """
        [project]
        name = "tree-voice-tts"
        version = "0.1.0"
        requires-python = ">=3.10"
        dependencies = [
            "mlx-audio==\(mlxAudioVersion)",
        ]
        """
    }

    /// 出力ファイル名 `${yyyyMMddHHmmss}.wav`。JSTで統一する。
    static func timestampFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date) + ".wav"
    }

    private let paths: AppPaths
    private let installer: UVInstaller
    private let command: RunCommand
    private let logStore: RunLogStore

    init(paths: AppPaths = AppPaths(), installer: UVInstaller? = nil, command: RunCommand? = nil) {
        self.paths = paths
        let hfHub = paths.hfHubURL.path
        let run: RunCommand = command ?? { executable, args, workingDirectory in
            try await ProcessRunner().runCancellable(
                executable, args: args, workingDirectory: workingDirectory,
                environment: ["HF_HUB_CACHE": hfHub])
        }
        self.command = run
        self.installer = installer ?? UVInstaller(paths: paths, command: run)
        self.logStore = RunLogStore(paths: paths)
    }

    /// 実行開始時に掃除する残存プロセスの目印。
    static var staleMarkers: [String] {
        ["tree-voice-tts-", "tree-voice-assistant/tools/tts/", "tree-voice-uv-"]
    }

    /// 合成して出力ファイルに保存する。手動実行用。
    /// 失敗時は全文をログファイルに残し、短い理由とパスを投げる。
    func synthesize(
        request: TTSRequest, onStage: @escaping @Sendable (EngineStage) -> Void
    ) async throws -> URL {
        ProcessRunner.terminateLeftovers(matching: Self.staleMarkers)
        var lines: [String] = [
            "参照音声: \(request.refAudioURL.path)",
            "文章: \(request.text)"
        ]
        onStage(.preparingModel)
        do {
            return try await run(request: request, onStage: onStage, lines: &lines)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            lines.append("失敗: \(error)")
            let logPath = (try? logStore.write(engine: "MLXAudioTTS", model: request.model, lines: lines))?.path
                ?? "-"
            throw AppError.synthesisFailed(reason: RunLogStore.shortReason(for: error), logPath: logPath)
        }
    }

    private func run(
        request: TTSRequest, onStage: @escaping @Sendable (EngineStage) -> Void, lines: inout [String]
    ) async throws -> URL {
        try Task.checkCancellation()
        let uvPath = try await installer.uvExecutable()
        try await ensureEnvironment(uvPath: uvPath, lines: &lines)
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let productDir = fileManager.temporaryDirectory
            .appendingPathComponent("tree-voice-tts-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: productDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: productDir) }
        let args = Self.generateArguments(
            request: request, projectDirectory: paths.ttsToolsURL, outputDirectory: productDir)
        onStage(.running)
        do {
            _ = try await runLogged(command, uvPath, args, nil, lines: &lines)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
        try Task.checkCancellation()
        guard let produced = Self.newestWav(in: productDir) else {
            throw AppError.fileNotFound(path: productDir.appendingPathComponent("result*.wav").path)
        }
        try fileManager.createDirectory(
            at: request.outputDirectory, withIntermediateDirectories: true)
        let destination = request.outputDirectory
            .appendingPathComponent(Self.timestampFileName(), isDirectory: false)
        try Self.moveOrCopy(item: produced, to: destination)
        return destination
    }

    /// シェル版と同一の引数を組み立てる。
    static func generateArguments(
        request: TTSRequest, projectDirectory: URL, outputDirectory: URL
    ) -> [String] {
        [
            "run", "--project", projectDirectory.path,
            "python", "-m", "mlx_audio.tts.generate",
            "--model", request.model,
            "--lang_code", "ja",
            "--ref_audio", request.refAudioURL.path,
            "--ref_text", request.refText,
            "--text", request.text,
            "--file_prefix", "result",
            "--audio_format", "wav",
            "--output", outputDirectory.path,
            "--verbose"
        ]
    }

    /// 実行環境（.venv）を用意する。初回は同期に時間がかかる。
    private func ensureEnvironment(uvPath: String, lines: inout [String]) async throws {
        let ttsDir = paths.ttsToolsURL
        try FileManager.default.createDirectory(at: ttsDir, withIntermediateDirectories: true)
        let pyproject = ttsDir.appendingPathComponent("pyproject.toml", isDirectory: false)
        let expected = Self.pyprojectContent()
        if (try? String(contentsOf: pyproject, encoding: .utf8)) != expected {
            try expected.write(to: pyproject, atomically: true, encoding: .utf8)
        }
        do {
            _ = try await runLogged(command, uvPath, ["sync"], ttsDir.path, lines: &lines)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
    }

    /// 生成物フォルダで最新のwavを探す。
    static func newestWav(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey])
        else { return nil }
        var best: (url: URL, date: Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "wav" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            let date = values.creationDate ?? .distantPast
            if best == nil || date > best!.date {
                best = (url, date)
            }
        }
        return best?.url
    }

    /// 別ボリューム越えでも移動できるよう、失敗時は複写して元を消す。
    static func moveOrCopy(item: URL, to destination: URL) throws {
        do {
            try FileManager.default.moveItem(at: item, to: destination)
        } catch {
            try FileManager.default.copyItem(at: item, to: destination)
            try? FileManager.default.removeItem(at: item)
        }
    }
}
