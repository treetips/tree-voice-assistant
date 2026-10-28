# 成功時・失敗時のサウンドのランダム再生を追加する

- ステータス: Accepted
- 影響範囲: `Services/SettingsStore.swift`、`Services/SoundService.swift`、`Services/CompletionNotifier.swift`、`Features/Settings/SettingsViewModel.swift`、`Features/Settings/SettingsView.swift`
- 関連: tree-image-optimizer ADR 0029（成功時・失敗時のサウンドのランダム再生を追加する）

## 背景

設定画面の `成功時のサウンド` / `失敗時のサウンド` は単一ファイルを選択するのみで、
ユーザーが配置した複数の音声から毎回異なる1つを再生する「ランダム再生」はできなかっ
た。背景画像シャッフル（014）と同様に、変換終了時にランダムに音声を切り替える機能が
求められていた。

## 決定

- 設定画面の成功時・失敗時サウンド行それぞれに `ランダム` チェックボックスを追加する。
    - チェックで該当プルダウンと `▶️` ボタンを `disabled` にし、解除で `enable` にする。
    - プルダウンの選択値は消さない。チェックを戻せば元の選択に復帰する。
    - 本リポジトリの仕様には `サウンドを再生する` チェック ⇄ プルダウンの連動が残る
      ので、プルダウンの無効条件は両者の OR（`!playSound || ランダム有効`）とする。
- 変換終了時に、ランダム有効ならユーザー配置サウンド
  （`~/.config/tree-voice-assistant/sounds/{success,error}`）から抽選して再生する。
    - 同梱（サンプル）サウンドは抽選対象外。背景画像シャッフル（014）と同一の方針。
    - ユーザー配置が無い・空の場合は選択中のサウンドへフォールバックし、音が鳴らない
      事態を防ぐ。
- 抽選ロジックは `SoundService.resolvePlaybackOption(success:name:random:)` に集約する。
    - 本リポジトリの再生箇所は `CompletionNotifier.finish` のみ（かんたん画面は006で
      撤去済み）なので、姉妹リポジトリのジョブストア2箇所の重複は発生しない。通知が
      この1箇所から抽選を呼び出す。
- 設定は `ScreenSettings` に `successSoundRandom` / `errorSoundRandom` として永続化する。
  初期値は `false`（チェック無し）。新キーのため別名キーは不要。

## 結果

- 変換終了時にユーザー配置サウンドからランダムに1つ再生できるようになった。
- `SettingsStoreTests` / `MediaServicesTests` / `SettingsViewModelTests` で永続化・抽選・
  状態復元の仕様を固定した。
- 実装箇所:
  - `TreeVoiceAssistant/TreeVoiceAssistant/Services/SettingsStore.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Services/SoundService.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Services/CompletionNotifier.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Features/Settings/SettingsViewModel.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Features/Settings/SettingsView.swift`
