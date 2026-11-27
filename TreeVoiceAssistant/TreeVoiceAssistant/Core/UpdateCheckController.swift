import AppKit
import Foundation

/// ヘッダーのアプリ本体更新カードの状態。
@MainActor
enum UpdateCard: Equatable {
    /// 更新あり。カード内の Download ボタンから開始する。
    case available(UpdateInfo)
    case installing(UpdateInstallProgress)
    /// 再起動用の準備が完了。緑色のカードから配置と起動を行う。
    case readyToRestart(URL, UpdateInfo)
    case installFailed(UpdateInfo)
    /// 更新なし。閉じるボタンでカードを非表示化する。
    case noUpdate
}

/// アプリ本体の更新確認・ダウンロード・ステージング・再起動を管理する。
@Observable
@MainActor
final class UpdateCheckController {
    static let noUpdateCardHideSeconds: Int64 = 10

    var isChecking = false
    var isInstalling = false
    var isRestarting = false
    var isCleaningStagedUpdate = false
    var message = ""
    var latestDialog = false
    var errorDialog: String?
    var restartErrorDialog: String?
    /// 変換終了前にアプリを置換・再起動しないためのApp層からの状態。
    var isConversionRunning = false
    /// ヘッダーの更新カード。起動時のサイレント確認と手動確認の結果を反映する。
    var card: UpdateCard?

    var isReadyToRestart: Bool {
        if case .readyToRestart = card { return true }
        return false
    }

    /// メニュー・About画面の更新確認ボタンで共通する実行可否。
    var canCheckForUpdates: Bool {
        !isChecking && !isInstalling && !isRestarting && !isCleaningStagedUpdate && !isReadyToRestart
    }

    private var hideCardTask: Task<Void, Never>?
    private var checkGeneration = 0
    private let updateService = UpdateService()

    private func language() -> String {
        let paths = AppPaths()
        let maxParallel = max(1, ProcessInfo.processInfo.processorCount)
        return (try? SettingsStore(paths: paths).load(maxParallel: maxParallel).settings.language) ?? ""
    }

