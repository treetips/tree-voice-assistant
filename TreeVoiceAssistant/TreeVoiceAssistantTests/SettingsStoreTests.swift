import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("SettingsStore")
struct SettingsStoreTests {
    func makeStore() throws -> (SettingsStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json", isDirectory: false)
        return (SettingsStore(fileURL: file), file)
    }

    @Test("無い場合は初期値を保存して返す")
    func createsDefaultsWhenMissing() throws {
        let (store, file) = try makeStore()
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.settings == ScreenSettings.defaults())
        #expect(loaded.convert.whisperModel == WhisperModel.default.rawValue)
        #expect(loaded.convert.ttsModel == TTSModel.default.rawValue)
        #expect(loaded.convert.outputFolderPath == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("保存した値を読み込める")
    func roundTrip() throws {
        let (store, _) = try makeStore()
        var file = try store.load(maxParallel: 8)
        file.settings.playSound = true
        file.settings.wallpaperOpacity = 0.4
        file.convert.transcriptionText = "こんにちは"
        file.convert.outputFolderPath = "/tmp/out"
        try store.save(file)
        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.settings.playSound == true)
        #expect(reloaded.settings.wallpaperOpacity == 0.4)
        #expect(reloaded.convert.transcriptionText == "こんにちは")
        #expect(reloaded.convert.outputFolderPath == "/tmp/out")
    }

    @Test("壊れたJSONは初期値に戻る")
    func recoversFromCorruptJSON() throws {
        let (store, _) = try makeStore()
        var file = try store.load(maxParallel: 8)
        file.convert.speechText = "残す"
        try store.save(file)
        try "not json".write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.convert.speechText == "")
    }

    @Test("保存は決定的なバイト列になる")
    func stableBytes() throws {
        let (store, file) = try makeStore()
        var saved = try store.load(maxParallel: 8)
        saved.convert.speechText = "あ"
        try store.save(saved)
        let first = try Data(contentsOf: file)
        try store.save(try store.load(maxParallel: 8))
        let second = try Data(contentsOf: file)
        #expect(first == second)
    }

    @Test("サウンドランダム設定の初期値と保存")
    func soundRandom() throws {
        let (store, file) = try makeStore()
        #expect(try store.load(maxParallel: 8).settings.successSoundRandom == false)
        #expect(try store.load(maxParallel: 8).settings.errorSoundRandom == false)
        var saved = try store.load(maxParallel: 8)
        saved.settings.successSoundRandom = true
        saved.settings.errorSoundRandom = true
        try store.save(saved)
        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.settings.successSoundRandom == true)
        #expect(reloaded.settings.errorSoundRandom == true)
        // キーが無い旧設定JSONは false で復元する。
        let legacyConvert = #"{"convert":{"whisperModel":"b","transcriptionText":"","ttsModel":"b","#
        let legacyJSON = legacyConvert
            + #""speechText":""},"settings":{"playSound":true}}"#
        try legacyJSON.write(to: file, atomically: true, encoding: .utf8)
        let legacy = try store.load(maxParallel: 8)
        #expect(legacy.settings.successSoundRandom == false)
        #expect(legacy.settings.errorSoundRandom == false)
        #expect(legacy.settings.playSound == true)
    }

    @Test("色バリデーション")
    func colorValidation() {
        #expect(SettingsStore.isValidColor("#FFFFFF"))
        #expect(SettingsStore.isValidColor("FF00ff00"))
        #expect(!SettingsStore.isValidColor("zzz"))
        #expect(!SettingsStore.isValidColor("#FFF"))
        #expect(!SettingsStore.isValidColor(""))
    }
}

@Suite("AgreementStore")
struct AgreementStoreTests {
    func makeStore() throws -> (AgreementStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("agreement.json", isDirectory: false)
        return (AgreementStore(fileURL: file), file)
    }

    @Test("ファイルが無ければ未同意")
    func notAgreedWhenMissing() throws {
        let (store, _) = try makeStore()
        #expect(store.isAgreed == false)
    }

    @Test("同意するとagreeDate付きで保存される")
    func writesAgreeDate() throws {
        let (store, file) = try makeStore()
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: .current,
            year: 2026, month: 9, day: 22, hour: 10, minute: 30, second: 0
        ).date!
        try store.agree(date: date)
        #expect(store.isAgreed == true)
        let data = try Data(contentsOf: file)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(decoded?["agreeDate"] == "2026-09-22 10:30:00")
    }
}
