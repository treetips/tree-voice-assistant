#!/usr/bin/env bash
# uv・TTSプロジェクト定義・Irodoriソースをツール単位ZIPとtools-info.jsonにまとめる。
#
# 使い方:
#   tools/build-tools-release.sh <output-dir>
#
# 環境変数:
#   REPO_URL  GitHubリポジトリURL
#   TAG       配布先リリースタグ（既定: tools-latest）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

OUT_DIR="${1:?出力先ディレクトリを指定してください}"
REPO_URL="${REPO_URL:-https://github.com/treetips/tree-voice-assistant}"
TAG="${TAG:-tools-latest}"
UV_BIN="${UV_BIN:-$(command -v uv)}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAGはtools-で始まる名前を指定してください: $TAG" >&2
  exit 1
}
[[ -x "$UV_BIN" ]] || {
  echo "::error::uvが見つかりません。setup-uvで配置してください: $UV_BIN" >&2
  exit 1
}
EXPECTED_UV_VERSION="$(tool_version uv)"
ACTUAL_UV_VERSION="$("$UV_BIN" --version | awk '{print $2}')"
[[ "$ACTUAL_UV_VERSION" == "$EXPECTED_UV_VERSION" ]] || {
  echo "::error::uvの版が一致しません: expected=$EXPECTED_UV_VERSION actual=$ACTUAL_UV_VERSION" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
find "$OUT_DIR" -maxdepth 1 -type f \
  \( -name 'tools-*.zip' -o -name 'tools-info.json' -o -name 'SHA256SUMS.txt' \) -delete

PAYLOAD="$OUT_DIR/.payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD/bin" "$PAYLOAD/tts" "$PAYLOAD/tts-irodori"
TOOLS_ROOT="$PAYLOAD"
export TOOLS_ROOT

cp "$UV_BIN" "$PAYLOAD/bin/uv"
chmod 755 "$PAYLOAD/bin/uv"
cp "$APP_RESOURCES/tts-pyproject.toml" "$PAYLOAD/tts/pyproject.toml"
cp "$APP_RESOURCES/tts-irodori-pyproject.toml" "$PAYLOAD/tts-irodori/pyproject.toml"

IRODORI_REVISION="$(resolve_irodori_revision)"
export IRODORI_REVISION
[[ -n "$IRODORI_REVISION" ]] || {
  echo "::error::Irodori-TTSのリビジョンを解決できませんでした" >&2
  exit 1
}
git clone --depth 1 --branch main \
  https://github.com/Aratako/Irodori-TTS "$PAYLOAD/tts-irodori/Irodori-TTS"
CLONED_REVISION="$(git -C "$PAYLOAD/tts-irodori/Irodori-TTS" rev-parse HEAD)"
[[ "$CLONED_REVISION" == "$IRODORI_REVISION" ]] || {
  echo "::error::Irodori-TTSのclone中にリビジョンが変わりました" >&2
  exit 1
}
rm -rf "$PAYLOAD/tts-irodori/Irodori-TTS/.git"

python3 - "$PAYLOAD/tts-irodori/pyproject.toml" "$IRODORI_REVISION" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
revision = sys.argv[2]
content = path.read_text(encoding="utf-8")
old = 'rev = "main"'
if content.count(old) != 1:
    raise SystemExit("Irodoriのpyprojectにrev = \"main\"が1箇所必要です")
path.write_text(content.replace(old, f'rev = "{revision}"'), encoding="utf-8")
PY

# Why not .venvも同梱しないか: CIのPython絶対パスを利用者環境へ持ち込むと
# 再配置で壊れるため。依存定義とlockfileだけを配り、初回合成時にuv syncする。
(
  cd "$PAYLOAD/tts"
  "$UV_BIN" lock
)
(
  cd "$PAYLOAD/tts-irodori"
  "$UV_BIN" lock
)

validate_tool_versions
for name in "${TOOL_NAMES[@]}"; do
  verify_tool_payload "$name"
done
[[ -s "$PAYLOAD/tts/uv.lock" && -s "$PAYLOAD/tts-irodori/uv.lock" ]] || {
  echo "::error::uv.lockの生成に失敗しました" >&2
  exit 1
}

entries_file="$(mktemp)"
trap 'rm -f "$entries_file"; rm -rf "$PAYLOAD"' EXIT

for name in "${TOOL_NAMES[@]}"; do
  version="$(tool_version "$name")"
  case "$name" in
    uv) root='bin' ;;
    tts) root='tts' ;;
    tts-irodori) root='tts-irodori' ;;
  esac
  zip_name="tools-${name}-${version}.zip"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent \
    "$PAYLOAD/$root" "$OUT_DIR/$zip_name"
  sha256="$(shasum -a 256 "$OUT_DIR/$zip_name" | awk '{print $1}')"
  printf '%s\t%s\t%s\n' "$name" "$version" "$sha256" >> "$entries_file"
  echo "Created: $zip_name (sha256=$sha256)"
done

python3 - "$OUT_DIR" "$REPO_URL" "$TAG" "$entries_file" <<'PY'
import hashlib
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
repo_url = sys.argv[2].rstrip("/")
tag = sys.argv[3]
entries = []
for line in pathlib.Path(sys.argv[4]).read_text(encoding="utf-8").splitlines():
    name, version, checksum = line.split("\t")
    filename = f"tools-{name}-{version}.zip"
    asset = out / filename
    if not asset.is_file():
        raise SystemExit(f"missing asset: {asset}")
    hasher = hashlib.sha256()
    with asset.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            hasher.update(chunk)
    if hasher.hexdigest() != checksum:
        raise SystemExit(f"checksum mismatch: {asset}")
    entries.append(
        {
            "name": name,
            "version": version,
            "url": f"{repo_url}/releases/download/{tag}/{filename}",
            "sha256": checksum,
            "required": True,
        }
    )

manifest = out / "tools-info.json"
manifest.write_text(
    json.dumps({"schemaVersion": 1, "tools": entries}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
files = sorted(out.glob("tools-*.zip")) + [manifest]
checksums = out / "SHA256SUMS.txt"
checksums.write_text(
    "".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
        for path in files
    ),
    encoding="utf-8",
)
print(f"created: {manifest}")
print(f"created: {checksums}")
PY
