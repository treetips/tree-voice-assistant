# ハイブリッド構成の実装（外部プロセス版TTS）

- ADR-004／ADR-005のとおり、音声合成を外部プロセス版に戻し、実装した。
  - 文字起こし： argmax の `WhisperKit`（変更なし）。
  - 音声合成： `uv` 管理のPython環境で `mlx_audio.tts.generate` を実行する
    `MLXAudioTTSService` を新設し、参照音声の声クローンを行う。
    引数はシェル版と同一（`--model`・`--lang_code ja`・`--ref_audio`・
    `--ref_text`・`--text`・`--file_prefix result`・`--audio_format wav`・
    `--output`・`--verbose`）。
  - モデルIDはADR-004の指定（1.7B→6bit、0.6B→bf16）を使う。
  - 生成物は一時フォルダで受け、`${yyyyMMddHHmmss}.wav` に改名して出力する。
- 実行環境の調達は次のとおり。
  - 内蔵 `uv`（0.12.9、aarch64）を初回TTS実行時に公式から取得し、
    `tools/bin/uv` に配置する（`UVInstaller`）。取得はTLS、
    検証は展開の成功と版表示で行う。内蔵が無理な場合はホストの `uv` を使う。
  - `tools/tts` に `pyproject.toml`（`mlx-audio==0.5.1` 固定）を置き、
    初回に `uv sync` で `.venv` を作る。失敗時は内容付きのエラーにする。
- 取り消しはタスク取り消しとしてプロセスに伝播し（`terminate`）、
  世代管理で完了処理を守る。手動実行のみの画面方針は変えていない。
- `mlx-audio-swift` 系のSwift依存と `ArgmaxSpeechService`（定型ボイス版）を削除した。
  TTSの `TTSKit` 製品リンクも外し、依存は `WhisperKit` のみに戻った。
