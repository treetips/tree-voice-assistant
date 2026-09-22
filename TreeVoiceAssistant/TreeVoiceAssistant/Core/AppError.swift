import Foundation

/// アプリ共通のエラー。
enum AppError: LocalizedError, Equatable {
    case toolMissing(String)
    case processFailed(executable: String, exitCode: Int32, output: String)
    case fileNotFound(path: String)
    case invalidSettings(reason: String)
    case networkError(reason: String)
    case verificationFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolMissing(let executable):
            return "ツールが見つかりません: \(executable)"
        case .processFailed(let executable, let exitCode, let output):
            return "実行に失敗しました: \(executable) (終了コード \(exitCode))\n\(output)"
        case .fileNotFound(let path):
            return "ファイルが見つかりません: \(path)"
        case .invalidSettings(let reason):
            return "設定が不正です: \(reason)"
        case .networkError(let reason):
            return "通信に失敗しました: \(reason)"
        case .verificationFailed(let reason):
            return "検証に失敗しました: \(reason)"
        case .cancelled:
            return "キャンセルされました"
        }
    }
}
