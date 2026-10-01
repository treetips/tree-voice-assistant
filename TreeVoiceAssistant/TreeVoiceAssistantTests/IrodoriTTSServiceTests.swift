import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("IrodoriTTSService")
struct IrodoriTTSServiceTests {
    func makeService(stub: @escaping RunCommand) throws -> (IrodoriTTSService, AppPaths) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = AppPaths(baseURL: dir)
        let uvPath = paths.bundledUvURL
        try FileManager.default.createDirectory(
            at: uvPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: uvPath.path, contents: Data("x".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uvPath.path)
        return (IrodoriTTSService(paths: paths, command: stub), paths)
    }

    func makeRequest(outputDirectory: URL) -> TTSRequest {
        TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small",
            refAudioURL: URL(fileURLWithPath: "/tmp/ref.wav"),
            refText: "",
            text: "よむ",
            outputDirectory: outputDirectory,
            caption: "落ち着いた声"
        )
    }

    @Test("pyprojectはPython3.11系に固定する")
    func pyprojectPythonPin() {
        let content = IrodoriTTSService.pyprojectContent()
        #expect(content.contains("requires-python = \">=3.10,<3.12\""))
    }

    @Test("pyprojectは正しい節にgitソースを書く")
    func pyprojectSources() {
        let content = IrodoriTTSService.pyprojectContent()
        #expect(!content.contains("[dependency-sources]"))
        guard let range = content.range(of: "[tool.uv.sources]") else {
            Issue.record("missing [tool.uv.sources]")
            return
        }
        #expect(content[range.upperBound...].contains("irodori-tts = { git = "))
    }

    @Test("git cloneの失敗はログ付きで伝える")
    func gitFailureLogged() async throws {
        let (service, _) = try makeService { executable, _, _ in
            if executable == "/usr/bin/git" {
                throw AppError.processFailed(executable: executable, exitCode: 128, output: "net down")
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        do {
            let request = makeRequest(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
            try await service.synthesize(request: request)
            Issue.record("投げられるべき")
        } catch let AppError.synthesisFailed(reason, logPath) {
            #expect(reason.contains("128"))
            #expect(FileManager.default.fileExists(atPath: logPath))
            let body = try String(contentsOfFile: logPath, encoding: .utf8)
            #expect(body.contains("net down"))
        }
    }

    @Test("git不在はgitMissingの理由でログ付きになる")
    func gitMissingLogged() async throws {
        let (service, _) = try makeService { executable, _, _ in
            if executable == "/usr/bin/git" {
                throw AppError.toolMissing(executable)
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        do {
            let request = makeRequest(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
            try await service.synthesize(request: request)
            Issue.record("投げられるべき")
        } catch let AppError.synthesisFailed(reason, logPath) {
            #expect(reason.contains("git"))
            #expect(FileManager.default.fileExists(atPath: logPath))
        }
    }

    @Test("実行開始時に残存を掃除する")
    func sweepsLeftovers() async throws {
        let (service, paths) = try makeService { executable, args, _ in
            if executable == "/usr/bin/git" {
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
            if args.first == "sync" {
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
            throw AppError.processFailed(executable: executable, exitCode: 1, output: "infer down")
        }
        let markerDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tva-sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        let link = markerDir.appendingPathComponent("tree-voice-irodori-sleep", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let leftover = Process()
        leftover.executableURL = link
        leftover.arguments = ["60"]
        try leftover.run()
        #expect(leftover.isRunning)
        do {
            let request = makeRequest(outputDirectory: paths.toolsURL)
            try await service.synthesize(request: request)
            Issue.record("投げられるべき")
        } catch is AppError {
        }
        var waits = 0
        while leftover.isRunning, waits < 100 {
            try await Task.sleep(for: .milliseconds(50))
            waits += 1
        }
        #expect(leftover.isRunning == false)
    }

    @Test("デバイスはinfer.pyの既定に任せる")
    func noDeviceFlag() throws {
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
            caption: "c"
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(!args.contains("--model-device"))
    }

    @Test("精度はinfer.pyの既定に任せる")
    func noPrecisionFlag() throws {
        let ref = URL(fileURLWithPath: "/tmp/ref.wav", isDirectory: false)
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let proj = URL(fileURLWithPath: "/tmp/tts-irodori", isDirectory: true)
        let src = URL(fileURLWithPath: "/tmp/tts-irodori/src", isDirectory: true)
        let request = TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small-Quantized/int8-weight-only",
            refAudioURL: ref,
            refText: "",
            text: "よむ",
            outputDirectory: out,
            caption: "c"
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(!args.contains("--model-precision"))
    }

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
        #expect(args.contains("/tmp/tts-irodori/src/infer.py"))
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
