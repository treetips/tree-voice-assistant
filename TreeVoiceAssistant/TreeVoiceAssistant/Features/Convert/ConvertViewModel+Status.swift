import AVFoundation
import Foundation

extension ConvertViewModel {
    /// Irodori-TTSを選択中か否か。
    var isIrodoriSelected: Bool {
        TTSModel(rawValue: ttsModel)?.isIrodori ?? false
    }

    /// 選択中モデルの取得状態を更新する。
    func refreshModelCache() {
        let whisper = WhisperModel(rawValue: whisperModel) ?? WhisperModel.default
        whisperCached = cacheChecker.isWhisperCached(whisper.argmaxModelID)
        let selected = TTSModel(rawValue: ttsModel) ?? TTSModel.default
        if selected.isIrodori {
            ttsCached = cacheChecker.isIrodoriReady(checkpoint: selected.irodoriHFCheckpoint ?? "")
        } else {
            ttsCached = cacheChecker.isHFCached(repo: selected.mlxAudioModelID)
        }
    }

    func notifyFinished() async {
        if let player = await notifier.finish(
            allSuccess: jobStore.lastRunSucceeded ?? false,
            language: currentLanguage()
        ) {
            audioPlayer = player
            player.play()
        }
    }

    func currentLanguage() -> String {
        cachedLanguage
    }

    func refreshLanguage() {
        cachedLanguage =
            (try? store.load(maxParallel: ProcessInfo.processInfo.processorCount).settings.language) ?? ""
    }

    func msg(_ key: String) -> String {
        L10n.string(key, language: currentLanguage())
    }

    /// 実行段階の表示文。準備中は取得中、実行中は指定の文言。
    func stageText(_ stage: EngineStage, runningKey: String) -> String {
        switch stage {
        case .preparingModel: return msg("v.stage.downloading")
        case .running: return msg(runningKey)
        case .idle: return ""
        }
    }
}
