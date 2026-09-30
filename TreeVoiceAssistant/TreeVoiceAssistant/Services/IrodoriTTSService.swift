import Foundation

/// 外部プロセス版のIrodori音声合成。`uv` 管理のPython環境で
/// Irodori-TTSの `infer.py` を実行し、`--ref-wav` と `--caption` で合成する。
/// `tools/tts`（mlx-audio）とは別環境の `tools/tts-irodori` を使う。
final class IrodoriTTSService: SpeechSynthesizer, @unchecked Sendable {
    /// Irodori-TTSのリポジトリ。`infer.py` を調達するために複製する。
    static let repoURL = "https://github.com/Aratako/Irodori-TTS"
    static let repoBranch = "main"

    /// TTS実行環境の `pyproject.toml`。macOSはPyPIのtorch（MPS/CPU）を使う。
    static func pyprojectContent() -> String {
        """
        [project]
        name = "tree-voice-tts-irodori"
        version = "0.1.0"
        requires-python = ">=3.10"
        dependencies = [
            "irodori-tts",
        ]

        [tool.uv.sources]
        irodori-tts = { git = "\(repoURL)", rev = "\(repoBranch)" }
        torch = { index = "pt-cpu", extra = "cpu", marker = "sys_platform == 'linux' or sys_platform == 'win32'" }
        torchaudio = { index = "pt-cpu", extra = "cpu", marker = "sys_platform == 'linux' or sys_platform == 'win32'" }

        [[tool.uv.index]]
        name = "pt-cpu"
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

    /// 合成して出力ファイルに保存する。手動実行用。
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

    /// `infer.py` の引数を組み立てる。`--ref_text` は渡さない。
    static func generateArguments(
        request: TTSRequest, projectDirectory: URL, sourceDirectory: URL, outputDirectory: URL
    ) -> [String] {
        var args = [
            "run", "--project", projectDirectory.path, "--extra", "cpu",
            "python", sourceDirectory.appendingPathComponent("infer.py", isDirectory: false).path,
            "--hf-checkpoint", request.model,
            "--text", request.text,
            "--ref-wav", request.refAudioURL.path,
            "--output-wav",
            outputDirectory.appendingPathComponent("result.wav", isDirectory: false).path,
            "--model-device", "auto"
        ]
        if let caption = request.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            args += ["--caption", caption]
        }
        return args
    }

    /// 実行環境（複製＋.venv）を用意し、`infer.py` の配置先を返す。
    private func ensureEnvironment(uvPath: String) async throws -> URL {
        let toolsDir = paths.ttsIrodoriURL
        try FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)
        let checkoutDir = toolsDir.appendingPathComponent("Irodori-TTS", isDirectory: true)
        let inferPy = checkoutDir.appendingPathComponent("infer.py", isDirectory: false)
        if !FileManager.default.fileExists(atPath: inferPy.path) {
            do {
                _ = try await command(
                    "/usr/bin/git",
                    ["clone", "--depth", "1", "--branch", Self.repoBranch, Self.repoURL, checkoutDir.path],
                    nil)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                if let appError = error as? AppError, appError == .toolMissing("/usr/bin/git") {
                    throw AppError.gitMissing
                }
                throw error
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
