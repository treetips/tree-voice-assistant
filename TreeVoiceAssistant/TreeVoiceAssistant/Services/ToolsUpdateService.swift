import Foundation

/// tools単位の差分更新を行う。アプリ本体の更新処理とは独立する。
struct ToolsUpdateService: Sendable {
    let paths: AppPaths
    let runner: ProcessRunner

    init(paths: AppPaths, runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    private var store: ToolsInfoStore {
        ToolsInfoStore(paths: paths)
    }

    static let supportedSchemaVersion = 1

    /// `tools-info.json` を取得し、対応スキーマと既知のツールだけを検証する。
    func fetchToolsInfo() async throws -> ToolsInfo {
        var request = URLRequest(url: ToolsInfoStore.toolsInfoURL)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.networkError(reason: "tools-info.json の取得に失敗しました")
        }
        let info = try JSONDecoder().decode(ToolsInfo.self, from: data)
        guard info.schemaVersion == Self.supportedSchemaVersion else {
            throw AppError.networkError(
                reason: "未対応の tools-info.json スキーマです: \(info.schemaVersion)")
        }
        let names = info.tools.map(\.name)
        guard names.count == Set(names).count, Set(names) == ToolsDistribution.knownNames else {
            throw AppError.networkError(reason: "tools-info.json のツール一覧が不正です")
        }
        for tool in info.tools {
            guard tool.required,
                  let url = URL(string: tool.url), url.scheme == "https",
                  tool.version.range(
                    of: "^[A-Za-z0-9][A-Za-z0-9._+-]*$", options: .regularExpression
                  ) != nil,
                  tool.sha256.range(
                    of: "^[0-9a-fA-F]{64}$", options: .regularExpression
                  ) != nil
            else {
                throw AppError.networkError(reason: "tools-info.json の \(tool.name) が不正です")
            }
        }
        return info
    }

    /// 差分のあるツールだけを更新する。完了済みは記録へ残し、再実行時に省略する。
    func updateTools(
        info: ToolsInfo,
        installed: InstalledTools,
        onProgress: @escaping @Sendable (ToolsUpdateProgress) -> Void = { _ in }
    ) async throws -> InstalledTools {
        try await installTools(
            targets: store.updatesNeeded(info: info, installed: installed),
            installed: installed,
            onProgress: onProgress
        )
    }

    /// 初回起動など、実体が欠けているツールを配布物から修復する。
    func installMissingTools(
        info: ToolsInfo,
        onProgress: @escaping @Sendable (ToolsUpdateProgress) -> Void = { _ in }
    ) async throws -> InstalledTools {
        try await installTools(
            targets: Self.missingTools(info: info, paths: paths),
            installed: store.loadInstalled(),
            onProgress: onProgress
        )
    }

    /// 移行前の「版不明」環境など、指定したツール群を一括してそろえる。
    func installTools(
        targets: [ToolMetadata],
        installed: InstalledTools,
        onProgress: @escaping @Sendable (ToolsUpdateProgress) -> Void
    ) async throws -> InstalledTools {
        guard !targets.isEmpty else { return installed }
        let total = Double(targets.count)
        var updated = installed
        for (index, tool) in targets.enumerated() {
            try await install(
                tool: tool,
                index: index,
                total: total,
                onProgress: onProgress
            )
            updated.tools[tool.name] = tool.version
            try store.saveInstalled(updated)
            onProgress(.init(
                phase: .installing,
                fraction: Double(index + 1) / total,
                label: tool.name
            ))
        }
        return updated
    }

    /// 対応バイナリ・ファイルが実体として存在しないツールを返す。
    static func missingTools(info: ToolsInfo, paths: AppPaths) -> [ToolMetadata] {
        info.tools.filter { tool in
            guard let layout = ToolsDistribution.layout(for: tool.name) else { return false }
            let root = paths.toolsURL.appendingPathComponent(layout.destination, isDirectory: true)
            return !Self.isPayloadComplete(at: root, layout: layout, requiresExecutable: tool.name == "uv")
        }
    }

