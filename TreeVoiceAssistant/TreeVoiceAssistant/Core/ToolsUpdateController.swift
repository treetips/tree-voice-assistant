import Foundation

/// ツール更新カードの状態。アプリ本体更新とは独立して持つ。
@MainActor
enum ToolsUpdateCard: Equatable {
    case available(ToolsInfo)
    case installing(ToolsUpdateProgress)
    case installFailed(ToolsInfo)
}

/// ツール更新の段階。遅れて届いた進捗で表示を巻き戻さないよう順序を持つ。
enum ToolsUpdatePhase: Int, Sendable, Equatable, Comparable {
    case downloading = 0
    case verifying = 1
    case extracting = 2
    case installing = 3

    static func < (lhs: ToolsUpdatePhase, rhs: ToolsUpdatePhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ツール更新の進捗。全ツールを通した0...1と、現在処理中のツール名を表示する。
struct ToolsUpdateProgress: Sendable, Equatable {
    var phase: ToolsUpdatePhase
    var fraction: Double?
    var label: String
}

/// toolsの初回準備・差分確認・更新実行を管理する。
@Observable
@MainActor
final class ToolsUpdateController {
    var card: ToolsUpdateCard?
    var isInstalling = false
    var isChecking = false
    /// 変換タスクが終了するまでtoolsの置換を始めないためのApp層からの状態。
    var isConversionRunning = false
    var errorDialog: String?

    private let store: ToolsInfoStore
    private let service: ToolsUpdateService

    init(paths: AppPaths = AppPaths(), service: ToolsUpdateService? = nil) {
        self.store = ToolsInfoStore(paths: paths)
        self.service = service ?? ToolsUpdateService(paths: paths)
    }

    /// 不足ツールを準備した後、配布メタデータとローカル記録を比べる。
    /// 取得失敗時はカードを出さず、既存の動的調達へフォールバックする。
    func refreshAvailability() {
        guard card == nil, !isInstalling, !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let info = try await service.fetchToolsInfo()
                let state = store.loadInstalledState()
                // 記録が無い既存環境は版を断定できないため、配布物で一度すべてそろえる。
                let targets = state.isKnown
                    ? Self.missingTools(info: info, paths: store.paths)
                    : info.tools
                if !targets.isEmpty {
                    guard !isConversionRunning else { return }
                    isInstalling = true
                    card = .installing(.init(phase: .downloading, fraction: 0, label: ""))
                    let onProgress: @Sendable (ToolsUpdateProgress) -> Void = { [self] progress in
                        Task { @MainActor in
                            self.applyProgress(progress)
                        }
                    }
                    _ = try await service.installTools(
                        targets: targets, installed: state.installed, onProgress: onProgress)
                    isInstalling = false
                    card = nil
                }
                let installed = store.loadInstalled()
                guard !store.updatesNeeded(info: info, installed: installed).isEmpty else { return }
                card = .available(info)
            } catch {
                isInstalling = false
                if case .installing = card { card = nil }
            }
        }
    }

    /// 差分のあるツールだけを更新する。完了でカードを消し、失敗時は再実行可能にする。
    func install(
        _ info: ToolsInfo,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard !isInstalling, !isConversionRunning else {
            completion(false)
            return
        }
        isInstalling = true
        card = .installing(.init(phase: .downloading, fraction: 0, label: ""))
        let installed = store.loadInstalled()
        Task {
            let onProgress: @Sendable (ToolsUpdateProgress) -> Void = { [self] progress in
                Task { @MainActor in
                    self.applyProgress(progress)
                }
            }
            var succeeded = false
            do {
                _ = try await service.updateTools(
                    info: info, installed: installed, onProgress: onProgress)
                card = nil
                succeeded = true
            } catch {
                card = .installFailed(info)
                errorDialog = error.localizedDescription
            }
            isInstalling = false
            completion(succeeded)
        }
    }

    func retryInstall(completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard case .installFailed(let info) = card else {
            completion(false)
            return
        }
        install(info, completion: completion)
    }

    private func applyProgress(_ progress: ToolsUpdateProgress) {
        guard isInstalling, case .installing(let current) = card,
              current.phase <= progress.phase
        else { return }
        card = .installing(progress)
    }

    private static func missingTools(info: ToolsInfo, paths: AppPaths) -> [ToolMetadata] {
        ToolsUpdateService.missingTools(info: info, paths: paths)
    }
}
