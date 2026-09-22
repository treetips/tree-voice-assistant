# アーキテクチャ

- `argmax-oss-swift` で `Whisper` と `TTS` を `Swift` で記述します。
- `TTS` は `Qwen TTS` を採用。

## サウンドの再生

- [AVFoundation](https://developer.apple.com/av-foundation/)（`AVAudioPlayer`）を `SoundService` 経由で使います。音声ファイルはXcodeのリソースとして同梱します。
- 再生対象のフォルダは以下の通りです。
  - アプリバンドル内の `assets/sounds/success` 。最初から同梱されている `成功音声` のフォルダです。このフォルダには必ず音声ファイルが配置されています。
  - アプリバンドル内の `assets/sounds/error` 。最初から同梱されている `失敗音声` のフォルダです。このフォルダには必ず音声ファイルが配置されています。
  - `~/.config/tree-voice-assistant/sounds/success` 。ユーザーが自分で用意した `成功音声` のフォルダです。このフォルダはユーザーが任意に配置するので、フォルダ・ファイルが存在しない場合があります。
  - `~/.config/tree-voice-assistant/sounds/error` 。ユーザーが自分で用意した `失敗音声` のフォルダです。このフォルダはユーザーが任意に配置するので、フォルダ・ファイルが存在しない場合があります。


## 通知

- [UserNotifications](https://developer.apple.com/documentation/usernotifications/)（`UNUserNotificationCenter`）を `NotificationService` 経由で使います。起動時に許可を求め、アプリ前面表示中もバナーを出します。

## 国際化

- String Catalogs（`Resources/Localizable.xcstrings`、ja/en）を使います。SwiftUIの `.environment(\.locale)` が届かない箇所（メニュー・通知・ダイアログ文言）は `L10n.string(_:language:)` で設定言語に従わせます。

## アプリケーション

- アプリケーションアイコンは `Resources/TreeVoiceAssistant.icns` を使用します。
- About画面の表示アイコンは `assets/images/icon-tree-01.png` を使用します。
