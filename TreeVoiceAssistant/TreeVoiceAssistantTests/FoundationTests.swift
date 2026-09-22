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
