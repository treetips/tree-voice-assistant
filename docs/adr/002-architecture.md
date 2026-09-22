# アーキテクチャ

## シェルスクリプト版の実装概要

既に [シェルスクリプトによる実装](/Users/tester/work/tts) したものが動いており、それをSwiftUI化します。

シェルスクリプト版のざっくり実装は以下のような形です。

```shell
params=(
  --model "mlx-community/whisper-large-v3-mlx"
  --language "Japanese"
  --output-name "${OUTPUT_NAME}"
  --output-format "${OUTPUT_FORMAT}"
  --output-dir "${OUTPUT_DIR}"
)
uv run mlx_whisper "${params[@]}" "${SOURCE_PATH}"
```
```shell
params=(
  --lang_code "ja"
  --model "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit"
  --ref_audio "${SOURCE_PATH}"
  --ref_text "${REF_TEXT}"
  --text "${TEXT}"
  --file_prefix "result"
  --audio_format "wav"
  --output "output"
  --verbose
)
uv run python -m mlx_audio.tts.generate "${params[@]}"
```

上記をSwiftUIに移植します。

| シェルスクリプト版     | SwiftUI版                                                     | 説明                                         |
|------------------------|---------------------------------------------------------------|----------------------------------------------|
| mlx_whisper            | [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | WhisperにはMLX Swift版が有るのでそれを使う。 |
| mlx_audio.tts.generate | ？                                                            | ？                                          |

上記を考えてみましたが、TTSの方がSwiftではないため、断念。

代わりに [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) を発見。

`argmax-oss-swift` は `Whisper` と `Qwen TTS` の両方に対応しており、Swiftで書けます。

`Core ML` で実装されており、 `MLX` ではない点が気になるのですが、遅いという情報は見当たらないので、

`argmax-oss-swift` で決定。
