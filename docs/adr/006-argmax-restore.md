# かんたん画面の削除とargmaxへの復帰

- かんたん音声変換画面を全削除した。対象は画面・状態・設定・文言・テスト・
  プロジェクト定義のすべて。`settings.json` の `easyConvert` 欄は読まなくなるが、
  残っていても読み込みは成功する（未知の欄は無視される）。
- 音声合成を `mlx-audio-swift` から argmax の `TTSKit`（Qwen3-TTS）に戻した。
  - TTSKitに参照音声からの声クローン機能は無いため（ADR-004で確認済み）、
    合成はプリセットの声を使う。日本語の読み上げには `ono-anna` を使う。
  - 1.7B／0.6Bの選択は `TTSModelVariant`（`1.7b`／`0.6b`）に対応付ける。
  - 文字起こしは従来どおり argmax の `WhisperKit` を使う。
- `mlx-audio-swift` と `mlx-swift` のSPM参照・リンクを外した。
  依存は `argmax-oss-swift`（`WhisperKit`・`TTSKit`）のみに戻った。
- 手動実行・取り消し・世代管理の仕組みはそのまま残し、
  合成の既定エンジンだけを `ArgmaxSpeechService` に差し替えた。
