import Foundation

/// 実行ログの保存。`logs/yyyyMMdd.log`（JST）に追記する。
/// 起動時・終了時に30日より古いログを消す。
struct RunLogStore: Sendable {
    /// 保持日数。
    static let keepingDays = 30

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init(paths: AppPaths) {
        self.init(directory: paths.logsURL)
    }

    /// 出力ファイル名 `yyyyMMdd.log`。JSTで統一する。
    static func timestampFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date) + ".log"
    }

    /// 時刻の見出し `yyyy-MM-dd HH:mm:ss`。JSTで統一する。
    static func timestampLabel(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 日単位ファイルに1件分を追記してURLを返す。
    func write(engine: String, model: String, lines: [String], date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.timestampFileName(date: date), isDirectory: false)
        var body = "## \(Self.timestampLabel(date: date))\nエンジン: \(engine)\nモデル: \(model)\n"
        for line in lines {
            body += line + "\n"
        }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(body.utf8))
        } else {
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    /// 保持日数より古い `yyyyMMdd.log` を消す。日付外のファイルは残す。
    static func rotate(directory: URL, keepingDays: Int = keepingDays, today: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        for name in names {
            guard name.hasSuffix(".log"), name.count == 12 else { continue }
            let stem = String(name.prefix(8))
            guard stem.allSatisfy(\.isNumber) else { continue }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
            formatter.dateFormat = "yyyyMMdd"
            guard let date = formatter.date(from: stem) else { continue }
            let days = calendar.dateComponents([.day], from: date, to: today).day ?? 0
            if days >= keepingDays {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(name, isDirectory: false))
            }
        }
    }

    /// 画面表示用の短い失敗理由。全文はログファイルに残る。
    static func shortReason(for error: Error) -> String {
        if let app = error as? AppError, case .processFailed(let executable, let exitCode, _) = app {
            return "\(executable) (終了コード \(exitCode))"
        }
        return error.localizedDescription
    }
}

/// コマンドを実行し、呼び出し・結果をログ行に記録する。
func runLogged(
    _ command: RunCommand, _ executable: String, _ args: [String],
    _ workingDirectory: String?, lines: inout [String]
) async throws -> ProcessResult {
    lines.append("$ \(executable) \(args.joined(separator: " "))")
    do {
        let result = try await command(executable, args, workingDirectory)
        lines.append("終了コード: \(result.exitCode)")
        if !result.stdout.isEmpty { lines.append("--- stdout ---\n\(result.stdout)") }
        if !result.stderr.isEmpty { lines.append("--- stderr ---\n\(result.stderr)") }
        return result
    } catch {
        lines.append("失敗: \(error)")
        throw error
    }
}
