import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("RunLogStore")
struct RunLogStoreTests {
    func makeStore() throws -> (RunLogStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (RunLogStore(directory: dir), dir)
    }

    @Test("時刻名のログに本文を書く")
    func writesTimestampedLog() throws {
        let (store, dir) = try makeStore()
        let url = try store.write(engine: "IrodoriTTS", model: "m", lines: ["cmd ok"])
        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath() == dir.resolvingSymlinksInPath())
        #expect(url.pathExtension == "log")
        #expect(url.deletingPathExtension().lastPathComponent.count == 14)
        let body = try String(contentsOf: url, encoding: .utf8)
        #expect(body.contains("IrodoriTTS"))
        #expect(body.contains("cmd ok"))
    }

    @Test("同名衝突時は接尾辞を付ける")
    func collisionSuffix() throws {
        let (store, _) = try makeStore()
        let first = try store.write(engine: "e", model: "m", lines: [], date: Date(timeIntervalSince1970: 0))
        let second = try store.write(engine: "e", model: "m", lines: [], date: Date(timeIntervalSince1970: 0))
        #expect(first != second)
        #expect(second.deletingPathExtension().lastPathComponent.hasSuffix("-02"))
    }
}
