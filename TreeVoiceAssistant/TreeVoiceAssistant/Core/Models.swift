import Foundation

// MARK: - Sidebar

/// 左サイドナビの選択肢。
enum SidebarSelection: String, Hashable, Identifiable, CaseIterable {
    case convert
    case settings
    case about

    var id: String { rawValue }
}

// MARK: - Voice Convert

/// Whisperの文字起こしモデル。
enum WhisperModel: String, Hashable, Identifiable, CaseIterable {
    case largeV3TurboCompressed = "Large v3 Turbo (compressed)"
    case largeV3Turbo = "Large v3 Turbo"
    case baseMultilingual = "Base (multilingual)"
    case baseEnglishOnly = "Base (English-only)"
    case smallMultilingual = "Small (Multilingual)"
    case smallEnglishOnly = "Small (English-only)"
    case tinyMultilingual = "Tiny (Multilingual)"
    case tinyEnglishOnly = "Tiny (English-only)"

    var id: String { rawValue }

    static var `default`: WhisperModel { .largeV3TurboCompressed }

    /// argmaxのモデルID（`WhisperKitConfig(model:)` に渡す）。
    var argmaxModelID: String {
        switch self {
        case .largeV3TurboCompressed: return "large-v3-v20240930_626MB"
        case .largeV3Turbo: return "large-v3-v20240930_turbo"
        case .baseMultilingual: return "base"
        case .baseEnglishOnly: return "base.en"
        case .smallMultilingual: return "small"
        case .smallEnglishOnly: return "small.en"
        case .tinyMultilingual: return "tiny"
        case .tinyEnglishOnly: return "tiny.en"
        }
    }
}

/// TTSの音声合成モデル。
enum TTSModel: String, Hashable, Identifiable, CaseIterable {
    case qwen17B = "Qwen3-TTS-12Hz-1.7B"
    case qwen06B = "Qwen3-TTS-12Hz-0.6B"
    case irodoriV4Large = "Irodori-TTS-v4-Large"
    case irodoriV4LargeQuantized = "Irodori-TTS-v4-Large-Quantized"
    case irodoriV41SmallMF = "Irodori-TTS-v4.1-Small-MF"
    case irodoriV41Small = "Irodori-TTS-v4.1-Small"
    case irodoriV41SmallQuantized = "Irodori-TTS-v4.1-Small-Quantized"

    var id: String { rawValue }

    static var `default`: TTSModel { .qwen17B }

    /// 外部プロセス版に渡すモデルID。シェル版実績の checkpoint に合わせる。
    var mlxAudioModelID: String {
        switch self {
        case .qwen17B: return "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit"
        case .qwen06B: return "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
        case .irodoriV4Large, .irodoriV4LargeQuantized, .irodoriV41SmallMF, .irodoriV41Small,
            .irodoriV41SmallQuantized:
            return ""
        }
    }

    /// Irodori-TTSか否か。
    var isIrodori: Bool {
        switch self {
        case .irodoriV4Large, .irodoriV4LargeQuantized, .irodoriV41SmallMF, .irodoriV41Small,
            .irodoriV41SmallQuantized:
            return true
        case .qwen17B, .qwen06B: return false
        }
    }

    /// Irodori-TTSに渡すHugging Faceチェックポイント。Qwenの場合はnil。
    /// 量子化版は `リポジトリ/方式` 形式で、既定のint8-weight-onlyを使う。
    var irodoriHFCheckpoint: String? {        switch self {
        case .irodoriV4Large: return "Aratako/Irodori-TTS-v4-Large"
        case .irodoriV4LargeQuantized: return "Aratako/Irodori-TTS-v4-Large-Quantized/int8-weight-only"
        case .irodoriV41SmallMF: return "Aratako/Irodori-TTS-v4.1-Small-MF"
        case .irodoriV41Small: return "Aratako/Irodori-TTS-v4.1-Small"
        case .irodoriV41SmallQuantized:
            return "Aratako/Irodori-TTS-v4.1-Small-Quantized/int8-weight-only"
        case .qwen17B, .qwen06B: return nil
        }
    }
}

/// 選択中モデルに対応する合成用パラメータ。
struct TTSModelResolution: Sendable, Equatable {
    var modelID: String
    var caption: String?
}

/// 選択中モデルに対応する合成用モデルIDとcaptionを解決する。Qwenはcaptionなし。
func resolveTTSModel(selected: TTSModel, captionText: String) -> TTSModelResolution {
    if selected.isIrodori {
        return TTSModelResolution(
            modelID: selected.irodoriHFCheckpoint ?? "Aratako/Irodori-TTS-v4.1-Small",
            caption: captionText
        )
    }
    return TTSModelResolution(modelID: selected.mlxAudioModelID, caption: nil)
}

/// 対応する音声ファイルの拡張子。
enum SupportedAudio {
    static let extensions = ["wav", "mp3", "m4a", "flac", "aac", "ogg"]

    static func isAudio(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Settings

/// 外観モード。macOSの外観モードと同じくライト／ダーク／自動（システムに従う）。
enum AppearanceMode: String, Hashable, Identifiable, CaseIterable {
    case auto
    case light
    case dark

    var id: String { rawValue }
}

/// 文字の大きさ。小さい／標準／大きい。
enum FontSizeOption: String, Hashable, Identifiable, CaseIterable {
    case small
    case standard
    case large

    var id: String { rawValue }
}

/// サウンド選択肢。
struct SoundOption: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isBundled: Bool

    /// 同梱のみサンプルprefixを付ける。
    func label(language: String) -> String {
        if isBundled {
            return String(format: L10n.string("sample.prefix", language: language), name)
        }
        return name
    }
}

/// 壁紙選択肢。
struct WallpaperOption: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isBundled: Bool

    /// 同梱のみサンプルprefixを付ける。
    func label(language: String) -> String {
        if isBundled {
            return String(format: L10n.string("sample.prefix", language: language), name)
        }
        return name
    }
}