    private func currentVersion() -> (version: String, build: Int) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
        return (version, build)
    }

    /// 起動時などにダイアログなしで有無だけ確認し、ヘッダーの更新カードに反映する。
    func refreshAvailability() {
        // カードが残っている間に掃除すると、Downloadと削除が競合し得るため初期状態だけを対象にする。
        guard canCheckForUpdates, card == nil else { return }
        checkGeneration += 1
        let generation = checkGeneration
        isCleaningStagedUpdate = true
        Task {
            let service = updateService
            await Task.detached(priority: .utility) {
                service.cleanupStagedUpdate()
            }.value
            isCleaningStagedUpdate = false
            guard generation == checkGeneration else { return }
            let current = currentVersion()
            let result = await service.checkForUpdate(
                url: AppInfo.updateInfoURL,
                currentVersion: current.version,
                currentBuild: current.build
            )
            // 新しい確認・インストールが始まっていた場合は、古い結果で状態を上書きしない。
            guard generation == checkGeneration,
                  !isInstalling, !isRestarting, !isReadyToRestart
            else { return }
            setCard(Self.resolveCard(for: result))
        }
    }

    static func resolveCard(for result: UpdateCheckResult) -> UpdateCard {
        if case .available(let info) = result { return .available(info) }
        return .noUpdate
    }

    /// 手動確認は失敗時カードを変えない。失敗ダイアログと「更新なし」の食い違いを防ぐため。
    static func resolveManualCard(for result: UpdateCheckResult) -> UpdateCard? {
        if case .failed = result { return nil }
        return resolveCard(for: result)
    }

    private func setCard(_ newCard: UpdateCard) {
        hideCardTask?.cancel()
        hideCardTask = nil
        card = newCard
        if case .noUpdate = newCard {
            hideCardTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(Self.noUpdateCardHideSeconds))
                } catch {
                    return
                }
                self?.card = nil
            }
        }
    }

    /// 確認ダイアログを挟まず、そのままダウンロードを始める。
    func startDownload(_ info: UpdateInfo, language: String? = nil) {
        install(info, language: language)
    }

    func dismissCard() {
        hideCardTask?.cancel()
        hideCardTask = nil
        card = nil
    }

    /// About画面とメニューバーの手動確認。更新ありはヘッダーカードで知らせる。
    func checkForUpdate(language: String? = nil) {
        guard canCheckForUpdates else { return }
        checkGeneration += 1
        let generation = checkGeneration
        isChecking = true
        message = ""
        Task {
            let lang = language ?? self.language()
            let current = currentVersion()
            let result = await updateService.checkForUpdate(
                url: AppInfo.updateInfoURL,
                currentVersion: current.version,
                currentBuild: current.build
            )
            guard generation == checkGeneration,
                  !isInstalling, !isRestarting, !isReadyToRestart
            else {
                isChecking = false
                return
            }
            switch result {
            case .latest:
                message = L10n.string("a.latest", language: lang)
                latestDialog = true
            case .available(let info):
                message = String(format: L10n.string("a.availableMsg", language: lang), info.version)
            case .failed(let reason):
                message = "\(L10n.string("a.checkFailed", language: lang)): \(reason)"
                errorDialog = reason
            }
            if let card = Self.resolveManualCard(for: result) {
                setCard(card)
            }
            isChecking = false
        }
    }

    /// ダウンロード・検証・展開を行い、再起動用にアプリをステージングする。
    /// `/Applications` の置換は再起動ボタン押下時まで遅らせる。
    func install(_ info: UpdateInfo, language: String? = nil) {
        guard !isInstalling, !isRestarting, !isCleaningStagedUpdate, !isReadyToRestart else { return }
        isInstalling = true
        hideCardTask?.cancel()
        hideCardTask = nil
        card = .installing(.indeterminate(.downloading))
        let lang = language ?? self.language()
        Task {
            let onProgress: @Sendable (UpdateInstallProgress) -> Void = { [self] progress in
                Task { @MainActor in
                    self.applyProgress(progress)
                }
            }
            do {
                let prepared = try await updateService.downloadAndPrepare(info: info, onProgress: onProgress)
                card = .installing(.indeterminate(.installing))
                let staged = try await Task.detached(priority: .userInitiated) {
                    try UpdateService().stageForRestart(preparedApp: prepared)
                }.value
                card = .readyToRestart(staged, info)
                message = L10n.string("a.restartReadyMsg", language: lang)
            } catch {
                card = .installFailed(info)
                message = "\(L10n.string("a.downloadFailed", language: lang)): \(error.localizedDescription)"
                errorDialog = error.localizedDescription
            }
            isInstalling = false
        }
    }

    /// 緑色の完了カードから、ステージング済みアプリを配置して起動する。
    func restart(language: String? = nil) {
        guard !isRestarting, !isConversionRunning,
              case .readyToRestart(let stagedAppURL, let info) = card
        else { return }
        isRestarting = true
        let lang = language ?? self.language()
        Task {
            var installedAppURL: URL?
            do {
                let destination = UpdateService.installDestination(for: stagedAppURL)
                if stagedAppURL.standardizedFileURL.path != destination.standardizedFileURL.path {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try UpdateService().applyUpdate(preparedApp: stagedAppURL, destination: destination)
                    }.value
                }
                installedAppURL = destination
                card = .readyToRestart(destination, info)
                try await relaunch(appURL: destination)
            } catch {
                isRestarting = false
                if let installedAppURL {
                    // 配置済みなら再ダウンロードさせず、起動だけを再試行できる。
                    card = .readyToRestart(installedAppURL, info)
                } else {
                    card = .installFailed(info)
                }
                let title = L10n.string("a.restartFailed", language: lang)
                message = "\(title): \(error.localizedDescription)"
                restartErrorDialog = error.localizedDescription
                return
            }
            // 終了が実行されなかった場合に、再起動中のまま操作を固めないためのフォールバック。
            try? await Task.sleep(for: .seconds(10))
            isRestarting = false
        }
    }

    func retryInstall(language: String? = nil) {
        guard case .installFailed(let info) = card else { return }
        install(info, language: language)
    }

    private func applyProgress(_ progress: UpdateInstallProgress) {
        guard isInstalling, case .installing(let current) = card,
              current.phase <= progress.phase
        else { return }
        card = .installing(progress)
    }

    /// 同一bundle IDの新インスタンスを開いてから旧プロセスを終了する。
    private func relaunch(appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
    }
}
