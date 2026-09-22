import AppKit
import Foundation

/// アプリ情報・バージョン定数。
enum AppInfo {
    /// 同梱するargmax-oss-swiftのバージョン（SPMのpinに合わせる）。
    static let argmaxVersion = "0.18.0"

    static let githubURL = URL(string: "https://github.com/treetips/tree-voice-assistant")!
    static let updateInfoURL = URL(
        string: "https://github.com/treetips/tree-voice-assistant/releases/latest/download/update-info.json"
    )!

    /// アプリ本体のバージョン（Bundleから取得）。
    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// About画面に表示するアプリアイコン。同梱の `assets/images/icon-tree-01.png` を読む。
    static var appIconImage: NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(
            "assets/images/icon-tree-01.png", isDirectory: false
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    static var toolVersions: [(binary: String, version: String)] {
        [
            ("argmax-oss-swift", argmaxVersion),
        ]
    }
}
