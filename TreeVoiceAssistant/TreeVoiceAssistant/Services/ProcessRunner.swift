import Foundation

/// 外部コマンドの実行結果。
struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

/// コマンド実行の関数形。テストでは差し替え可能にする。
typealias RunCommand = @Sendable (
    _ executable: String,
    _ args: [String],
    _ workingDirectory: String?
) async throws -> ProcessResult

/// 外部コマンドを実行する。
/// 終了コードが0以外の場合は `AppError.processFailed` を投げる。
struct ProcessRunner: Sendable {
    func run(
        _ executable: String,
        args: [String] = [],
        workingDirectory: String? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { _ in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: AppError.processFailed(
                        executable: executable,
                        exitCode: process.terminationStatus,
                        output: "\(stdout)\n\(stderr)"
                    ))
                } else {
                    continuation.resume(returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AppError.toolMissing(executable))
            }
        }
    }

    /// 外部コマンドを実行する。タスクの取り消しでプロセスを終了させる。
    /// 終了コードが0以外の場合は `AppError.processFailed` を投げる。
    /// 取り消しによる終了の場合は呼び出し側で `Task.isCancelled` を見て扱うこと。
    /// 取り消し時は子孫プロセスごと終了し、uv経由のpython等を残さない。
    func runCancellable(
        _ executable: String,
        args: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.terminationHandler = { _ in
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: AppError.processFailed(
                            executable: executable,
                            exitCode: process.terminationStatus,
                            output: "\(stdout)\n\(stderr)"
                        ))
                    } else {
                        continuation.resume(returning: ProcessResult(
                            exitCode: process.terminationStatus,
                            stdout: stdout,
                            stderr: stderr
                        ))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AppError.toolMissing(executable))
                }
            }
        } onCancel: {
            let pid = process.processIdentifier
            process.terminate()
            Self.terminateTree(pid: pid)
        }
    }

    /// 指定プロセスを子孫ごと終了する。存在しなくても何もしない。
    static func terminateTree(pid: Int32) {
        terminateSubtree(root: pid, seen: [])
        runDetached("/bin/kill", ["-TERM", String(pid)])
    }

    private static func terminateSubtree(root: Int32, seen: Set<Int32>) {
        var seen = seen
        guard !seen.contains(root) else { return }
        seen.insert(root)
        for child in childPIDs(of: root) {
            terminateSubtree(root: child, seen: seen)
            runDetached("/bin/kill", ["-TERM", String(child)])
        }
    }

    /// 直下の子プロセスIDを返す。取得失敗時は空。
    static func childPIDs(of pid: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 実行開始前の残存プロセスを掃除する。合致なしは何もしない。
    /// 呼び出し元自身には合致しない目印を使うこと。
    static func terminateLeftovers(matching markers: [String]) {
        for marker in markers {
            runDetached("/usr/bin/pkill", ["-TERM", "-f", marker])
        }
    }

    private static func runDetached(_ executable: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
