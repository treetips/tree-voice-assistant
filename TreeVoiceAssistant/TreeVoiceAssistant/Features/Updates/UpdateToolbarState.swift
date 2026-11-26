import Foundation

/// ヘッダー右端の更新表示を、アプリとツールの状態から1つに解決した結果。
@MainActor
enum UpdateToolbarState: Equatable {
    case hidden
    case checking
    case available(UpdateAvailability)
    case appInstalling(UpdateInstallProgress)
    case toolsInstalling(ToolsUpdateProgress)
    case readyToRestart
    case appInstallFailed(UpdateInfo)
    case toolsInstallFailed(ToolsInfo)
    case noUpdate
}

/// 更新ボタンから実行できる更新の組み合わせ。
@MainActor
enum UpdateAvailability: Equatable {
    case app(UpdateInfo)
    case tools(ToolsInfo)
    case appAndTools(UpdateInfo, ToolsInfo)

    var labelKey: String {
        switch self {
        case .app: return "nav.appUpdateAvailable"
        case .tools: return "nav.toolsUpdateAvailable"
        case .appAndTools: return "nav.appAndToolsUpdateAvailable"
        }
    }

    var systemImage: String {
        switch self {
        case .app, .appAndTools: return "arrow.down.circle.fill"
        case .tools: return "shippingbox.and.arrow.backward.fill"
        }
    }
}

/// アプリとツールの更新状態を共通の表示・実行計画へ変換する。
@MainActor
enum UpdateToolbarResolver {
    // swiftlint:disable:next cyclomatic_complexity
    static func resolve(
        appCard: UpdateCard?,
        toolsCard: ToolsUpdateCard?,
        isChecking: Bool
    ) -> UpdateToolbarState {
        if case .readyToRestart = appCard { return .readyToRestart }
        if case .installing(let progress) = appCard { return .appInstalling(progress) }
        if case .installing(let progress) = toolsCard { return .toolsInstalling(progress) }
        if case .installFailed(let info) = appCard { return .appInstallFailed(info) }
        if case .installFailed(let info) = toolsCard { return .toolsInstallFailed(info) }
        if isChecking { return .checking }

        switch (appCard, toolsCard) {
        case (.available(let appInfo), .available(let toolsInfo)):
            return .available(.appAndTools(appInfo, toolsInfo))
        case (.available(let appInfo), _):
            return .available(.app(appInfo))
        case (_, .available(let toolsInfo)):
            return .available(.tools(toolsInfo))
        default:
            break
        }
        if case .noUpdate = appCard { return .noUpdate }
        return .hidden
    }

    static func plan(for availability: UpdateAvailability) -> UpdateInstallPlan {
        switch availability {
        case .app(let info): return .app(info)
        case .tools(let info): return .tools(info)
        case .appAndTools(let appInfo, let toolsInfo): return .toolsThenApp(appInfo, toolsInfo)
        }
    }

    /// 失敗済みの更新を再実行するための計画。利用可能な更新も未完了として扱う。
    static func retryPlan(appCard: UpdateCard?, toolsCard: ToolsUpdateCard?) -> UpdateInstallPlan {
        let app: UpdateInfo?
        switch appCard {
        case .installFailed(let info), .available(let info): app = info
        default: app = nil
        }
        let tools: ToolsInfo?
        switch toolsCard {
        case .installFailed(let info), .available(let info): tools = info
        default: tools = nil
        }
        if let app, let tools { return .toolsThenApp(app, tools) }
        if let app { return .app(app) }
        if let tools { return .tools(tools) }
        return .none
    }
}

/// 更新ボタンが実行する計画。両方ある場合はツールを先に完了させる。
@MainActor
enum UpdateInstallPlan: Equatable {
    case none
    case app(UpdateInfo)
    case tools(ToolsInfo)
    case toolsThenApp(UpdateInfo, ToolsInfo)
}
