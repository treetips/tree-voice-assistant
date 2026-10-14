# 設定画面に背景画像のシャッフル機能を追加する

- ステータス: Accepted
- 影響範囲: `Services/SettingsStore.swift`、`Features/Settings/SettingsViewModel.swift`、`Features/Settings/SettingsView.swift`
- 関連: tree-image-optimizer ADR 0027（設定画面に背景画像のシャッフル機能を追加する）

## 背景

設定画面の `背景画像` は単一ファイルを選択するのみで、macOS の壁紙シャッフル
のような「一定間隔でランダム切り替え」はできなかった。ユーザーが配置した
壁紙を定期的に自動切り替えする機能が求められていた。

## 決定

- 設定画面 `基本設定` に `背景画像のシャッフル` 行を追加する。
    - 左カラムに `背景画像のシャッフル` ラベル、右カラムに左寄せで
      シャッフル間隔プルダウンと `ランダム` チェックボックスを配置する。
    - `ランダム` チェックで背景画像プルダウンを無効化し、シャッフル間隔
      プルダウンを有効化する。チェック解除時は逆にする。
- シャッフル間隔は 1 / 5 / 15 / 30 / 60 / 240 / 720 / 1440 分の 8 択。
- シャッフル対象はユーザー配置壁紙のみ。同梱（サンプル）壁紙は対象外。
- 切り替えロジックは `SettingsViewModel` が `Timer` で保持し、ランダムに
  ユーザー壁紙を選択して `wallpaper` を更新する。
- 設定は `ScreenSettings` に `wallpaperRandom` / `wallpaperShuffleInterval`
  として永続化し、旧・別名キーも読み込み時に統合する。

## 結果

- 設定画面から定期的なランダム壁紙切り替えが利用可能になった。
- 実装箇所:
  - `TreeVoiceAssistant/TreeVoiceAssistant/Features/Settings/SettingsView.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Features/Settings/SettingsViewModel.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Services/SettingsStore.swift`