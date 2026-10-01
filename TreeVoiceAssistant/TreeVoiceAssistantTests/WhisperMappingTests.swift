import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("WhisperMapping")
struct WhisperMappingTests {
    @Test("UIモデルはargmaxのモデルIDに対応する")
    func modelIDs() {
        #expect(WhisperModel.largeV3TurboCompressed.argmaxModelID == "large-v3-v20240930_626MB")
        #expect(WhisperModel.largeV3Turbo.argmaxModelID == "large-v3-v20240930_turbo")
        #expect(WhisperModel.baseMultilingual.argmaxModelID == "base")
        #expect(WhisperModel.baseEnglishOnly.argmaxModelID == "base.en")
        #expect(WhisperModel.smallMultilingual.argmaxModelID == "small")
        #expect(WhisperModel.smallEnglishOnly.argmaxModelID == "small.en")
        #expect(WhisperModel.tinyMultilingual.argmaxModelID == "tiny")
        #expect(WhisperModel.tinyEnglishOnly.argmaxModelID == "tiny.en")
    }

    @Test("初期値は圧縮版Turbo")
    func defaultModel() {
        #expect(WhisperModel.default == .largeV3TurboCompressed)
        #expect(WhisperModel.default.argmaxModelID == "large-v3-v20240930_626MB")
    }

    @Test("TTSモデルは外部プロセス版のチェックポイントに対応する")
    func ttsModelIDs() {
        #expect(TTSModel.qwen17B.mlxAudioModelID == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit")
        #expect(TTSModel.qwen06B.mlxAudioModelID == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
        #expect(TTSModel.default == .qwen17B)
        #expect(TTSModel.irodoriV41Small.irodoriHFCheckpoint == "Aratako/Irodori-TTS-v4.1-Small")
        #expect(TTSModel.irodoriV41SmallMF.irodoriHFCheckpoint == "Aratako/Irodori-TTS-v4.1-Small-MF")
        #expect(TTSModel.qwen17B.irodoriHFCheckpoint == nil)
        #expect(TTSModel.irodoriV41Small.isIrodori == true)
        #expect(TTSModel.qwen17B.isIrodori == false)
        #expect(TTSModel.irodoriV4Large.irodoriHFCheckpoint == "Aratako/Irodori-TTS-v4-Large")
        #expect(
            TTSModel.irodoriV4LargeQuantized.irodoriHFCheckpoint
                == "Aratako/Irodori-TTS-v4-Large-Quantized/int8-weight-only"
        )
        #expect(
            TTSModel.irodoriV41SmallQuantized.irodoriHFCheckpoint
                == "Aratako/Irodori-TTS-v4.1-Small-Quantized/int8-weight-only"
        )
        #expect(TTSModel.allCases.filter(\.isIrodori).map(\.rawValue) == [
            "Irodori-TTS-v4-Large",
            "Irodori-TTS-v4-Large-Quantized",
            "Irodori-TTS-v4.1-Small-MF",
            "Irodori-TTS-v4.1-Small",
            "Irodori-TTS-v4.1-Small-Quantized"
        ])
    }
}
