# ポータブルなuvの内蔵

- ホストへの `uv` 事前インストールを不要にする。
- 公式の単体バイナリ（`uv-aarch64-apple-darwin.tar.gz`、0.12.9、SHA-256検証）を
  初回TTS実行時に取得し、`~/Library/Application Support/tree-voice-assistant/tools/bin/uv` に配置する。
  取得・検証・展開は `UVInstaller` が行う（参照元の `ToolInstaller` と同型）。
- TTS実行は内蔵 `uv` を優先し、開発時の利便のためホストの探索先も残す。
- `mlx-audio` はPyPI版（0.5.1）に固定し、ホストの `git` を不要にする。
- Pythonは `uv` が自動調達する。音声形式はWAV運用のため `ffmpeg` は不要。
- 変更後のホスト要件はゼロ（初回のみ通信が必要）。
