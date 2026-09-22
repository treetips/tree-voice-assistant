import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("UpdateLogic")
struct UpdateLogicTests {
    @Test("アップデート比較")
    func updateComparison() {
        let info = UpdateInfo(version: "0.0.1", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(info.isNewerThan(currentVersion: "0.0.0", currentBuild: 99))
        #expect(info.isNewerThan(currentVersion: "0.0.1", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.0.1", currentBuild: 2))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.0.1", currentBuild: 3))
    }

    @Test("インストール先は/Applications配下")
    func installDestination() {
        let prepared = URL(fileURLWithPath: "/tmp/TreeVoiceAssistant.app", isDirectory: false)
        #expect(UpdateService.installDestination(for: prepared).path == "/Applications/TreeVoiceAssistant.app")
    }

    @Test("適用は展開済みアプリを複写する")
    func applyUpdateCopies() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prepared = base.appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        try fm.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: prepared.appendingPathComponent("Contents/Info.plist").path, contents: Data("x".utf8))
        let destination = base.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("TreeVoiceAssistant.app", isDirectory: false)
        let service = UpdateService()
        let installed = try service.applyUpdate(preparedApp: prepared, destination: destination)
        #expect(installed == destination)
        #expect(fm.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path))
    }

    @Test("適用は存在しない展開元で失敗する")
    func applyUpdateFailsWithoutSource() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = UpdateService()
        #expect(throws: AppError.self) {
            try service.applyUpdate(
                preparedApp: base.appendingPathComponent("Missing.app", isDirectory: false),
                destination: base.appendingPathComponent("Dest.app", isDirectory: false))
        }
    }
}
