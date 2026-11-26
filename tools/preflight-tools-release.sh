#!/usr/bin/env bash
# 構築済み候補と既存tools-latestを比較し、公開が必要か判定する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

TAG="${TAG:-tools-latest}"
REPOSITORY="${REPOSITORY:-treetips/tree-voice-assistant}"
FORCE="${FORCE:-false}"
CANDIDATE_DIR="${CANDIDATE_DIR:?構築済み成果物ディレクトリを指定してください}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

[[ "$FORCE" == true || "$FORCE" == false ]] || fail "FORCEはtrueまたはfalseを指定してください。"
[[ "$TAG" == tools-* ]] || fail "TAGはtools-で始まる名前を指定してください: $TAG"
python3 - "$REPOSITORY" <<'PY'
import sys
parts = sys.argv[1].split("/")
if len(parts) != 2 or not all(parts) or any(char.isspace() for part in parts for char in part):
    raise SystemExit("REPOSITORYはowner/name形式で指定してください")
PY
[[ -d "$CANDIDATE_DIR" ]] || fail "候補ディレクトリがありません: $CANDIDATE_DIR"
CANDIDATE_DIR="$(cd "$CANDIDATE_DIR" && pwd)"
[[ -f "$CANDIDATE_DIR/tools-info.json" && -f "$CANDIDATE_DIR/SHA256SUMS.txt" ]] \
  || fail "tools-info.jsonまたはSHA256SUMS.txtがありません"
(
  cd "$CANDIDATE_DIR"
  shasum -a 256 -c SHA256SUMS.txt >/dev/null
)

python3 - "$CANDIDATE_DIR/tools-info.json" "$REPOSITORY" "$TAG" <<'PY'
import json
import pathlib
import posixpath
import re
import sys
from urllib.parse import urlparse

manifest_path, repository, tag = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"候補manifestを読み込めません: {error}")
if not isinstance(data, dict) or data.get("schemaVersion") != 1:
    raise SystemExit("候補manifestのschemaVersionが不正です")
entries = data.get("tools")
if not isinstance(entries, list):
    raise SystemExit("候補manifestのtoolsが不正です")
expected = {"uv", "tts", "tts-irodori"}
seen = set()
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit("候補manifestのentryが不正です")
    name = entry.get("name")
    version = entry.get("version")
    url = entry.get("url")
    checksum = entry.get("sha256")
    if name not in expected or name in seen:
        raise SystemExit(f"候補manifestのツール名が不正です: {name}")
    if not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
        raise SystemExit(f"候補manifestの{name}のversionが不正です")
    parsed = urlparse(url) if isinstance(url, str) else None
    expected_url = f"https://github.com/{repository}/releases/download/{tag}/"
    if parsed is None or not url.startswith(expected_url):
        raise SystemExit(f"候補manifestの{name}のURLが不正です")
    if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-fA-F]{64}", checksum) is None:
        raise SystemExit(f"候補manifestの{name}のchecksumが不正です")
    filename = posixpath.basename(parsed.path)
    if not (pathlib.Path(manifest_path).parent / filename).is_file():
        raise SystemExit(f"候補資産がありません: {filename}")
    if entry.get("required") is not True:
        raise SystemExit(f"候補manifestの{name}が必須ツールではありません")
    seen.add(name)
if seen != expected:
    raise SystemExit("候補manifestの必須ツールが不足しています")
PY

changed=true
if [[ "$FORCE" != true ]]; then
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  api_curl() {
    local -a args=(
      -sS -L
      --retry 3
      --retry-delay 2
      --connect-timeout 30
      -H 'Accept: application/vnd.github+json'
      -H 'X-GitHub-Api-Version: 2022-11-28'
      -H 'User-Agent: tree-voice-assistant-tools-release'
    )
    if [[ -n "${GH_TOKEN:-}" ]]; then
      args+=(-H "Authorization: Bearer $GH_TOKEN")
    fi
    curl "${args[@]}" "$@"
  }

  encoded_tag="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
  release_response="$WORK_DIR/release.json"
  if ! status="$(api_curl -o "$release_response" -w '%{http_code}' \
    "https://api.github.com/repos/${REPOSITORY}/releases/tags/${encoded_tag}")"; then
    fail "配布先リリース$TAGのAPI問い合わせに失敗しました。"
  fi
  case "$status" in
    200)
      manifest_url="$(python3 - "$release_response" "$TAG" <<'PY'
