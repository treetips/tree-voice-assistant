import Foundation
import WhisperKit

/// WhisperKitによる文字起こし。モデルは初回利用時に自動取得される。
/// 同一モデルのパイプを使い回す。
final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var pipes: [String: WhisperKit] = [:]

    /// 日本語の文字起こしを行う。
    func transcribe(audioURL: URL, modelID: String) async throws -> String {
        let pipe: WhisperKit
        if let cached = cachedPipe(for: modelID) {
            pipe = cached
        } else {
            let created = try await WhisperKit(WhisperKitConfig(model: modelID))
            storePipe(created, for: modelID)
            pipe = created
        }
        let options = DecodingOptions(language: "ja")
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return Self.joinedText(results.map { $0.text })
    }

    /// 同期ヘルパー経由で触る。async文脈から直接 `lock()` を呼ぶと警告になるため。
    private func cachedPipe(for modelID: String) -> WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return pipes[modelID]
    }

    private func storePipe(_ pipe: WhisperKit, for modelID: String) {
        lock.lock()
        defer { lock.unlock() }
        pipes[modelID] = pipe
    }

    /// 結果片を結合する。空文は除く。
    static func joinedText(_ texts: [String]) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
