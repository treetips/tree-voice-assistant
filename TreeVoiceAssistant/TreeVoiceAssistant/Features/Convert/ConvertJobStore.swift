import Foundation

/// 音声変換画面の実行状態。App層が所有する共有状態のため、
/// サイドナビ切替でViewが再生成されても進捗・結果が維持される。
@Observable
@MainActor
final class ConvertJobStore {
    var isTranscribing = false
    var isSynthesizing = false
    var isPlaying = false
    /// 直近の実行結果に応じたドロップエリアの枠色に使う。成功=true、失敗=false。
    var lastRunSucceeded: Bool?
    var outputFileURL: URL?
    var resultMessage = ""

    var isRunning: Bool {
        isTranscribing || isSynthesizing || isPlaying
    }
}
