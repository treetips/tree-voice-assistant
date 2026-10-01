# Irodori-TTSの併設（外部プロセス版）

- https://github.com/Aratako/Irodori-TTS
- https://huggingface.co/Aratako/models?sort=modified
- 音声合成にIrodori-TTSを追加し、Qwen3-TTSと併設した。
  - プルダウン: Qwen3-TTS-12Hz-1.7B／0.6B、Irodori-TTS-v4.1-Small／v4.1-Small-MF。
  - Irodoriは `uv` 管理の別環境 `tools/tts-irodori` で `infer.py` を実行する
   （`--hf-checkpoint`・`--text`・`--ref-wav`・`--caption`・`--output-wav`）。
  - `tools/tts`（mlx-audio）とは混載しない。依存衝突を避けるため。
  - Irodori選択時はcaption必須・事前文字起こし必須。`--ref_text` は渡さない。
  - v4-Large・量子化バリアント・v2/v3系は対象外。必要になれば追加する。
