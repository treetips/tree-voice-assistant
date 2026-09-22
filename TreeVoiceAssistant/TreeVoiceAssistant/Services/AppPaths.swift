import Foundation

/// アプリの各種パスを提供する。
struct AppPaths: Sendable {
    /// テスト用に基準ディレクトリを差し替える。`nil` の場合は実環境を使う。
    var baseURL: URL?

    /// `~/Library/Application Support/tree-voice-assistant`。
    var projectDirectoryURL: URL {
        if let baseURL {
            return baseURL
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/tree-voice-assistant", isDirectory: true)
    }

    /// `~/.config/tree-voice-assistant`。設定ファイル・ユーザー配置資産の基準。
    var configDirectoryURL: URL {
        if baseURL != nil {
            return projectDirectoryURL
                .appendingPathComponent(".config/tree-voice-assistant", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tree-voice-assistant", isDirectory: true)
    }

    /// 設定ファイル `settings.json`。
    var settingsFileURL: URL {
        configDirectoryURL.appendingPathComponent("settings.json", isDirectory: false)
    }

    /// 利用同意の記録 `agreement.json`。
    var agreementFileURL: URL {
        projectDirectoryURL.appendingPathComponent("agreement.json", isDirectory: false)
    }

    /// ユーザー配置の壁紙ディレクトリ。
    var userWallpaperURL: URL {
        configDirectoryURL.appendingPathComponent("wallpaper", isDirectory: true)
    }

    /// ユーザー配置のサウンド基準ディレクトリ。
    var userSoundsURL: URL {
        configDirectoryURL.appendingPathComponent("sounds", isDirectory: true)
    }

    /// `<基準>/logs`。
    var logsURL: URL {
        projectDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    }

    /// `<基準>/tools`。内蔵ツール（uv・TTS環境）の配置先。
    var toolsURL: URL {
        projectDirectoryURL.appendingPathComponent("tools", isDirectory: true)
    }

    /// 内蔵 `uv` の配置先。`<基準>/tools/bin/uv`。
    var bundledUvURL: URL {
        toolsURL.appendingPathComponent("bin/uv", isDirectory: false)
    }

    /// TTS実行環境の配置先。`<基準>/tools/tts`（pyproject＋.venv）。
    var ttsToolsURL: URL {
        toolsURL.appendingPathComponent("tts", isDirectory: true)
    }
}
