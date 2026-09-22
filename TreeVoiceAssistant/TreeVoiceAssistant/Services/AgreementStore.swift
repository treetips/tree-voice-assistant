import Foundation

/// 利用同意の記録。`Application Support` 配下の `agreement.json` に
/// 同意日時を保存し、存在すれば同意済みとして扱う。
struct AgreementStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(paths: AppPaths) {
        self.init(fileURL: paths.agreementFileURL)
    }

    /// 同意済みかどうか。ファイルが無ければ未同意。
    var isAgreed: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// 同意日時を書き込む。日時は `yyyy-MM-dd HH:mm:ss`。
    func agree(date: Date = Date()) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let payload: [String: String] = ["agreeDate": formatter.string(from: date)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
