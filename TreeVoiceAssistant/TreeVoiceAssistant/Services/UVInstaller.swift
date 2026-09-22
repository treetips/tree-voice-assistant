import Foundation

/// 内蔵 `uv` の調達。初回TTS実行時に公式バイナリを取得し、
/// `tools/bin/uv` に配置する。開発時はホストの `uv` も使う。
struct UVInstaller: Sendable {
    /// 取得する `uv` の版。ADR-005の指定に合わせる。
    static let uvVersion = "0.12.9"
    static let uvAssetName = "uv-aarch64-apple-darwin.tar.gz"

    /// 公式リリースの取得元。
    static func downloadURL(version: String = uvVersion) -> URL {
        URL(string: "https://github.com/astral-sh/uv/releases/download/\(version)/\(uvAssetName)")!
    }

    private let paths: AppPaths
    private let command: RunCommand

    init(paths: AppPaths = AppPaths(), command: RunCommand? = nil) {
        self.paths = paths
        if let command {
            self.command = command
        } else {
            self.command = { executable, args, workingDirectory in
                try await ProcessRunner().runCancellable(
                    executable, args: args, workingDirectory: workingDirectory)
            }
        }
    }

    /// 使う `uv` のパスを返す。内蔵を優先し、無ければホストを探す。
    func uvExecutable() async throws -> String {
        let bundled = paths.bundledUvURL
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        try await installBundledUv()
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        if let host = try? await command("/bin/sh", ["-c", "command -v uv"], nil),
           !host.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return host.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw AppError.toolMissing(
            "uv（内蔵の取得に失敗し、ホストにも見つかりません）")
    }

    /// 公式バイナリを取得・展開して `tools/bin/uv` に配置する。
    /// TLSでの取得・展開の成功・版表示をもって検証とする。
    func installBundledUv() async throws {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let binDir = paths.bundledUvURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("tree-voice-uv-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDir) }
        let archive = workDir.appendingPathComponent(Self.uvAssetName, isDirectory: false)
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: Self.downloadURL())
            try fileManager.moveItem(at: tempURL, to: archive)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.networkError(reason: "uvの取得に失敗しました: \(error.localizedDescription)")
        }
        let expanded = workDir.appendingPathComponent("expanded", isDirectory: true)
        do {
            _ = try await command("/usr/bin/tar", ["-xzf", archive.path, "-C", expanded.path], nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.verificationFailed(reason: "uvの展開に失敗しました: \(error.localizedDescription)")
        }
        guard let uvBinary = Self.findUvBinary(under: expanded) else {
            throw AppError.verificationFailed(reason: "uvの書庫に実行ファイルがありません")
        }
        do {
            if fileManager.fileExists(atPath: paths.bundledUvURL.path) {
                try fileManager.removeItem(at: paths.bundledUvURL)
            }
            try fileManager.moveItem(at: uvBinary, to: paths.bundledUvURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: paths.bundledUvURL.path)
            _ = try await command(paths.bundledUvURL.path, ["--version"], nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.verificationFailed(reason: "uvの配置確認に失敗しました: \(error.localizedDescription)")
        }
    }

    /// 展開先から `uv` 本体を探す。
    static func findUvBinary(under directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "uv" {
            return url
        }
        return nil
    }
}
