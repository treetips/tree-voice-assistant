import Foundation

/// モデル取得済みかの判定。初回実行の注意表示に使う。
/// 取得先は `<基準>/models` に統一する。
struct ModelCacheChecker: Sendable {
    var modelsURL: URL
    var appSupportURL: URL
    var legacyDocumentsURL: URL
    var legacyHubURL: URL

    init(
        modelsURL: URL,
        appSupportURL: URL,
        legacyDocumentsURL: URL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Documents", isDirectory: true),
        legacyHubURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    ) {
        self.modelsURL = modelsURL
        self.appSupportURL = appSupportURL
        self.legacyDocumentsURL = legacyDocumentsURL
        self.legacyHubURL = legacyHubURL
    }

    init(appSupportURL: URL) {
        self.init(
            modelsURL: appSupportURL.appendingPathComponent("models", isDirectory: true),
            appSupportURL: appSupportURL)
    }

    init() {
        self.init(appSupportURL: AppPaths().projectDirectoryURL)
    }

    /// WhisperKitのモデル取得済みか。`modelID` は短縮名でも一致する。
    func isWhisperCached(_ modelID: String) -> Bool {
        let base = modelsURL
            .appendingPathComponent("argmaxinc/whisperkit-coreml", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: base.path) else {
            return false
        }
        return names.contains("openai_whisper-\(modelID)") || names.contains(modelID)
    }

    /// Hugging Face形式の取得済みか。`repo` は `org/name` 形式。
    func isHFCached(repo: String) -> Bool {
        let dir = hfHubURL.appendingPathComponent(hfCacheName(repo: repo), isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
    }

    var hfHubURL: URL {
        modelsURL.appendingPathComponent("hf-hub", isDirectory: true)
    }

    /// Irodori-TTSの実行可否。モデルとvenvのtorchが揃っていればtrue。
    /// `checkpoint` は `repo` または `repo/subfolder` 形式。
    func isIrodoriReady(checkpoint: String) -> Bool {
        let repo = String(checkpoint.split(separator: "/").prefix(2).joined(separator: "/"))
        guard isHFCached(repo: repo) else { return false }
        let venv = appSupportURL.appendingPathComponent("tools/tts-irodori/.venv", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: venv, includingPropertiesForKeys: [.isDirectoryKey])
        else { return false }
        for case let url as URL in enumerator where url.lastPathComponent == "torch" {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return true
            }
        }
        return false
    }

    /// 旧場所の取得済みを新場所へ移す。移行先の既存品は残す。
    func migrateIfNeeded() {
        migrateChildren(
            from: legacyDocumentsURL.appendingPathComponent("huggingface/models", isDirectory: true),
            to: modelsURL)
        migrateChildren(from: legacyHubURL, to: hfHubURL, onlyPrefix: "models--")
    }

    private func migrateChildren(from source: URL, to destination: URL, onlyPrefix: String? = nil) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: source.path) else {
            return
        }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names {
            if let prefix = onlyPrefix, !name.hasPrefix(prefix) { continue }
            let target = destination.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) { continue }
            let origin = source.appendingPathComponent(name, isDirectory: true)
            do {
                try FileManager.default.moveItem(at: origin, to: target)
            } catch {
                try? FileManager.default.copyItem(at: origin, to: target)
                try? FileManager.default.removeItem(at: origin)
            }
        }
    }

    /// HFキャッシュのディレクトリ名。`/` を `--` に置き換える。
    static func hfCacheName(repo: String) -> String {
        "models--" + repo.replacingOccurrences(of: "/", with: "--")
    }

    private func hfCacheName(repo: String) -> String {
        Self.hfCacheName(repo: repo)
    }
}
