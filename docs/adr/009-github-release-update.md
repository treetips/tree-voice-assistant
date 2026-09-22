# GitHub Releasesによるアプリ更新配布

- tree-image-optimizer と同様の形式で、GitHub Releases を使った自前アップデート配布を行う。
  - アプリは `https://github.com/treetips/tree-voice-assistant/releases/latest/download/update-info.json`
    を取得し、セマンティックバージョン→ビルド番号の順で比較する。
  - 新しい場合のみアップデートダイアログを表示し、ZIP のダウンロード・SHA-256検証・
    展開・`/Applications` への適用・再起動を行う（`UpdateService`・`UpdateCheckController`）。
- リリース作業は GitHub Actions で自動化し、手動作業は「PRマージ」と
  「Releaseワークフローの実行ボタン押下（bump選択）」の2ステップに限定する。
  - `.github/workflows/ci.yml`: Build & Test の検証。
  - `.github/workflows/release.yml`: バージョン算出・テスト・Releaseビルド・
    ad-hoc再署名・ZIP/SHA-256/update-info.json 生成・タグpush・Release作成。
  - `.github/release.yml`: 自動リリースノートの分類設定。
- バージョンの正本は `TreeVoiceAssistant/TreeVoiceAssistant/Info.plist` の
  `CFBundleShortVersionString` / `CFBundleVersion` とし、ローカルでの手動更新は不要。
  Releaseワークフローが最新リリースタグ＋bump指定から算出して書き込む。
- uv 本体は実行時に取得するため（`UVInstaller`）、配布ZIPに同梱しない。
  tree-image-optimizer の `tools/`（Git LFS）相当の仕組みは持たない。
- 詳細な手順は `docs/design/release-flow.md` を参照。
