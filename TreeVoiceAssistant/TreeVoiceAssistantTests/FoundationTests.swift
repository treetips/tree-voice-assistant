import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("AppPaths")
struct AppPathsTests {
    @Test("テスト基準では分離される")
    func testBaseIsIsolated() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(baseURL: base)
        #expect(paths.settingsFileURL.path.hasSuffix(".config/tree-voice-assistant/settings.json"))
        #expect(paths.userSoundsURL.path.contains("tree-voice-assistant"))
        #expect(paths.userWallpaperURL.path.contains("tree-voice-assistant"))
        #expect(paths.modelsURL == base.appendingPathComponent("models", isDirectory: true))
        #expect(paths.hfHubURL == base.appendingPathComponent("models/hf-hub", isDirectory: true))
    }

    @Test("実環境ではtree-voice-assistant配下を指す")
    func productionPaths() {
        let paths = AppPaths()
        #expect(paths.settingsFileURL.path.contains("tree-voice-assistant"))
        #expect(!paths.settingsFileURL.path.contains("tree-image-optimizer"))
    }
}

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("成功時は出力を返す")
    func success() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run("/bin/echo", args: ["hello"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
    }

    @Test("非ゼロ終了は失敗になる")
    func failure() async {
        let runner = ProcessRunner()
        await #expect(throws: AppError.self) {
            try await runner.run("/usr/bin/false")
        }
    }

    @Test("存在しない実行ファイルは欠落になる")
    func missing() async {
        let runner = ProcessRunner()
        do {
            try await runner.run("/nonexistent-tool-xyz")
            Issue.record("失敗するはず")
        } catch let error as AppError {
            #expect(error == .toolMissing("/nonexistent-tool-xyz"))
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }

    @Test("環境変数を子プロセスに渡す")
    func environment() async throws {
        let runner = ProcessRunner()
        let result = try await runner.runCancellable(
            "/bin/sh", args: ["-c", "echo $TVA_TEST_ENV_PING"], environment: ["TVA_TEST_ENV_PING": "pong"])
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "pong")
    }

    @Test("残存プロセスを掃除する")
    func terminatesLeftovers() throws {
        let markerDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tva-leftover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        let link = markerDir.appendingPathComponent("sleep", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let process = Process()
        process.executableURL = link
        process.arguments = ["60"]
        try process.run()
        #expect(process.isRunning)
        ProcessRunner.terminateLeftovers(matching: [markerDir.lastPathComponent])
        var waits = 0
        while process.isRunning, waits < 100 {
            Thread.sleep(forTimeInterval: 0.05)
            waits += 1
        }
        #expect(process.isRunning == false)
    }
}

@Suite("L10n")
struct L10nTests {
    @Test("日本語と英語を解決する")
    func resolves() {
        #expect(L10n.string("nav.convert", language: "ja-JP") == "音声変換")
        #expect(L10n.string("nav.convert", language: "en-US") == "Voice Convert")
    }

    @Test("書式付き文字列")
    func format() {
        let ja = String(format: L10n.string("sample.prefix", language: "ja"), "a.mp3")
        #expect(ja == "（サンプル）a.mp3")
    }
}

@Suite("AppTheme")
struct AppThemeTests {
    @Test("倍率マッピング")
    func scales() {
        #expect(AppTheme.fontScale(for: "small") == 0.88)
        #expect(AppTheme.fontScale(for: "standard") == 1.0)
        #expect(AppTheme.fontScale(for: "large") == 1.35)
        #expect(AppTheme.fontScale(for: "unknown") == 1.0)
    }
}

@Suite("SaveCoalescer")
struct SaveCoalescerTests {
    @Test("連続要求は1回にまとまる")
    @MainActor
    func coalesces() async throws {
        let saver = SaveCoalescer()
        var count = 0
        saver.schedule { count += 1 }
        saver.schedule { count += 1 }
        saver.schedule(delay: .milliseconds(50)) { count += 1 }
        var waits = 0
        while count == 0, waits < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        #expect(count == 1)
    }

    @Test("flushは即時実行する")
    @MainActor
    func flushRunsNow() {
        let saver = SaveCoalescer()
        var count = 0
        saver.schedule(delay: .seconds(60)) { count += 1 }
        saver.flush { count += 1 }
        #expect(count == 1)
    }
}
