import Foundation
import Testing

// swiftlint:disable file_length

@testable import TreeVoiceAssistant

@Suite("UpdateLogic")
struct UpdateLogicTests { // swiftlint:disable:this type_body_length
    private func makeTempDir() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAppInfo(version: String = "0.1.0") -> UpdateInfo {
        UpdateInfo(
            version: version,
            build: 2,
            url: "https://example.com/a.zip",
            sha256: String(repeating: "a", count: 64)
        )
    }

    private func makeToolsInfo() -> ToolsInfo {
        ToolsInfo(schemaVersion: 1, tools: [
            ToolMetadata(
                name: "uv",
                version: "0.12.9",
                url: "https://example.com/uv.zip",
                sha256: String(repeating: "a", count: 64),
                required: true
            ),
            ToolMetadata(
                name: "tts",
                version: "0.5.1",
                url: "https://example.com/tts.zip",
                sha256: String(repeating: "b", count: 64),
                required: true
            ),
            ToolMetadata(
                name: "tts-irodori",
                version: "revision",
                url: "https://example.com/irodori.zip",
                sha256: String(repeating: "c", count: 64),
                required: true
            )
        ])
    }

    @Test("アップデート比較")
    func updateComparison() {
        let info = UpdateInfo(version: "0.0.1", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(info.isNewerThan(currentVersion: "0.0.0", currentBuild: 99))
        #expect(info.isNewerThan(currentVersion: "0.0.1", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.0.1", currentBuild: 2))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.0.1", currentBuild: 3))
    }

    @Test("ダウンロード進捗は受信バイト数を0〜1に丸める")
    func updateDownloadProgress() {
        #expect(UpdateInstallProgress.downloadFraction(received: 0, total: 100) == 0)
        #expect(UpdateInstallProgress.downloadFraction(received: 50, total: 100) == 0.5)
        #expect(UpdateInstallProgress.downloadFraction(received: 120, total: 100) == 1)
        #expect(UpdateInstallProgress.downloadFraction(received: 10, total: -1) == nil)
        let progress = UpdateInstallProgress.downloading(received: 25, total: 100)
        #expect(progress.phase == .downloading)
        #expect(progress.fraction == 0.25)
        #expect(UpdateInstallProgress.indeterminate(.verifying).fraction == nil)
    }

    @Test("SHA-256はファイルを逐次計算する")
    func sha256() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.bin", isDirectory: false)
        try Data("hello".utf8).write(to: file)
        #expect(
            try UpdateService.sha256(of: file)
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    @Test("インストール先は/Applications配下")
    func installDestination() {
        let prepared = URL(fileURLWithPath: "/tmp/TreeVoiceAssistant.app", isDirectory: false)
        #expect(UpdateService.installDestination(for: prepared).path == "/Applications/TreeVoiceAssistant.app")
    }

    @Test("再起動用アプリはApplicationsへ配置せずステージングする")
    func stageUpdateForRestart() throws {
        let fileManager = FileManager.default
        let base = try makeTempDir()
        defer { try? fileManager.removeItem(at: base) }
        let prepared = base.appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        try fileManager.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: prepared.appendingPathComponent("Contents/Info.plist"))

        let paths = AppPaths(baseURL: base)
        let staged = try UpdateService().stageForRestart(preparedApp: prepared, paths: paths)
        #expect(
            staged.standardizedFileURL.path
                == paths.updatesDirectoryURL.appendingPathComponent("TreeVoiceAssistant.app").standardizedFileURL.path
        )
        #expect(fileManager.fileExists(atPath: staged.appendingPathComponent("Contents/Info.plist").path))
        #expect(!fileManager.fileExists(atPath: prepared.path))
    }

    @Test("起動時にステージング済みアプリを掃除する")
    func cleanupStagedUpdate() throws {
        let fileManager = FileManager.default
        let base = try makeTempDir()
        defer { try? fileManager.removeItem(at: base) }
        let prepared = base.appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        try fileManager.createDirectory(at: prepared, withIntermediateDirectories: true)
        let paths = AppPaths(baseURL: base)
        let service = UpdateService()
        _ = try service.stageForRestart(preparedApp: prepared, paths: paths)

        service.cleanupStagedUpdate(paths: paths)
        #expect(!fileManager.fileExists(atPath: paths.updatesDirectoryURL.path))
    }

    @Test("適用は展開済みアプリを複写する")
    func applyUpdateCopies() throws {
        let fileManager = FileManager.default
        let base = try makeTempDir()
        defer { try? fileManager.removeItem(at: base) }
        let prepared = base.appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        try fileManager.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: prepared.appendingPathComponent("Contents/Info.plist").path, contents: Data("x".utf8))
        let destination = base.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        let service = UpdateService()
        let installed = try service.applyUpdate(preparedApp: prepared, destination: destination)
        #expect(installed == destination)
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path))
    }

    @Test("適用は存在しない展開元で失敗する")
    func applyUpdateFailsWithoutSource() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = UpdateService()
        #expect(throws: AppError.self) {
            try service.applyUpdate(
                preparedApp: base.appendingPathComponent("Missing.app", isDirectory: false),
                destination: base.appendingPathComponent("Dest.app", isDirectory: false))
        }
    }

    @Test("配置失敗時は部分コピーを削除し旧アプリを復元する")
    func applyUpdateRestoresPreviousAppOnCopyFailure() throws {
        let fileManager = FileManager.default
        let base = try makeTempDir()
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
            try? fileManager.removeItem(at: base)
        }
        let prepared = base.appendingPathComponent("Prepared.app", isDirectory: false)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: prepared.path) }
        let destination = base.appendingPathComponent("Installed.app", isDirectory: false)
        try fileManager.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: prepared.appendingPathComponent("Contents/New"))
        try fileManager.createDirectory(
            at: destination.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("Contents/Old"))
        try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: prepared.path)

        #expect(throws: (any Error).self) {
            try UpdateService().applyUpdate(preparedApp: prepared, destination: destination)
        }
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/Old").path))
        #expect(!fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/New").path))
    }

    @Test("更新確認結果はヘッダーの更新カード状態に解決する")
    @MainActor
    func resolveCard() {
        let info = makeAppInfo()
        #expect(UpdateCheckController.resolveCard(for: .available(info)) == .available(info))
        #expect(UpdateCheckController.resolveCard(for: .latest) == .noUpdate)
        #expect(UpdateCheckController.resolveCard(for: .failed("offline")) == .noUpdate)
    }

    @Test("手動確認結果は確認失敗時を除きヘッダーの更新カード状態に解決する")
    @MainActor
    func resolveManualCard() {
        let info = makeAppInfo()
        #expect(UpdateCheckController.resolveManualCard(for: .available(info)) == .available(info))
        #expect(UpdateCheckController.resolveManualCard(for: .latest) == .noUpdate)
        #expect(UpdateCheckController.resolveManualCard(for: .failed("offline")) == nil)
    }

    @Test("再起動待ちは更新確認を上書きしない")
    @MainActor
    func restartReadyBlocksUpdateCheck() {
        let controller = UpdateCheckController()
        let destination = URL(fileURLWithPath: "/Applications/TreeVoiceAssistant.app")
        let info = makeAppInfo()
        controller.card = .readyToRestart(destination, info)
        controller.checkForUpdate(language: "ja")
        #expect(controller.isReadyToRestart)
        #expect(!controller.isChecking)
        #expect(controller.card == .readyToRestart(destination, info))
    }

    @Test("ステージング掃除中は更新確認とダウンロードを開始しない")
    @MainActor
    func stagedUpdateCleanupBlocksUpdateOperations() {
        let controller = UpdateCheckController()
        let info = makeAppInfo()
        controller.isCleaningStagedUpdate = true
        controller.checkForUpdate(language: "ja")
        controller.startDownload(info, language: "ja")
        #expect(!controller.canCheckForUpdates)
        #expect(!controller.isChecking)
        #expect(!controller.isInstalling)
        #expect(controller.card == nil)
    }

    @Test("ヘッダーはアプリ・ツール・両方の更新を1つの状態に解決する")
    @MainActor
    func toolbarResolvesAvailability() {
        let app = makeAppInfo()
        let tools = makeToolsInfo()
        #expect(
            UpdateToolbarResolver.resolve(appCard: .available(app), toolsCard: nil, isChecking: false)
                == .available(.app(app))
        )
        #expect(
            UpdateToolbarResolver.resolve(appCard: nil, toolsCard: .available(tools), isChecking: false)
                == .available(.tools(tools))
        )
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .available(app), toolsCard: .available(tools), isChecking: false
            ) == .available(.appAndTools(app, tools))
        )
        #expect(UpdateToolbarResolver.resolve(appCard: nil, toolsCard: nil, isChecking: true) == .checking)
        #expect(UpdateToolbarResolver.resolve(appCard: .noUpdate, toolsCard: nil, isChecking: false) == .noUpdate)
        #expect(UpdateToolbarResolver.resolve(appCard: nil, toolsCard: nil, isChecking: false) == .hidden)
    }

    @Test("両方の更新はツールを先に実行する")
    @MainActor
    func toolbarPlansToolsBeforeApp() {
        let app = makeAppInfo()
        let tools = makeToolsInfo()
        #expect(UpdateToolbarResolver.plan(for: .app(app)) == .app(app))
        #expect(UpdateToolbarResolver.plan(for: .tools(tools)) == .tools(tools))
        #expect(UpdateToolbarResolver.plan(for: .appAndTools(app, tools)) == .toolsThenApp(app, tools))
        #expect(
            UpdateToolbarResolver.retryPlan(
                appCard: .installFailed(app), toolsCard: .installFailed(tools)
            ) == .toolsThenApp(app, tools)
        )
    }

    @Test("toolsのインストール済み記録を保存・読込する")
    func toolsInstalledStateRoundTrip() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ToolsInfoStore(paths: AppPaths(baseURL: base))
        let installed = InstalledTools(tools: ["uv": "0.12.9", "tts": "0.5.1"])
        try store.saveInstalled(installed)
        #expect(store.loadInstalled() == installed)
    }

    @Test("記録が無い既存環境は版不明として全ツール再準備の対象にする")
    func toolsInstalledStateFallback() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ToolsInfoStore(paths: AppPaths(baseURL: base))
        let state = store.loadInstalledState()
        #expect(state.installed.tools.isEmpty)
        #expect(!state.isKnown)
        #expect(store.updatesNeeded(info: makeToolsInfo(), installed: state.installed).count == 3)
    }

    @Test("壊れたインストール済み記録も版不明として扱う")
    func corruptInstalledStateIsUnknown() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ToolsInfoStore(paths: AppPaths(baseURL: base))
        try FileManager.default.createDirectory(
            at: store.installedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: store.installedFileURL)
        let state = store.loadInstalledState()
        #expect(state.installed.tools.isEmpty)
        #expect(!state.isKnown)
    }

    @Test("toolsはローカル記録と異なる項目だけを更新対象にする")
    func toolsUpdatesNeeded() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ToolsInfoStore(paths: AppPaths(baseURL: base))
        let info = makeToolsInfo()
        let installed = InstalledTools(tools: ["uv": "0.12.9", "tts": "old", "tts-irodori": "revision"])
        #expect(store.updatesNeeded(info: info, installed: installed).map(\.name) == ["tts"])
    }

    @Test("toolsの不足判定は実体を見る")
    func missingToolsChecksPayloads() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let paths = AppPaths(baseURL: base)
        let info = makeToolsInfo()
        #expect(ToolsUpdateService.missingTools(info: info, paths: paths).count == 3)

        let uvURL = paths.bundledUvURL
        try FileManager.default.createDirectory(
            at: uvURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("uv".utf8).write(to: uvURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uvURL.path)
        let tts = paths.ttsToolsURL.appendingPathComponent("pyproject.toml")
        try FileManager.default.createDirectory(
            at: tts.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("project".utf8).write(to: tts)
        let infer = paths.ttsIrodoriURL.appendingPathComponent("Irodori-TTS/infer.py")
        try FileManager.default.createDirectory(
            at: infer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("infer".utf8).write(to: infer)
        #expect(
            ToolsUpdateService.missingTools(info: info, paths: paths).map(\.name)
                == ["tts", "tts-irodori"]
        )

        try Data("tts-lock".utf8).write(to: paths.ttsToolsURL.appendingPathComponent("uv.lock"))
        try Data("irodori-project".utf8).write(
            to: paths.ttsIrodoriURL.appendingPathComponent("pyproject.toml"))
        try Data("irodori-lock".utf8).write(
            to: paths.ttsIrodoriURL.appendingPathComponent("uv.lock"))
        #expect(ToolsUpdateService.missingTools(info: info, paths: paths).isEmpty)
    }

    @Test("変換中はtools更新を開始しない")
    @MainActor
    func toolsUpdateBlocksDuringConversion() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let controller = ToolsUpdateController(paths: AppPaths(baseURL: base))
        let info = makeToolsInfo()
        controller.card = .available(info)
        controller.isConversionRunning = true
        var completed = true
        controller.install(info) { completed = $0 }
        #expect(!completed)
        #expect(!controller.isInstalling)
        #expect(controller.card == .available(info))
    }

    @Test("ツール更新通知は実行中だけ閉じられない")
    @MainActor
    func toolsUpdateCardDismissPreservesInstallProgress() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let controller = ToolsUpdateController(paths: AppPaths(baseURL: base))
        let info = makeToolsInfo()

        controller.card = .available(info)
        controller.dismissCard()
        #expect(controller.card == nil)

        let progress = ToolsUpdateProgress(phase: .downloading, fraction: 0.5, label: "uv")
        controller.card = .installing(progress)
        controller.isInstalling = true
        controller.dismissCard()
        #expect(controller.card == .installing(progress))
    }

    @Test("変換中はアプリの再起動を開始しない")
    @MainActor
    func restartBlocksDuringConversion() {
        let controller = UpdateCheckController()
        let staged = URL(fileURLWithPath: "/tmp/TreeVoiceAssistant.app")
        let info = makeAppInfo()
        controller.card = .readyToRestart(staged, info)
        controller.isConversionRunning = true
        controller.restart(language: "ja")
        #expect(!controller.isRestarting)
        #expect(controller.card == .readyToRestart(staged, info))
    }

    @Test("tools配布先はアプリ本体とは別の事前リリースを指す")
    func toolsInfoURLIsSeparate() {
        #expect(
            ToolsInfoStore.toolsInfoURL.absoluteString
                == "https://github.com/treetips/tree-voice-assistant/releases/download/tools-latest/tools-info.json"
        )
        #expect(ToolsDistribution.knownNames == Set(["uv", "tts", "tts-irodori"]))
    }

    @Test("更新なしカードの文言")
    func noUpdateCardText() {
        #expect(L10n.string("nav.updateNone", language: "ja") == "アップデートは有りません")
        #expect(L10n.string("nav.updateNone", language: "en") == "No update available")
    }

    @Test("Rex風更新フローの文言")
    func rexUpdateText() {
        #expect(L10n.string("nav.appUpdateAvailable", language: "ja") == "アプリの更新があります")
        #expect(L10n.string("nav.toolsUpdateAvailable", language: "en") == "Tools update available")
        #expect(L10n.string("nav.updateReady", language: "ja") == "アップデート完了")
        #expect(L10n.string("nav.restart", language: "en") == "Restart app")
        #expect(L10n.string("a.restartReadyMsg", language: "ja") == "再起動するとアップデートが反映されます。")
    }

    @Test("Rex風ステータスピルの文言")
    func rexStatusPillText() {
        #expect(L10n.string("a.close", language: "ja") == "閉じる")
        #expect(L10n.string("a.close", language: "en") == "Close")
        #expect(L10n.string("nav.download", language: "ja") == "ダウンロード")
        #expect(L10n.string("nav.download", language: "en") == "Download")
        #expect(L10n.string("a.install", language: "ja") == "インストール")
        #expect(L10n.string("a.install", language: "en") == "Install")
    }

    @Test("ダウンロード進捗の書式")
    func downloadProgressFormatted() {
        let japanese = String(format: L10n.string("nav.downloadingPercent", language: "ja"), 42)
        #expect(japanese == "ダウンロード中... 42%")
        let english = String(format: L10n.string("nav.downloadingPercent", language: "en"), 42)
        #expect(english == "Downloading... 42%")
    }
}
