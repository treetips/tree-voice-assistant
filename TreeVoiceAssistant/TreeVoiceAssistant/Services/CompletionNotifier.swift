import AVFoundation
import Foundation

/// 変換完了時の通知・サウンド再生。設定に従い、無効なら何もしない。
struct CompletionNotifier: Sendable {
    let store: SettingsStore
    let notificationService: NotificationService
    let soundService: SoundService
    let maxParallel: Int

    init(paths: AppPaths = AppPaths(), notificationService: NotificationService = NotificationService()) {
        self.store = SettingsStore(paths: paths)
        self.notificationService = notificationService
        self.soundService = SoundService(paths: paths)
        self.maxParallel = max(1, ProcessInfo.processInfo.processorCount)
    }

    init(
        store: SettingsStore,
        notificationService: NotificationService = NotificationService(),
        soundService: SoundService? = nil
    ) {
        self.store = store
        self.notificationService = notificationService
        self.soundService = soundService ?? SoundService()
        self.maxParallel = max(1, ProcessInfo.processInfo.processorCount)
    }

    /// 完了を通知する。再生すべきプレイヤーがあれば返す。
    /// 呼び出し側が保持・再生すること（保持しないと再生前に破棄される）。
    func finish(allSuccess: Bool, language: String) async -> AVAudioPlayer? {
        let settings: ScreenSettings
        do {
            settings = try store.load(maxParallel: maxParallel).settings
        } catch {
            return nil
        }
        if settings.showOsNotification {
            let body = L10n.string(allSuccess ? "notify.success" : "notify.failure", language: language)
            await notificationService.notify(body: body)
        }
        if settings.playSound {
            let name = allSuccess ? settings.successSound : settings.errorSound
            let options = soundService.listSounds(success: allSuccess)
            let resolved = soundService.resolveSelected(name, options: options)
            if let option = options.first(where: { $0.name == resolved }),
               let player = soundService.makePlayer(for: option) {
                return player
            }
        }
        return nil
    }
}
