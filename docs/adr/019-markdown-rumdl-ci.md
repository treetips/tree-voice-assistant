# Markdownのlint・フォーマットをrumdlで行いCIでチェックする

- ステータス: Accepted
- 実行トリガーに関する決定は [ADR 024](024-markdown-ci-push-only.md) で変更した。
- 影響範囲: `.rumdl.toml`、`.github/workflows/markdown.yml`、`.vscode`、`AGENTS.md`、`docs/design/system.md`
- 関連: tree-image-optimizer ADR 0043（Markdownのlint・フォーマットをrumdlで行いCIでチェックする）

## 背景

Markdownの書式はSwiftと違って検査手段が無く、文書ごとにインデント・空行・
コードフェンスの言語指定・見出しの重複といった揺れが放置されていた
（導入時点の自前Markdownにはrumdl基準の違反が91件あった）。
AGENTS.md に「markdownを修正した場合は `rumdl` でフォーマットしてlintチェックし、
エラーが有れば修正する」を追加したが、遵守は個人の手順に依存し、CIで担保できない。

## 決定

- MarkdownのLinter・Formatterに [rumdl](https://rumdl.dev/) を採用し、設定を
  リポジトリ直下の `.rumdl.toml` で管理する。導入はHomebrew（`brew install rumdl`）。
- lint対象は自前のMarkdownすべて（`include = ["**/*.md"]`）。
  - 同梱しているスキルの文書（`.opencode`）は外部由来のため対象外にする。
  - `.github` も対象外とする（ワークフロー内の見出し等に規約を当てない）。
- 既存の違反を一括で解消し、クリーンな状態を初期状態にする。
  - 書式系の86件は `rumdl fmt` で自動修正する。
  - 重複見出し（MD024）は文脈込みの見出し名に変更する（例: `ランダムチェックボックス` →
    `成功時のランダムチェックボックス`）。メニュー項目の `区切り線` は位置を付けて区別する。
- GitHub Actions（`.github/workflows/markdown.yml`）で `rumdl check`（PRアノテーション付き）と
  `rumdl fmt --check` を実行し、違反があるとCIに失敗する。実行は全ブランチのpushと
  すべてのPRで毎回行い、変更ファイルでは絞らない。
- rumdlのバージョンはワークフローで固定し、ローカルとCIで検査結果が変わらないようにする。

## 代替案

- Markdown関連の変更時だけ実行する（pathsで絞る）
  - 却下: 変更ファイルで絞るとMarkdown以外の変更で検査が素通りし、
    どのブランチでも違反が無い状態を常に確認できない。実行は数秒で終わる。
- 変更されたMarkdownだけを検査する
  - 却下: 既存違反が放置され、そのファイルを将来触ったときにまとめて直しが必要になる。
    全体を常に検査した方が違反が蓄積しない。
- markdownlint-cli2を使う
  - 却下: rumdlはNode.jsランタイムを不要とし、フォーマッタも兼ねる。ローカル導入も
    Homebrew1コマンドで済む。
- pull_requestのブランチをmainに限定する
  - 却下: 積み上げPR（ベースがfeatureブランチ）でも検査を通したい。

## 結果

- Markdownの修正は `rumdl fmt` と `rumdl check` で品質が揃い、CIが違反を検出する。
- 実装箇所: `.rumdl.toml`・`.github/workflows/markdown.yml`・`docs/design/system.md`。
- 既存のMarkdown違反は `docs/` 配下と `AGENTS.md` で解消済み。
