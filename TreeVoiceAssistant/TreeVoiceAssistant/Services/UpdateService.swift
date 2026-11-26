import CryptoKit
import Foundation

/// GitHub Releases配置のアップデート情報。
struct UpdateInfo: Codable, Equatable {
    var version: String
    var build: Int
    var url: String
    var sha256: String

    /// セマンティックバージョン→ビルド番号の順で比較する。
    func isNewerThan(currentVersion: String, currentBuild: Int) -> Bool {
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }
        let remote = version.split(separator: ".").compactMap { Int($0) }
        for index in 0 ..< 3 {
            let currentPart = index < current.count ? current[index] : 0
            let remotePart = index < remote.count ? remote[index] : 0
            if remotePart > currentPart { return true }
            if remotePart < currentPart { return false }
        }
        return build > currentBuild
    }
}

enum UpdateCheckResult: Sendable {
    case latest
    case available(UpdateInfo)
    case failed(String)
}

/// インストール処理の段階。この順に進む。
enum UpdateInstallPhase: Int, Sendable, Equatable, Comparable {
    case downloading = 0
    case verifying = 1
    case extracting = 2
    case installing = 3

    static func < (lhs: UpdateInstallPhase, rhs: UpdateInstallPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ヘッダーの「インストール中」カードに表示する進捗。
struct UpdateInstallProgress: Sendable, Equatable {
    var phase: UpdateInstallPhase
    /// 0...1。nilの段階は不確定表示にする。
    var fraction: Double?
    var receivedBytes: Int64
    var totalBytes: Int64

    /// 受信バイト数から進捗率を求める。総バイト数が不明ならnilを返す。
    /// サーバーが Content-Length を返さない場合に0%固定へ丸めないため。
    static func downloadFraction(received: Int64, total: Int64) -> Double? {
        guard total > 0 else { return nil }
        return min(max(Double(received) / Double(total), 0), 1)
    }

    static func downloading(received: Int64, total: Int64) -> UpdateInstallProgress {
        UpdateInstallProgress(
            phase: .downloading,
            fraction: downloadFraction(received: received, total: total),
            receivedBytes: received,
            totalBytes: total
        )
    }

    /// バイト進捗を持たない段階（検証・展開・配置）の不確定表示。
    static func indeterminate(_ phase: UpdateInstallPhase) -> UpdateInstallProgress {
        UpdateInstallProgress(phase: phase, fraction: nil, receivedBytes: 0, totalBytes: 0)
    }
}

/// 自前アップデート処理。ZIPのダウンロード・検証・展開と、再起動までの配置を扱う。
struct UpdateService: Sendable {
    /// `update-info.json` を取得してバージョン比較する。
    func checkForUpdate(url: URL, currentVersion: String, currentBuild: Int) async -> UpdateCheckResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("HTTPエラー")
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            if info.isNewerThan(currentVersion: currentVersion, currentBuild: currentBuild) {
                return .available(info)
            }
            return .latest
        } catch {
            return .failed("\(error)")
        }
    }