import json
import pathlib
import sys
from urllib.parse import urlparse

path = pathlib.Path(sys.argv[1])
tag = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"リリース{tag}の情報を読み込めません: {error}")
assets = [
    asset for asset in data.get("assets", [])
    if isinstance(asset, dict) and asset.get("name") == "tools-info.json"
]
if len(assets) != 1:
    raise SystemExit(f"リリース{tag}にtools-info.jsonがありません")
url = assets[0].get("browser_download_url")
parsed = urlparse(url) if isinstance(url, str) else None
if parsed is None or parsed.scheme != "https" or parsed.netloc != "github.com":
    raise SystemExit(f"リリース{tag}のtools-info.json URLが不正です")
print(url)
PY
      )" || fail "配布先リリース$TAGのマニフェスト情報を確認できませんでした。"
      remote_manifest="$WORK_DIR/tools-info.json"
      api_curl -fsSL "$manifest_url" -o "$remote_manifest" \
        || fail "配布先リリース$TAGのtools-info.jsonを取得できませんでした。"
      changed="$(python3 - "$CANDIDATE_DIR/tools-info.json" "$remote_manifest" \
        "$release_response" "$TAG" <<'PY'
import json
import pathlib
import posixpath
import sys
from urllib.parse import unquote, urlparse

candidate_path, remote_path, release_path, tag = sys.argv[1:]
try:
    candidate = json.loads(pathlib.Path(candidate_path).read_text(encoding="utf-8"))
    remote = json.loads(pathlib.Path(remote_path).read_text(encoding="utf-8"))
    release = json.loads(pathlib.Path(release_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"配布情報を読み込めません: {error}")
if not isinstance(remote, dict) or remote.get("schemaVersion") != 1:
    raise SystemExit("既存manifestのschemaVersionが不正です")
if not isinstance(remote.get("tools"), list):
    raise SystemExit("既存manifestのtoolsが不正です")

def checksum_map(data):
    result = {}
    for entry in data["tools"]:
        if not isinstance(entry, dict):
            raise SystemExit("既存manifestのentryが不正です")
        name = entry.get("name")
        if not isinstance(name, str) or name in result:
            raise SystemExit("既存manifestのツール名が不正です")
        result[name] = entry.get("sha256")
    return result

candidate_checksums = checksum_map(candidate)
remote_checksums = checksum_map(remote)
asset_names = {
    asset.get("name")
    for asset in release.get("assets", [])
    if isinstance(asset, dict) and isinstance(asset.get("name"), str)
}
candidate_files = {
    unquote(posixpath.basename(urlparse(entry["url"]).path))
    for entry in candidate["tools"]
}
missing_assets = (candidate_files | {"SHA256SUMS.txt"}) - asset_names
same_content = candidate_checksums == remote_checksums
is_prerelease = release.get("prerelease") is True
print("false" if same_content and not missing_assets and is_prerelease else "true")
PY
      )" || fail "既存tools-latestの検証に失敗しました。"
      ;;
    404)
      echo "配布先リリース$TAGはまだ存在しません。"
      ;;
    *)
      fail "配布先リリース$TAGのAPI問い合わせがHTTP$statusで失敗しました。"
      ;;
  esac
fi

printf 'changed=%s\n' "$changed" >> "$OUTPUT_FILE"
if [[ "$changed" == true ]]; then
  echo "ツール配布物の更新あり"
else
  echo "ツール配布物は最新です"
fi
