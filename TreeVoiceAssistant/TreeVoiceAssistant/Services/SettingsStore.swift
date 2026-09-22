import Foundation

/// 音声変換画面の設定。`settings.json` の `convert` セクションに対応する。
struct ConvertSettings: Codable, Equatable {
    var whisperModel: String
    var transcriptionText: String
    var outputFolderPath: String?
    var ttsModel: String
    var speechText: String

    static func defaults() -> ConvertSettings {
        ConvertSettings(
            whisperModel: WhisperModel.default.rawValue,
            transcriptionText: "",
            outputFolderPath: nil,
            ttsModel: TTSModel.default.rawValue,
            speechText: ""
        )
    }
}

/// 設定画面の設定。`settings.json` の `settings` セクションに対応する。
struct ScreenSettings: Codable, Equatable {
    var showOsNotification: Bool
    var playSound: Bool
    var successSound: String
    var errorSound: String
    var language: String
    var appearance: String
    var fontSize: String
    var wallpaper: String
    var wallpaperOpacity: Double
    var wallpaperBackgroundColor: String

    static func defaults() -> ScreenSettings {
        ScreenSettings(
            showOsNotification: false,
            playSound: false,
            successSound: "",
            errorSound: "",
            language: "",
            appearance: AppearanceMode.auto.rawValue,
            fontSize: FontSizeOption.standard.rawValue,
            wallpaper: WallpaperSelection.noneName,
            wallpaperOpacity: 1.0,
            wallpaperBackgroundColor: "#1E1E1E"
        )
    }
}

struct AppSettingsFile: Codable, Equatable {
    var settings: ScreenSettings
    var convert: ConvertSettings
}

/// `settings.json` の読み書き。書き込みはロックで直列化する。
final class SettingsStore: Sendable {
    let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    convenience init(paths: AppPaths) {
        self.init(fileURL: paths.settingsFileURL)
    }

    /// 読み込む。無い・壊れている場合は初期値を保存して返す。
    func load(maxParallel: Int) throws -> AppSettingsFile {
        lock.lock()
        defer { lock.unlock() }
        _ = maxParallel
        let defaults = AppSettingsFile(
            settings: .defaults(),
            convert: .defaults()
        )
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try writeLocked(defaults)
            return defaults
        }
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(AppSettingsFile.self, from: data)
        else {
            try writeLocked(defaults)
            return defaults
        }
        return decoded
    }

    func save(_ file: AppSettingsFile) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeLocked(file)
    }

    private func writeLocked(_ file: AppSettingsFile) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 背景色テキスト入力の検証。`#RRGGBB` または `#AARRGGBB` のみ有効。
    nonisolated static func isValidColor(_ hex: String) -> Bool {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8 else { return false }
        return UInt64(value, radix: 16) != nil
    }
}
