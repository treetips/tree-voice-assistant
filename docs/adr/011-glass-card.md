# 全画面のカードをLiquid Glassに共通化する

- ステータス: Accepted
- 影響範囲: 変換・設定・Aboutの各画面、`Core/GlassCard.swift`
- 関連: tree-image-optimizer ADR 0022（GlassCardによる共通化）

## 背景

変換画面の入力エリアなどは `GroupBox` で囲まれており、Liquid Glassになっていない。
`glassEffect` は実行ボタン（`GlassCTAButton`）にだけ使われており、
濃さ（tint不透明度）や角丸が各所に分散している。

## 決定

- `Core/GlassCard.swift` に `GlassStyle` と `GlassCard` を新設する。
  参照元の `TreeImageOptimizer/Core/GlassCard.swift` と同じ定義を持ち込む。
- `GlassStyle` でカード・フッター・CTAのtint不透明度と角丸を一元管理する。
  透明度や屈折率の調整はこの定義だけを変更すれば全画面に反映される。
- カードの初期値は透明（tintなしの `regular`）とする。青が必要な場所は
  呼び出し側で `tint` を上書きする（例: フッターは `footerTintOpacity: 0.2` で青を維持）。
- `ConvertView`（4箇所: 入力・出力・文字起こし・音声合成）・
  `SettingsView`（2箇所: 通知・基本）・`AboutView`（2箇所: アプリ情報・バージョン一覧）の
  `GroupBox` を `GlassCard` に置き換える。見出し文言とローカライズは変えない。
- HIGのBoxes（macOSはタイトルを枠の上に表示）に合わせ、タイトルはガラス枠の外・上に置く。
  枠内に含めると透けで可読性が落ちるため。
- `GlassCTAButton` の `glassEffect` も `GlassStyle` の定数（0.5/14）を参照させる。

## 結果

- 全画面のカード枠がLiquid Glassになり、見た目が統一される。
  初期値は透明で、フッターなど青が必要な場所だけ上書きする。
- 濃さ・形状の変更点が1ファイルに集約され、調整が容易になる。
- `GlassCardTests` で中央値（カード透明/22、フッター0.2/22、CTA0.5/14）と
  `tint` 上書きの可否を検証する。

## 適合確認

- デプロイメントターゲットmacOS 26.0を維持し、`glassEffect` の利用可能範囲内で実装する。
- 既存テストは削除せず、`GlassCardTests` を追加する。
