import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("ModelCacheChecker")
struct ModelCacheCheckerTests {
    struct TestRoots: Sendable {
        var models: URL
        var support: URL
        var legacyDocuments: URL
        var legacyHub: URL
    }

    func makeRoots() throws -> TestRoots {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("models", isDirectory: true),
            withIntermediateDirectories: true)
        return TestRoots(
            models: support.appendingPathComponent("models", isDirectory: true),
            support: support,
            legacyDocuments: base.appendingPathComponent("Documents", isDirectory: true),
            legacyHub: base.appendingPathComponent("hub", isDirectory: true))
    }

    func makeChecker(_ roots: TestRoots) -> ModelCacheChecker {
        ModelCacheChecker(
            modelsURL: roots.models,
            appSupportURL: roots.support,
            legacyDocumentsURL: roots.legacyDocuments,
            legacyHubURL: roots.legacyHub)
    }

    @Test("Whisper未取得はfalse")
    func whisperMissing() throws {
        let checker = makeChecker(try makeRoots())
        #expect(checker.isWhisperCached("large-v3-v20240930_626MB") == false)
    }

    @Test("Whisper取得済みはtrue")
    func whisperCached() throws {
        let roots = try makeRoots()
        let dir = roots.models
            .appendingPathComponent(
                "argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB",
                isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let checker = makeChecker(roots)
        #expect(checker.isWhisperCached("large-v3-v20240930_626MB") == true)
        #expect(checker.isWhisperCached("base") == false)
    }

    @Test("HF取得済みはtrue")
    func hfCached() throws {
        let roots = try makeRoots()
        let dir = roots.models
            .appendingPathComponent(
                "hf-hub/models--mlx-community--Qwen3-TTS-12Hz-1.7B-Base-6bit", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let checker = makeChecker(roots)
        #expect(checker.isHFCached(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit") == true)
        #expect(checker.isHFCached(repo: "mlx-community/other") == false)
    }

    @Test("Irodoriはモデルとvenvが揃ってtrue")
    func irodoriReady() throws {
        let roots = try makeRoots()
        let checker = makeChecker(roots)
        #expect(checker.isIrodoriReady(checkpoint: "Aratako/Irodori-TTS-v4.1-Small") == false)
        let hub = roots.models.appendingPathComponent(
            "hf-hub/models--Aratako--Irodori-TTS-v4.1-Small", isDirectory: true)
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        #expect(checker.isIrodoriReady(checkpoint: "Aratako/Irodori-TTS-v4.1-Small") == false)
        let torch = roots.support
            .appendingPathComponent(
                "tools/tts-irodori/.venv/lib/python3.11/site-packages/torch", isDirectory: true)
        try FileManager.default.createDirectory(at: torch, withIntermediateDirectories: true)
        #expect(checker.isIrodoriReady(checkpoint: "Aratako/Irodori-TTS-v4.1-Small") == true)
    }

    @Test("量子化はリポジトリ部分で判定する")
    func irodoriQuantizedRepo() throws {
        let roots = try makeRoots()
        let hub = roots.models.appendingPathComponent(
            "hf-hub/models--Aratako--Irodori-TTS-v4.1-Small-Quantized", isDirectory: true)
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        let torch = roots.support
            .appendingPathComponent(
                "tools/tts-irodori/.venv/lib/python3.11/site-packages/torch", isDirectory: true)
        try FileManager.default.createDirectory(at: torch, withIntermediateDirectories: true)
        let checker = makeChecker(roots)
        #expect(
            checker.isIrodoriReady(checkpoint: "Aratako/Irodori-TTS-v4.1-Small-Quantized/int8-weight-only")
                == true)
    }

    @Test("旧場所の取得済みを移す")
    func migratesLegacy() throws {
        let roots = try makeRoots()
        let legacyWhisper = roots.legacyDocuments
            .appendingPathComponent(
                "huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny",
                isDirectory: true)
        try FileManager.default.createDirectory(at: legacyWhisper, withIntermediateDirectories: true)
        let legacyHF = roots.legacyHub.appendingPathComponent("models--org--name", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyHF, withIntermediateDirectories: true)
        let checker = makeChecker(roots)
        #expect(checker.isWhisperCached("tiny") == false)
        checker.migrateIfNeeded()
        #expect(checker.isWhisperCached("tiny") == true)
        #expect(checker.isHFCached(repo: "org/name") == true)
    }

    @Test("移行先の既存品は残す")
    func migrationKeepsExisting() throws {
        let roots = try makeRoots()
        let legacy = roots.legacyHub.appendingPathComponent("models--org--name", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let destDir = roots.models.appendingPathComponent("hf-hub", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let existing = destDir.appendingPathComponent("models--org--other", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let checker = makeChecker(roots)
        checker.migrateIfNeeded()
        #expect(FileManager.default.fileExists(atPath: existing.path))
        #expect(checker.isHFCached(repo: "org/name") == true)
    }
}
