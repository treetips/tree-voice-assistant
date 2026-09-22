# ハイブリッド構成（WhisperKit + mlx_audio外部プロセス）

- TTSKit（OSS）に参照音声からの声クローン機能が無いことをソースで確認した。
  内蔵9ボイスのみで、シェル版の声質再現はできない。
- そのため以下とする。
  - 文字起こし： `WhisperKit`（SPM、`argmax-oss-swift` の `WhisperKit` プロダクト、0.9.0）。
    UIの8モデルはargmaxのモデルIDに対応付ける。言語は日本語固定。
  - 音声合成： `mlx_audio.tts.generate` を外部プロセスで実行する。
    シェル版（`run.sh`）と同一引数で声クローンを維持する。
- TTS実行環境は同梱せず、初回実行時に修復する。
  `~/Library/Application Support/tree-voice-assistant/tools/tts` に
  `pyproject.toml`（シェル版の移植）を配置し、`uv sync` で `.venv` を作る。
  `uv` が無い・同期失敗の場合は明確なエラーにする。
- TTSのモデルIDは以下を使う。
  - 1.7B → `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit`（シェル版実績）
  - 0.6B → `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16`（同系列の軽量版）
- 出力ファイル名は `${yyyyMMddHHmmss}.wav` とする（仕様書通り）。
  `mlx_audio` の生成物は一時フォルダで受けて改名する。
- かんたん画面のプリセットは `~/.config/tree-voice-assistant/presets/<名>/`
  配下の参照音声＋ `transcript.txt` の組み合わせとする。
