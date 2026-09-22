# 共通仕様

## ✳️ アプリのアップデート

### ✏️ アップデートのチェック

https://github.com/treetips/tree-voice-assistant/releases/latest/download/update-info.json

- 起動時にバックグラウンドで確認し（ダイアログなし・サイドナビ通知のみ反映）、About画面・メニューバー・サイドナビ通知から手動確認もできる。
- GitHub Releasesの `update-info.json` を取得し、セマンティックバージョン→ビルド番号の順で比較する。GitHub側が新しい場合のみアップデートダイアログを表示する。
- ダウンロード・SHA-256検証・展開は `UpdateService` が行い、`/Applications` への適用と再起動は `UpdateCheckController` が行う。リリース手順は `docs/design/release-flow.md` を参照。

### ✏️ アップデートが有る場合

- 以下のダイアログを開く。

| 役割               | ラベル                                          | アクション         |
|--------------------|-------------------------------------------------|--------------------|
| ダイアログタイトル | アップデートがあります                          | -                  |
| ダイアログ説明     | vX.X.X をダウンロードしてインストールしますか？ | -                  |
| キャンセルボタン   | キャンセル                                      | ダイアログを閉じる |
| インストールボタン | インストール                                    | 後述参照           |

#### インストール

- GitHub Releases の `Tree-Voice-Assistant-vX.X.X-macos.zip` を、macOSのテンポラリフォルダにダウンロード。
- アプリを終了する（プロセスが終了する形）。
- zipを解凍すると `TreeVoiceAssistant.app` が有る。
- `Tree-Voice-Assistant-vX.X.X-macos.zip` を削除する。
- `/Applications/TreeVoiceAssistant.app` を削除する。（無い場合は無視）
- テンポラリフォルダの `TreeVoiceAssistant.app` を `/Applications` に移動する。
- `/Applications/TreeVoiceAssistant.app` を起動する。

### ✏️ アップデートが無い場合

- 左サイドナビの最下部に `アップデートはありません` と表示する。