    /// 単一ツールを download → SHA-256検証 → 展開 → 配置する。
    private func install(
        tool: ToolMetadata,
        index: Int,
        total: Double,
        onProgress: @escaping @Sendable (ToolsUpdateProgress) -> Void
    ) async throws {
        guard let layout = ToolsDistribution.layout(for: tool.name),
              let downloadURL = URL(string: tool.url), downloadURL.scheme == "https"
        else {
            throw AppError.networkError(reason: "未知のツール、または不正なURLです: \(tool.name)")
        }
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("tree-voice-tools-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }
        let archive = workDirectory.appendingPathComponent("\(tool.name).zip", isDirectory: false)

        let downloader = UpdateDownloader(destination: archive) { progress in
            let fraction = progress.phase == .downloading ? progress.fraction : nil
            onProgress(.init(
                phase: .downloading,
                fraction: Self.overallFraction(index: index, total: total, toolFraction: fraction),
                label: tool.name
            ))
        }
        try await downloader.download(from: downloadURL)

        onProgress(.init(
            phase: .verifying,
            fraction: Double(index) / total,
            label: tool.name
        ))
        let digest = try UpdateService.sha256(of: archive)
        guard digest == tool.sha256.lowercased() else {
            throw AppError.verificationFailed(
                reason: "SHA-256 mismatch: expected \(tool.sha256), got \(digest)")
        }

        try await extractAndPlace(
            tool: tool,
            layout: layout,
            workDirectory: workDirectory,
            baseFraction: Double(index) / total,
            onProgress: onProgress
        )
    }

    private func extractAndPlace(
        tool: ToolMetadata,
        layout: ToolLayout,
        workDirectory: URL,
        baseFraction: Double,
        onProgress: @escaping @Sendable (ToolsUpdateProgress) -> Void
    ) async throws {
        let archive = workDirectory.appendingPathComponent("\(tool.name).zip", isDirectory: false)
        onProgress(.init(
            phase: .extracting,
            fraction: baseFraction,
            label: tool.name
        ))
        _ = try await runner.run(
            "/usr/bin/unzip", args: ["-q", archive.path, "-d", workDirectory.path], workingDirectory: nil)
        guard let extractedRoot = findDirectory(named: layout.archiveRoot, under: workDirectory) else {
            throw AppError.fileNotFound(path: "\(layout.archiveRoot) not found in \(tool.name) archive")
        }

        onProgress(.init(
            phase: .installing,
            fraction: baseFraction,
            label: tool.name
        ))
        try place(extractedRoot: extractedRoot, tool: tool, layout: layout)
    }

    static func isPayloadComplete(
        at root: URL,
        layout: ToolLayout,
        requiresExecutable: Bool
    ) -> Bool {
        layout.requiredRelativePaths.allSatisfy { relativePath in
            let url = root.appendingPathComponent(relativePath, isDirectory: false)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return false }
            return !requiresExecutable || FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private static func overallFraction(index: Int, total: Double, toolFraction: Double?) -> Double {
        let fraction = min(max(toolFraction ?? 0, 0), 1)
        return (Double(index) + fraction) / total
    }

    private func findDirectory(named name: String, under directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }
        return contents.first { url in
            url.lastPathComponent == name
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// ステージングの内容を検証してから置換する。失敗時は旧ツールへ戻す。
    private func place(extractedRoot source: URL, tool: ToolMetadata, layout: ToolLayout) throws {
        let fileManager = FileManager.default
        let toolsDirectory = paths.toolsURL
        try fileManager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        let destination = toolsDirectory.appendingPathComponent(layout.destination, isDirectory: true)
        let identifier = UUID().uuidString
        let staging = toolsDirectory.appendingPathComponent(
            ".staging-\(layout.name)-\(identifier)", isDirectory: true)
        let backup = toolsDirectory.appendingPathComponent(
            ".backup-\(layout.name)-\(identifier)", isDirectory: true)
        try fileManager.copyItem(at: source, to: staging)
        defer { try? fileManager.removeItem(at: staging) }
        if tool.name == "uv" {
            let executable = staging.appendingPathComponent("uv", isDirectory: false)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        guard Self.isPayloadComplete(
            at: staging, layout: layout, requiresExecutable: tool.name == "uv"
        ) else {
            throw AppError.verificationFailed(reason: "\(tool.name) の配置物が不完全です")
        }

        let hadDestination = fileManager.fileExists(atPath: destination.path)
        if hadDestination {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            guard Self.isPayloadComplete(
                at: destination, layout: layout, requiresExecutable: tool.name == "uv"
            ) else {
                throw AppError.verificationFailed(reason: "\(tool.name) の配置後検証に失敗しました")
            }
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            if hadDestination, fileManager.fileExists(atPath: backup.path) {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch {
                    throw AppError.updateFailed(
                        reason: "旧\(tool.name)の復元に失敗しました。旧版: \(backup.path)")
                }
            }
            throw error
        }
        if hadDestination {
            try? fileManager.removeItem(at: backup)
        }
    }
}
