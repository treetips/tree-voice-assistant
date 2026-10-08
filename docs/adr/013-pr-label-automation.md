# PRラベルの自動付与によるリリースノート分類

- ステータス: Accepted
- 影響範囲: `.github/workflows/label-pr.yml`（新設）、`.github/release.yml`
- 関連: tree-image-optimizer ADR 0024（PRラベルの自動付与によるリリースノート分類）

## 背景

GitHubの自動リリースノート (`--generate-notes`) は `.github/release.yml`
に従い **PRのラベル** 基準でカテゴリ分類される。しかしラベル付与が運用に
依存しており、付与漏れが続くと全PRが「🔧 その他 (Other Changes)」に
分類されてしまう。
(Conventional Commits の `feat:` 等のタイトル接頭辞は分類に使われない)

## 決定

- `.github/workflows/label-pr.yml` を追加し、PRオープン時にタイトルの
  Conventional Commits接頭辞からラベルを自動付与する。
- 対応表:

| 接頭辞 | ラベル | リリースノートのカテゴリ |
|--------|--------|--------------------------|
| `feat` | `feature` | ✨ 新機能 (Features) |
| `fix` | `fix` | 🐛 バグ修正 (Bug Fixes) |
| `perf` | `performance` | ⚡ パフォーマンス・改善 (Improvements) |
| `refactor` | `improvement` | ⚡ パフォーマンス・改善 (Improvements) |
| `docs` | `documentation` | 📝 ドキュメント (Documentation) |
| `build`/`chore`(scope: deps) | `dependencies` | 📦 依存パッケージ更新 (Dependencies) |
| Dependabot形式 (`Bump ...`) | `dependencies` | 📦 依存パッケージ更新 (Dependencies) |
| その他・接頭辞なし | 付与しない | 🔧 その他 (Other Changes) |

- 自動付与対象のラベルはタイトル変更 (`edited`) 時に一度外して付け直す。
- 分類ロジックはConventional Commitsのtype/scopeパースを含むため、
  stubの`gh`でラベル呼び出しを記録してローカルでテストする。
- 自動付与するラベルはリポジトリに事前に作成しておく
  (feature / fix / performance / improvement / dependencies)。

## 代替案

- リリース時に手動でラベルを付ける運用にする
  - 却下: 付与漏れが起きた原因そのものであり、再発を防げないため。
- release-drafter への移行
  - 却下: `--generate-notes` + `.github/release.yml` の現行構成で
    ラベルさえ付与されれば要件を満たすため、移行コストに見合わない。
- `github/labeler` アクションの利用
  - 却下: ファイルパスベースのラベリングが主用途であり、タイトル接頭辞
    ベースの判定は結局自前実装が必要になるため。

## 結果

- PRはオープン時に自動でラベル付与され、リリースノートが
  Conventional Commits接頭辞に応じて分類される。
- ラベル付与漏れによる「その他」一極集中が解消される。
- 実装箇所: `.github/workflows/label-pr.yml`
