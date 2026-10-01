import Foundation

/// 実行段階。ボタンの状態表示に使う。
enum EngineStage: Sendable, Equatable {
    case idle
    case preparingModel
    case running
}

/// 文字起こしエンジンの抽象。テストでは仮実装に差し替える。
protocol TranscriptionEngine: Sendable {
    func transcribe(
        audioURL: URL, modelID: String, onStage: @escaping @Sendable (EngineStage) -> Void
    ) async throws -> String
}

extension TranscriptionEngine {
    func transcribe(audioURL: URL, modelID: String) async throws -> String {
        try await transcribe(audioURL: audioURL, modelID: modelID, onStage: { _ in })
    }
}

/// 音声合成の要求。
struct TTSRequest: Sendable, Equatable {
    var model: String
    var refAudioURL: URL
    var refText: String
    var text: String
    var outputDirectory: URL
    /// Irodori-TTSのcaption。Qwen側は無視する。
    var caption: String? = nil // swiftlint:disable:this implicit_optional_initialization
}

/// 音声合成エンジンの抽象。テストでは仮実装に差し替える。
protocol SpeechSynthesizer: Sendable {
    /// 合成して出力ファイルを返す（一括方式）。
    func synthesize(
        request: TTSRequest, onStage: @escaping @Sendable (EngineStage) -> Void
    ) async throws -> URL
    /// 合成しながら音声断片のURLを逐次返す（ streaming 方式）。
    func speakStream(request: TTSRequest) -> AsyncThrowingStream<URL, Error>
}

extension SpeechSynthesizer {
    func synthesize(request: TTSRequest) async throws -> URL {
        try await synthesize(request: request, onStage: { _ in })
    }

    /// 既定は一括合成して単一片として返す。
    func speakStream(request: TTSRequest) -> AsyncThrowingStream<URL, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await synthesize(request: request))
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
        }
    }
}
