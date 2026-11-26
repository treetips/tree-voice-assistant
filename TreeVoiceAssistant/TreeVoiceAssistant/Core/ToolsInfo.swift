import Foundation

/// `tools-info.json`（GitHub Releasesで配布するtoolsのメタデータ）を表す型。
/// アプリ本体の `UpdateInfo` とは独立して取得・更新する。
struct ToolsInfo: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var tools: [ToolMetadata]

    func metadata(for name: String) -> ToolMetadata? {
        tools.first { $0.name == name }
    }
}

/// 単一ツールの配布メタデータ。
struct ToolMetadata: Codable, Equatable, Sendable {
    var name: String
    var version: String
    var url: String
    var sha256: String
    var required: Bool
}

/// `tools/.installed.json` に記録するインストール済みバージョン。
struct InstalledTools: Codable, Equatable, Sendable {
    var tools: [String: String]

    init(tools: [String: String] = [:]) {
        self.tools = tools
    }

    func version(for name: String) -> String? {
        tools[name]
    }
}

/// tools配布メタデータとローカル記録の読み書きを担う。
struct ToolsInfoStore: Sendable {
    let paths: AppPaths

    init(paths: AppPaths) {
        self.paths = paths
    }

    /// toolsはアプリ本体のLatestを隠さないよう、別の事前リリースを参照する。
    static var toolsInfoURL: URL {
        AppInfo.githubURL.appending(path: "releases/download/tools-latest/tools-info.json")
    }

    var installedFileURL: URL {
        paths.toolsURL.appendingPathComponent(".installed.json", isDirectory: false)
    }

    func loadInstalled() -> InstalledTools {
        loadInstalledState().installed
    }

    /// 記録が無い・壊れている場合は「版不明」として空を返す。
    /// 実体の存在だけで現行版とみなすと、旧環境のuvやTTS定義が更新されないため。
    func loadInstalledState() -> (installed: InstalledTools, isKnown: Bool) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installedFileURL.path) else {
            return (InstalledTools(), false)
        }
        do {
            let data = try Data(contentsOf: installedFileURL)
            return (try JSONDecoder().decode(InstalledTools.self, from: data), true)
        } catch {
            return (InstalledTools(), false)
        }
    }

    func saveInstalled(_ installed: InstalledTools) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: installedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(installed)
        try data.write(to: installedFileURL, options: .atomic)
    }

    /// ローカル記録と異なるツールだけを更新対象にする。
    func updatesNeeded(info: ToolsInfo, installed: InstalledTools) -> [ToolMetadata] {
        info.tools.filter { tool in
            installed.version(for: tool.name) != tool.version
        }
    }
}

/// tools配布ZIPの展開規則と配置先。
struct ToolLayout: Equatable, Sendable {
    let name: String
    let archiveRoot: String
    let destination: String
    let requiredRelativePaths: [String]
}

/// 対象プロジェクトが扱うtoolsの許可リスト。
enum ToolsDistribution {
    static let layouts: [String: ToolLayout] = [
        "uv": ToolLayout(
            name: "uv",
            archiveRoot: "bin",
            destination: "bin",
            requiredRelativePaths: ["uv"]
        ),
        "tts": ToolLayout(
            name: "tts",
            archiveRoot: "tts",
            destination: "tts",
            requiredRelativePaths: ["pyproject.toml", "uv.lock"]
        ),
        "tts-irodori": ToolLayout(
            name: "tts-irodori",
            archiveRoot: "tts-irodori",
            destination: "tts-irodori",
            requiredRelativePaths: ["pyproject.toml", "uv.lock", "Irodori-TTS/infer.py"]
        )
    ]

    static func layout(for name: String) -> ToolLayout? {
        layouts[name]
    }

    static var knownNames: Set<String> {
        Set(layouts.keys)
    }
}
