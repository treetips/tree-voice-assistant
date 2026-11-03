# Swift関連の変更時のみBuild & Testを実行し、非該当時はスキップ報告する

- ステータス: Accepted
- 影響範囲: `.github/workflows/ci.yml`
- 関連: ADR 020（必須ステータスチェックのBuild & Testを常に実行する。本ADRで代替）、tree-image-optimizer `.github/workflows/ci.yml`

## 背景

ADR 020 では必須ステータスチェックの滞留を防ぐため、全PRで `Build & Test` を
実行するようにした。しかしSwift関連の変更が無いPRでもmacOSランナー上で
ビルド・テストが走り、macOS arm64ランナーの容量制約でキュー待ちのまま
キャンセルされる事象が続発した（PR #17・PR #19で発生。再実行の手間が生じる）。
Swift関連の変更を伴うときだけ実行する要件が出た。

一方で、tree-image-optimizer の `ci.yml` のようにワークフローの `paths` で
絞ると、非該当のPRでチェックが一度も報告されず、必須チェック待ちが
解消されないままマージできなくなる（PR #17のゾンビ状態。ADR 020の背景）。

## 決定

- `ci.yml` は全PR・mainへのpushで起動したまま、先頭に変更確認ジョブ
  （`changes`、ubuntu・数秒）を置き、macOSの `Build & Test` ジョブは
  job単位の `if` でSwift関連の変更があるときだけ実行する。
- Swift関連とみなすパスは `TreeVoiceAssistant/**`（アプリ・テストソースと
  Xcodeプロジェクト）・`assets/**`（アプリバンドルに同梱するリソース）・
  `.xcode-version`・`.github/workflows/ci.yml`。
- 非該当時 `Build & Test` は Skipped として報告される。GitHubの必須
  ステータスチェックは success・skipped・neutral を合格として扱うため、
  未報告のまま滞留するゾンビ状態は再発しない。
- ワークフローの `paths` フィルタは使わない。実行されないワークフローは
  チェックを報告しないためで、ADR 020で得た教訓を維持する。

## 代替案

- tree-image-optimizerと同様に `paths` フィルタだけで絞る
  - 却下: 非該当PRでチェックが報告されず、必須チェック待ちが解消されない
    （PR #17のゾンビ状態が再発する）。
- 非該当時に同名ジョブで成功を返すスタブワークフローを併置する
  - 却下: 同名のチェックが2系統になり、変更種別が混在したPRでどちらが
    報告したか追いにくくなる。
- ルールセットから必須ステータスチェックを外して `paths` で絞る
  - 却下: Swift変更のPRがビルド・テスト未実行のままマージできてしまう。

## 結果

- Swift関連の変更を伴うPR・mainへのpushでは従来どおり `Build & Test` が
  実行される。それ以外ではmacOSランナーを使わず、`Build & Test` は
  Skipped報告で必須ステータスチェックを満たす。
- 実装箇所: `.github/workflows/ci.yml`（`changes` ジョブと `verify` の実行条件）。
