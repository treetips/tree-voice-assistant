# Irodori-TTS併設 設計書

- 日付: 2026-10-01（2026-10-01に複数チェックポイント対応へ更新）
- 方式: 直接実行（`uv` で `infer.py` を叩く）
- チェックポイント: プルダウンで選択（サイズ降順: v4-Large / v4-Large-Quantized / v4.1-Small-MF / v4.1-Small / v4.1-Small-Quantized）
  - 量子化版は `int8-weight-only` 方式を使う。精度はinfer.pyの既定（fp32）に任せる
- Qwen3-TTS（mlx-audio）との両立が前提

## 目的・成功条件

- 変換画面のTTSプルダウンで `Qwen3-TTS-12Hz-1.7B` / `Qwen3-TTS-12Hz-0.6B` / `Irodori-TTS-v4.1-Small` / `Irodori-TTS-v4.1-Small-MF` を選べる
- Irodori選択時は `--ref-wav` + `--caption` で合成できる
- Qwen選択時の動作・保存済み設定を壊さない
- 成功条件: プルダウン切替で各エンジンが合成でき、Irodoriで文字起こし未実施の場合は実行できない

## 前提・制約

- macOS（CPU/MPS）で動作する。`--model-device auto` に任せる
- `tools/tts`（mlx-audio）と `tools/tts-irodori`（Irodori）を分離する。混載しない
- IrodoriのPython依存にgit参照（`dacvae`、`silentcipher`）が含まれるため、ホストに `git` が必要になる
- ユーザー指定: captionは任意、事前文字起こしは必須
- git操作は本設計では行わない（AGENTS.mdの禁止事項に従う）。ADRは別途起票する

## 構成

- `TTSModel` に `irodoriV41Small` / `irodoriV41SmallMF` を追加する
  - 表示名: `Irodori-TTS-v4.1-Small` / `Irodori-TTS-v4.1-Small-MF`
  - HFチェックポイント: `Aratako/Irodori-TTS-v4.1-Small` / `Aratako/Irodori-TTS-v4.1-Small-MF`（定数、UIで直接編集不可）
  - MFはMeanFlow用少量ステップ版。CLIは同一でランタイムが自動判定する
  - v4-Large・量子化バリアント・v2/v3系は対象外（必要になれば追加）
- `TTSRequest` に `caption: String? = nil` を追加する。Qwen側は無視する
- 新規 `IrodoriTTSService: SpeechSynthesizer` を追加する
  - 配置: `tools/tts-irodori` に `pyproject.toml` + `Irodori-TTS` チェックアウト + `.venv`
  - `uv sync --extra cpu` で環境作成（macOSはPyPIのtorchにフォールバック）
  - 合成は `python infer.py --hf-checkpoint ... --text ... --ref-wav ... --caption ... --output-wav ...` を実行
- `ConvertViewModel` でエンジンを分岐する
  - Qwen選択時: `MLXAudioTTSService`
  - Irodori選択時: `IrodoriTTSService`
  - `captionText` を保持し、`settings.json` の `convert` に永続化する
- `ConvertView` のTTS区分にcaption入力欄を追加する。Irodori選択時のみ表示する

## 実行条件

- 共通条件: 参照音声あり、出力フォルダ正常、本文あり、実行中でない
- Irodori追加条件:
  - `transcriptionText` が空でない（事前文字起こし必須）
  - `captionText` が空でもよい（caption任意）
  - 文字起こし文のcaptionへの自動転記はしない
- Qwen側の条件は現行のまま変えない

## 引数

Irodori固定引数:

```
run --project <tools/tts-irodori> python <src>/infer.py
  --hf-checkpoint <選択中のIrodoriチェックポイント>
  --text <speechText>
  --ref-wav <audioFileURL.path>
  --caption <captionText>
  --output-wav <tmp/result.wav>
  --model-device auto
```

- `--ref_text` は渡さない
- captionは空を許可する（空欄時は `--caption` を付けない）
- 出力は一時フォルダで受け、`${yyyyMMddHHmmss}.wav`（JST）に改名する。現行Qwenと同一規則

## エラー処理

- 初回はモデル取得のため長時間化する。Qwen同様に準備中表示とする
- `uv sync` 失敗、`infer.py` 失敗は内容付きエラーとして `resultMessage` に載せる
- 取り消しはタスク取り消しとしてプロセスに伝播し、世代管理で完了処理を守る。現行方式を踏襲する

## 変更ファイル

- `Core/Models.swift`: `TTSModel` に2件追加
- `Core/EngineProtocols.swift`: `TTSRequest.caption` 追加
- `Services/IrodoriTTSService.swift`: 新規
- `Services/AppPaths.swift`: `ttsIrodoriURL` 追加
- `Features/Convert/ConvertViewModel.swift`: `captionText`、分岐、実行条件
- `Features/Convert/ConvertView.swift`: caption欄（Irodori時のみ）
- `Services/SettingsStore.swift`: `ConvertSettings.captionText` 追加（既存設定の読み込み互換を保つ）
- テスト: 引数組み立て、実行条件分岐、永続化の単体テストを追加

## 検証

- lint → format → build → 関連単体テスト
- 実機合成（Qwen/Irodori各1件）は手動確認とする。モデル取得が重いため自動テストでは実行しない

## 対象外

- v4-Large・量子化バリアント・v2/v3系チェックポイント
- LoRA、複数参照音声、量子化バリアント指定
- サーバ方式（Irodori-TTS-Server）への対応
- 既存Qwen引数の変更