    /// ZIPをダウンロードしSHA-256検証して一時ディレクトリに展開する。
    /// 進捗はダウンロードの受信バイト数（Content-Length基準）で通知する。
    /// - Returns: 展開先ディレクトリ内の `.app` パス。
    func downloadAndPrepare(
        info: UpdateInfo,
        runner: ProcessRunner = ProcessRunner(),
        onProgress: @escaping @Sendable (UpdateInstallProgress) -> Void = { _ in }
    ) async throws -> URL {
        guard let downloadURL = URL(string: info.url) else {
            throw AppError.networkError(reason: "Invalid update URL: \(info.url)")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tree-voice-assistant-update", isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent("update.zip", isDirectory: false)

        let downloader = UpdateDownloader(destination: archive, onProgress: onProgress)
        try await downloader.download(from: downloadURL)

        onProgress(.indeterminate(.verifying))
        let digest = try Self.sha256(of: archive)
        guard digest == info.sha256.lowercased() else {
            throw AppError.verificationFailed(
                reason: "SHA-256 mismatch: expected \(info.sha256), got \(digest)")
        }

        onProgress(.indeterminate(.extracting))
        _ = try await runner.run(
            "/usr/bin/unzip", args: ["-o", archive.path, "-d", directory.path], workingDirectory: nil)
        guard let app = findAppBundle(under: directory, maxDepth: 2) else {
            throw AppError.fileNotFound(path: ".app bundle not found in archive")
        }
        return app
    }

    /// ファイルを読みながらSHA-256を計算する。大きなZIPを丸ごとメモリへ載せないため。
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func findAppBundle(under directory: URL, maxDepth: Int) -> URL? {
        var results: [URL] = []
        collectAppBundles(under: directory, depth: 0, maxDepth: maxDepth, into: &results)
        return results.sorted { $0.path < $1.path }.first
    }

    /// 再起動用のステージング先。実行中の `/Applications` のバンドルを先に置換しない。
    static func stagingDestination(for preparedApp: URL, paths: AppPaths = AppPaths()) -> URL {
        paths.updatesDirectoryURL.appendingPathComponent(preparedApp.lastPathComponent, isDirectory: false)
    }

    /// 展開済みアプリをApplication Supportへ退避し、再起動まで保持する。
    @discardableResult
    func stageForRestart(preparedApp: URL, paths: AppPaths = AppPaths()) throws -> URL {
        let destination = Self.stagingDestination(for: preparedApp, paths: paths)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: preparedApp, to: destination)
        return destination
    }

    /// 前回の再起動で不要になったステージングアプリを次回起動時に掃除する。
    func cleanupStagedUpdate(paths: AppPaths = AppPaths()) {
        let directory = paths.updatesDirectoryURL
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// インストール先。`/Applications/<展開名.app>` に固定する。
    static func installDestination(for preparedApp: URL) -> URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(preparedApp.lastPathComponent, isDirectory: false)
    }

    /// 展開済みの `.app` をインストール先に反映する。
    /// 同じボリュームへステージングして内容を検証し、旧アプリを退避してから名前を変える。
    @discardableResult
    func applyUpdate(preparedApp: URL, destination: URL) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: preparedApp.path) else {
            throw AppError.fileNotFound(path: preparedApp.path)
        }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).update-\(UUID().uuidString)", isDirectory: false)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: preparedApp, to: staging)
        guard fileManager.fileExists(
            atPath: staging.appendingPathComponent("Contents/Info.plist").path
        ) else {
            throw AppError.verificationFailed(reason: "アプリバンドルが不完全です")
        }

        var trashedAppURL: NSURL?
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: &trashedAppURL)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            if let trashedAppURL {
                let trashedURL = trashedAppURL as URL
                do {
                    try fileManager.moveItem(at: trashedURL, to: destination)
                } catch {
                    throw AppError.updateFailed(
                        reason: "旧アプリの復元に失敗しました。旧版: \(trashedURL.path)")
                }
            }
            throw error
        }
        return destination
    }

    private func collectAppBundles(
        under directory: URL, depth: Int, maxDepth: Int, into results: inout [URL]
    ) {
        guard depth <= maxDepth else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for url in contents {
            if url.pathExtension == "app" {
                results.append(url)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collectAppBundles(under: url, depth: depth + 1, maxDepth: maxDepth, into: &results)
            }
        }
    }
}

/// `URLSessionDownloadTask` の受信バイト数を通知するダウンローダ。
/// 進捗は1%単位に間引き、SwiftUIの状態更新を毎バイト起こさないようにする。
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (UpdateInstallProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var transferError: Error?
    private var lastPercent = -1

    init(destination: URL, onProgress: @escaping @Sendable (UpdateInstallProgress) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 30
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            lock.lock()
            self.session = session
            lock.unlock()
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite <= 0 {
            guard lastPercent != 0 else { return }
            lastPercent = 0
            onProgress(.downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite))
            return
        }
        let percent = Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100).rounded(.down))
        guard percent != lastPercent else { return }
        lastPercent = percent
        onProgress(.downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            transferError = AppError.networkError(reason: "Download failed: HTTP \(http.statusCode)")
            return
        }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            transferError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.invalidateAndCancel()
        finish(error ?? transferError)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.session = nil
        lock.unlock()
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
