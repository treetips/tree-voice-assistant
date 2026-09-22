# TreeVoiceAssistant (SwiftUI)

UIのみの実装。見た目と画面遷移が中心で、Whisper・TTSの実処理は未配線。

## 前提

- Xcode 26.6 / macOS Tahoe 26 SDK
- デプロイメントターゲットは macOS Tahoe 26.0

## 開き方・ビルド

```sh
open TreeVoiceAssistant/TreeVoiceAssistant.xcodeproj
xcodebuild -project TreeVoiceAssistant/TreeVoiceAssistant.xcodeproj \
  -scheme TreeVoiceAssistant -configuration Debug build
```

または `./start.sh` でビルドして起動する。

署名はアドホック（`CODE_SIGN_IDENTITY=-`）のため、チーム設定なしでローカルビルドできる。

## 範囲

- `NavigationSplitView` による音声変換/設定/Aboutの画面遷移
- 文字起こしはargmaxのWhisperKit（SPM、初回利用時にモデルを自動取得）
- 音声合成はargmaxのTTSKit（Qwen3-TTS、プリセットの声。SPMのみ、Python不要）
- 手動実行のみ。実行結果はファイル出力する
