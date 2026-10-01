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

    @Test("日単位のログに追記する")
    func writesDailyLog() throws {
        let (store, dir) = try makeStore()
        let first = try store.write(engine: "IrodoriTTS", model: "m", lines: ["one"])
        let second = try store.write(engine: "IrodoriTTS", model: "m", lines: ["two"])
        #expect(first == second)
        #expect(first.deletingPathExtension().lastPathComponent.count == 8)
        #expect(first.pathExtension == "log")
        #expect(first.deletingLastPathComponent().resolvingSymlinksInPath() == dir.resolvingSymlinksInPath())
        let body = try String(contentsOf: first, encoding: .utf8)
        #expect(body.contains("one"))
        #expect(body.contains("two"))
    }

    @Test("30日より古いログを消す")
    func rotatesOldLogs() throws {
        let (store, dir) = try makeStore()
        let today = Date()
        let old = try store.write(engine: "e", model: "m", lines: [], date: today.addingTimeInterval(-31 * 86400))
        let recent = try store.write(engine: "e", model: "m", lines: [], date: today.addingTimeInterval(-10 * 86400))
        let current = try store.write(engine: "e", model: "m", lines: [], date: today)
        let other = dir.appendingPathComponent("note.txt", isDirectory: false)
        try "x".write(to: other, atomically: true, encoding: .utf8)
        RunLogStore.rotate(directory: dir, today: today)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
