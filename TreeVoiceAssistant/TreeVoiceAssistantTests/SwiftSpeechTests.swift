import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("SwiftSpeech")
struct SwiftSpeechTests {
    func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func makeService(stub: @escaping RunCommand) throws -> (MLXAudioTTSService, AppPaths) {
        let paths = AppPaths(baseURL: try makeTempDir())
        let uvPath = paths.bundledUvURL
        try FileManager.default.createDirectory(
            at: uvPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: uvPath.path, contents: Data("x".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uvPath.path)
        return (MLXAudioTTSService(paths: paths, command: stub), paths)
    }

    func makeRequest(outputDirectory: URL) -> TTSRequest {
        TTSRequest(
            model: TTSModel.default.mlxAudioModelID,
            refAudioURL: URL(fileURLWithPath: "/tmp/voice.wav"),
            refText: "台本",
            text: "よむ",
            outputDirectory: outputDirectory
        )
    }

    @Test("TTSモデルは外部プロセス版のチェックポイントに対応する")
    func modelRepos() {
        #expect(TTSModel.qwen17B.mlxAudioModelID == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit")
        #expect(TTSModel.qwen06B.mlxAudioModelID == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
        #expect(TTSModel.default == .qwen17B)
    }

    @Test("出力ファイル名はyyyyMMddHHmmss.wav形式")
    func timestampFileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        components.hour = 10
        components.minute = 20
        components.second = 30
        let date = calendar.date(from: components)!
        #expect(MLXAudioTTSService.timestampFileName(date: date) == "20260915102030.wav")
    }

    @Test("pyprojectはmlx-audioを固定する")
    func pyprojectPinsVersion() {
        let content = MLXAudioTTSService.pyprojectContent()
        #expect(content.contains("mlx-audio==\(MLXAudioTTSService.mlxAudioVersion)"))
    }

    @Test("生成引数はシェル版と同一")
    func generateArguments() throws {
        let request = makeRequest(outputDirectory: URL(fileURLWithPath: "/tmp/out"))
        let project = URL(fileURLWithPath: "/tmp/tools/tts", isDirectory: true)
        let product = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
        let args = MLXAudioTTSService.generateArguments(
            request: request, projectDirectory: project, outputDirectory: product)
        #expect(args.contains("mlx_audio.tts.generate"))
        #expect(args.contains("--model"))
        #expect(args.contains(request.model))
        #expect(args.contains("--ref_audio"))
        #expect(args.contains("--ref_text"))
        #expect(args.contains("--text"))
        #expect(args.contains("--file_prefix"))
        #expect(args.contains("--audio_format"))
        #expect(args.contains("--output"))
        #expect(args.contains("--verbose"))
    }

    @Test("合成は生成物を改名して出力する")
    @MainActor
    func synthesisMovesProduct() async throws {
        let stub: RunCommand = { _, args, _ in
            if args == ["sync"] {
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
            guard let index = args.firstIndex(of: "--output"),
                  args.indices.contains(index + 1)
            else {
                throw AppError.processFailed(executable: "uv", exitCode: 1, output: "no output dir")
            }
            let url = URL(fileURLWithPath: args[index + 1], isDirectory: true)
                .appendingPathComponent("result_001.wav", isDirectory: false)
            try silentWavData().write(to: url, options: .atomic)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let (service, _) = try makeService(stub: stub)
        let outDir = try makeTempDir()
        let url = try await service.synthesize(request: makeRequest(outputDirectory: outDir))
        #expect(url.deletingLastPathComponent() == outDir)
        #expect(url.pathExtension == "wav")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("生成物が無ければ失敗する")
    @MainActor
    func synthesisWithoutProductFails() async throws {
        let stub: RunCommand = { _, _, _ in
            ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let (service, _) = try makeService(stub: stub)
        await #expect(throws: AppError.self) {
            try await service.synthesize(request: self.makeRequest(outputDirectory: try self.makeTempDir()))
        }
    }

    @Test("uvバイナリの所在を解決する")
    func findUvBinary() throws {
        let root = try makeTempDir()
        #expect(UVInstaller.findUvBinary(under: root) == nil)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let uvPath = nested.appendingPathComponent("uv", isDirectory: false)
        FileManager.default.createFile(atPath: uvPath.path, contents: Data("x".utf8))
        #expect(
            UVInstaller.findUvBinary(under: root)?.resolvingSymlinksInPath()
                == uvPath.resolvingSymlinksInPath())
    }

    @Test("uv取得先は公式リリースを指す")
    func uvDownloadURL() {
        let url = UVInstaller.downloadURL().absoluteString
        #expect(url.contains("github.com/astral-sh/uv/releases/download/"))
        #expect(url.contains(UVInstaller.uvVersion))
        #expect(url.hasSuffix(".tar.gz"))
    }
}
