# アプリケーションとツールのリリースフロー

## 目的

検証済みのmacOSアプリと外部ツールをGitHub Releasesへ公開し、利用者が更新を取得できるようにする。アプリ本体とツールは更新頻度が異なるため、別々のReleaseとして配布する。

- アプリ本体はセマンティックバージョンとGitHubタグを一致させる。
- ツールはアプリのバージョンを変更せずに公開できる。
- 手動作業はPRマージとGitHub Actionsの実行ボタン押下に限定する。
- 失敗した配布物を利用者へ公開しない。

## Release構成

| 種類 | タグ | GitHub上の位置 | 主な成果物 |
| ---- | ---- | --------------- | ---------- |
| アプリ | `vMajor.Minor.Patch` | 通常リリース。GitHubの「Latest」 | アプリZIP、`update-info.json`、`SHA256SUMS.txt` |
| ツール | `tools-latest` | 事前リリース。「Latest」にはならない | `tools-info.json`、ツール単位ZIP、`SHA256SUMS.txt` |

ツールReleaseを事前リリースに保つことで、アプリの `releases/latest/download/update-info.json` が引き続きアプリ本体を指す。

## 全体フロー

```text
1. 機能開発・PRレビュー・CI
2. mainへマージ
3. ツールに更新がある場合だけ Release Tools を実行
   ├─ uvをセットアップし、TTSのlockfileとIrodori-TTSソースを準備
   ├─ ツール単位ZIP・tools-info.json・SHA256SUMS.txtを生成
   ├─ 構築済み候補と既存tools-latestを比較
   └─ 変更がある場合だけtools-latestの事前リリースを更新
4. アプリを公開する場合 Release を実行
   ├─ tools-latest/tools-info.jsonの取得を検証
   ├─ バージョンとビルド番号を算出
   ├─ Debugテスト・Releaseビルド
   ├─ アプリZIP・update-info.json・SHA256SUMS.txtを生成
   ├─ vX.Y.Zタグを作成
   └─ 通常リリースを作成
```

## ブランチとバージョン

- `main` がリリース候補の安定版ブランチです。直接pushは禁止し、PR経由でマージします。
- アプリの表示バージョンは `TreeVoiceAssistant/TreeVoiceAssistant/Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を使います。
- Releaseワークフローが最新の `vX.Y.Z` タグとbump指定から次のバージョンを算出します。
- ビルド番号は直近のアプリReleaseにある `update-info.json` の `build` に1を加えます。初回だけInfo.plistの値を使います。
- ローカルでバージョンを手動更新する必要はありません。
- `uv` と `mlx-audio` のバージョンはアプリ内の定数を使い、`Irodori-TTS` は配布時に解決したGitコミットをバージョンとして使います。
- Python仮想環境と音声モデルはtools ZIPへ含めず、初回利用時に取得します。

## ツールRelease

### 実行

1. GitHubの **Actions** → **Release Tools** → **Run workflow** を開く。
2. 配布先タグは既定の `tools-latest` を使う。
3. 同一バージョンでも配布物を作り直す場合だけ `force` を有効にする。

### 処理内容

1. `tools/build-tools-release.sh` が `uv` / `tts` / `tts-irodori` の3ツールをZIP化し、SHA-256を計算する。
2. ZIPのルートは `bin` / `tts` / `tts-irodori` とし、クライアントの展開規則を変えない。
3. `uv` の実体・実行権、TTSの `pyproject.toml` / `uv.lock`、Irodori-TTSの `infer.py` を確認する。
4. `tts` の配布バージョンには定義とlockfileの内容ハッシュを含め、定義だけの変更も更新対象にする。
5. `tools/preflight-tools-release.sh` が構築済み候補のSHA-256と既存 `tools-latest` を比較する。API障害や不正なマニフェストは更新なしとして扱わず、ワークフローを失敗させる。
6. 既存Releaseが無い、内容が異なる、必須資産が欠けている、事前リリースではない場合だけ公開する。
7. `tools/publish-tools-release.sh` が旧資産を残したまま新しいZIP、チェックサム、マニフェストの順に公開する。
8. 公開成功後にだけ、新manifestから参照されなくなった旧資産を削除する。

### 成果物

- `tools-<name>-<version>.zip`
- `tools-info.json`
- `SHA256SUMS.txt`

`tools-info.json` の各URLは `releases/download/tools-latest/` で統一する。スキーマは `schemaVersion: 1` を維持する。

## アプリRelease

### 実行

1. 事前にRelease Toolsを実行し、`tools-latest/tools-info.json` を取得できるようにする。
2. GitHubの **Actions** → **Release** → **Run workflow** を開く。
3. bumpとして `major` / `minor` / `patch` を選ぶ。

### 処理内容

1. 最新の `vX.Y.Z` タグとbump指定から次バージョンを算出する。
2. 直近のアプリReleaseのビルド番号から次ビルド番号を算出する。
3. `tools-latest/tools-info.json` を取得し、ツール配布の存在を検証する。
4. `.xcode-version` で指定したXcodeを選択する。
5. DebugテストとmacOS Releaseビルドを実行する。
6. アプリをアドホック署名し、署名を検証する。
7. アプリZIP、`update-info.json`、`SHA256SUMS.txt` を生成する。
8. `vX.Y.Z` タグを作成してpushする。
9. アプリZIP、チェックサム、更新情報だけを通常リリースへ添付する。

同じアプリReleaseにツールZIPや `tools-info.json` は添付しない。

## クライアントの参照先

- アプリ更新情報: `https://github.com/treetips/tree-voice-assistant/releases/latest/download/update-info.json`
- アプリ本体: `https://github.com/treetips/tree-voice-assistant/releases/download/<tag>/Tree-Voice-Assistant-<version>-macos.zip`
- ツール情報: `https://github.com/treetips/tree-voice-assistant/releases/download/tools-latest/tools-info.json`
- ツール本体: `https://github.com/treetips/tree-voice-assistant/releases/download/tools-latest/tools-<name>-<version>.zip`

アプリは更新情報のバージョンとビルド番号を比較し、ZIPをSHA-256検証して再起動用にステージングする。ツールは `tools-info.json` とローカル記録を比較し、差分のあるツールだけを更新する。

## 初回リリースと移行

- 初回は先にRelease Toolsを実行する。ツール配布が無い状態でアプリを公開しない。
- 既存クライアントはアプリ本体の更新を継続できる。
- 新しいアプリへ更新するまでは、旧クライアントのツール更新確認だけ失敗し、既存ツールを使い続ける。
- クリーンインストールの初回起動は、`tools-latest` から不足ツールをSHA-256検証付きで取得する。取得失敗時は既存の動的調達へフォールバックする。

## 失敗時と再実行

- テスト・ビルド・パッケージングに失敗した場合、タグやReleaseは作成しない。
- ツール公開は全資産をatomicに置き換える処理ではない。途中失敗後は `force=true` で再実行し、マニフェストと全資産の整合性を確認する。
- アプリ公開後の不具合は新しいバージョンで修正する。公開済みReleaseのタグや成果物を直接上書きしない。

## 配布上の注意

現在はアドホック署名で配布するため、Gatekeeperの警告と初回起動時の手動許可が必要になる。macOS専用配布であり、Windows/Linux向けバイナリは提供しない。
