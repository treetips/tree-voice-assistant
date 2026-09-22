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
    func runCancellable(
        _ executable: String,
        args: [String] = [],
        workingDirectory: String? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
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
            process.terminate()
        }
    }
}
