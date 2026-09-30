import Foundation

/// 実行ログの保存。`logs/${yyyyMMddHHmmss}.log`（JST）に書き出す。
struct RunLogStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init(paths: AppPaths) {
        self.init(directory: paths.logsURL)
    }

    /// 出力ファイル名 `${yyyyMMddHHmmss}.log`。JSTで統一する。
    static func timestampFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date) + ".log"
    }

    /// 行群を1ファイルに書き出してURLを返す。同名衝突時は `-02` 以降を付ける。
    func write(engine: String, model: String, lines: [String], date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = Self.timestampFileName(date: date).deletingPathExtension
        var url = directory.appendingPathComponent(base + ".log", isDirectory: false)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let suffixed = "\(base)-\(String(format: "%02d", counter)).log"
            url = directory.appendingPathComponent(suffixed, isDirectory: false)
            counter += 1
        }
        var body = "エンジン: \(engine)\nモデル: \(model)\n"
        for line in lines {
            body += line + "\n"
        }
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
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

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
