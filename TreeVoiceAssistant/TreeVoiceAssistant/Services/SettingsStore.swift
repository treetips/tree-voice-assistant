import Foundation

/// 音声変換画面の設定。`settings.json` の `convert` セクションに対応する。
struct ConvertSettings: Codable, Equatable {
    var whisperModel: String
    var transcriptionText: String
    var outputFolderPath: String?
    var ttsModel: String
    var speechText: String
    var captionText: String

    enum CodingKeys: String, CodingKey {
        case whisperModel
        case transcriptionText
        case outputFolderPath
        case ttsModel
        case speechText
        case captionText
    }

    init(
        whisperModel: String, transcriptionText: String, outputFolderPath: String?,
        ttsModel: String, speechText: String, captionText: String = ""
    ) {
        self.whisperModel = whisperModel
        self.transcriptionText = transcriptionText
        self.outputFolderPath = outputFolderPath
        self.ttsModel = ttsModel
        self.speechText = speechText
        self.captionText = captionText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whisperModel = try container.decode(String.self, forKey: .whisperModel)
        transcriptionText = try container.decode(String.self, forKey: .transcriptionText)
        outputFolderPath = try container.decodeIfPresent(String.self, forKey: .outputFolderPath)
        ttsModel = try container.decode(String.self, forKey: .ttsModel)
        speechText = try container.decode(String.self, forKey: .speechText)
        captionText = try container.decodeIfPresent(String.self, forKey: .captionText) ?? ""
    }

    static func defaults() -> ConvertSettings {
        ConvertSettings(
            whisperModel: WhisperModel.default.rawValue,
            transcriptionText: "",
            outputFolderPath: nil,
            ttsModel: TTSModel.default.rawValue,
            speechText: "",
            captionText: ""
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
    /// 壁紙をランダムにシャッフルするかどうか (checkbox label: ランダム).
    var wallpaperRandom: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var wallpaperShuffle: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var wallpaperShuffleEnabled: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var randomWallpaper: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var shuffleWallpaper: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var shuffleEnabled: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var isRandom: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var isShuffle: Bool = false

    /// シャッフル間隔 (分). 1/5/15/30/60/240/720/1440 のいずれか.
    var wallpaperShuffleInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleMinutes: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperRandomInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var shuffleInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var shuffleMinutes: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleTime: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleIntervalMinutes: Int = 1

    enum CodingKeys: String, CodingKey {
        case showOsNotification, playSound, successSound, errorSound, language
        case appearance, fontSize, wallpaper, wallpaperOpacity, wallpaperBackgroundColor
        case wallpaperRandom, wallpaperShuffle, wallpaperShuffleEnabled, randomWallpaper
        case shuffleWallpaper, shuffleEnabled, isRandom, isShuffle
        case wallpaperShuffleInterval, wallpaperShuffleMinutes, wallpaperRandomInterval
        case shuffleInterval, shuffleMinutes, wallpaperShuffleTime, wallpaperShuffleIntervalMinutes
    }

    init() {
        showOsNotification = false
        playSound = false
        successSound = ""
        errorSound = ""
        language = ""
        appearance = AppearanceMode.auto.rawValue
        fontSize = FontSizeOption.standard.rawValue
        wallpaper = WallpaperSelection.noneName
        wallpaperOpacity = 1.0
        wallpaperBackgroundColor = "#1E1E1E"
        wallpaperRandom = false
        wallpaperShuffle = false
        wallpaperShuffleEnabled = false
        randomWallpaper = false
        shuffleWallpaper = false
        shuffleEnabled = false
        isRandom = false
        isShuffle = false
        wallpaperShuffleInterval = 1
        wallpaperShuffleMinutes = 1
        wallpaperRandomInterval = 1
        shuffleInterval = 1
        shuffleMinutes = 1
        wallpaperShuffleTime = 1
        wallpaperShuffleIntervalMinutes = 1
    }

    static func defaults() -> ScreenSettings {
        ScreenSettings()
    }

    // swiftlint:disable:next function_body_length
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showOsNotification = try container.decodeIfPresent(Bool.self, forKey: .showOsNotification) ?? false
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? false
        successSound = try container.decodeIfPresent(String.self, forKey: .successSound) ?? ""
        errorSound = try container.decodeIfPresent(String.self, forKey: .errorSound) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? AppearanceMode.auto.rawValue
        fontSize = try container.decodeIfPresent(String.self, forKey: .fontSize) ?? FontSizeOption.standard.rawValue
        wallpaper = try container.decodeIfPresent(String.self, forKey: .wallpaper) ?? WallpaperSelection.noneName
        wallpaperOpacity = try container.decodeIfPresent(Double.self, forKey: .wallpaperOpacity) ?? 1.0
        wallpaperBackgroundColor = try container.decodeIfPresent(String.self, forKey: .wallpaperBackgroundColor)
            ?? "#1E1E1E"

        let boolKeys: [CodingKeys] = [
            .wallpaperRandom, .wallpaperShuffle, .wallpaperShuffleEnabled, .randomWallpaper,
            .shuffleWallpaper, .shuffleEnabled, .isRandom, .isShuffle
        ]
        var shuffleBool = false
        var foundBool = false
        for key in boolKeys {
            if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
                shuffleBool = value
                foundBool = true
                break
            }
        }
        if !foundBool { shuffleBool = false }

        let intKeys: [CodingKeys] = [
            .wallpaperShuffleInterval, .wallpaperShuffleMinutes, .wallpaperRandomInterval,
            .shuffleInterval, .shuffleMinutes, .wallpaperShuffleTime, .wallpaperShuffleIntervalMinutes
        ]
        var resolvedInterval = 1
        var foundInt = false
        for key in intKeys {
            if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                resolvedInterval = Swift.min(Swift.max(value, 1), 1440)
                foundInt = true
                break
            }
        }
        if !foundInt { resolvedInterval = 1 }

        wallpaperRandom = shuffleBool
        wallpaperShuffle = shuffleBool
        wallpaperShuffleEnabled = shuffleBool
        randomWallpaper = shuffleBool
        shuffleWallpaper = shuffleBool
        shuffleEnabled = shuffleBool
        isRandom = shuffleBool
        isShuffle = shuffleBool
        wallpaperShuffleInterval = resolvedInterval
        wallpaperShuffleMinutes = resolvedInterval
        wallpaperRandomInterval = resolvedInterval
        shuffleInterval = resolvedInterval
        shuffleMinutes = resolvedInterval
        wallpaperShuffleTime = resolvedInterval
        wallpaperShuffleIntervalMinutes = resolvedInterval
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
