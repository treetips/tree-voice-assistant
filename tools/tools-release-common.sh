#!/usr/bin/env bash
# tools-releaseスクリプトで共有するツール一覧・バージョン解決・配置検証。

TOOL_NAMES=(uv tts tts-irodori)
REPO_ROOT="${TVA_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TOOLS_ROOT="${TOOLS_ROOT:-$REPO_ROOT/tools}"
APP_RESOURCES="${APP_RESOURCES:-$REPO_ROOT/TreeVoiceAssistant/TreeVoiceAssistant/Resources}"

swift_constant() {
  local file="$1" key="$2"
  grep -E "static let ${key} = \"" "$file" \
    | sed -E "s/.*\"([^\"]+)\".*/\1/" \
    | head -n1
}

resolve_irodori_revision() {
  if [[ -n "${IRODORI_REVISION:-}" ]]; then
    printf '%s\n' "$IRODORI_REVISION"
    return
  fi
  git ls-remote https://github.com/Aratako/Irodori-TTS refs/heads/main \
    | awk 'NR == 1 { print $1 }'
}

tool_version() {
  local name="$1"
  case "$name" in
    uv)
      swift_constant "$REPO_ROOT/TreeVoiceAssistant/TreeVoiceAssistant/Services/UVInstaller.swift" uvVersion
      ;;
    tts)
      local base hash
      base="$(swift_constant "$REPO_ROOT/TreeVoiceAssistant/TreeVoiceAssistant/Services/MLXAudioTTSService.swift" mlxAudioVersion)"
      if [[ -s "$TOOLS_ROOT/tts/pyproject.toml" && -s "$TOOLS_ROOT/tts/uv.lock" ]]; then
        hash="$(shasum -a 256 "$TOOLS_ROOT/tts/pyproject.toml" "$TOOLS_ROOT/tts/uv.lock" \
          | shasum -a 256 | awk '{print $1}')"
      else
        hash="$(shasum -a 256 "$APP_RESOURCES/tts-pyproject.toml" | awk '{print $1}')"
      fi
      printf '%s-%s\n' "$base" "${hash:0:12}"
      ;;
    tts-irodori)
      resolve_irodori_revision
      ;;
    *)
      echo "::error::Unknown tool: $name" >&2
      return 1
      ;;
  esac
}

validate_tool_versions() {
  local name version
  for name in "${TOOL_NAMES[@]}"; do
    version="$(tool_version "$name")"
    if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
      echo "::error::Invalid version for $name: $version" >&2
      return 1
    fi
  done
}

verify_tool_payload() {
  local name="$1" relative
  local -a required
  case "$name" in
    uv) required=('bin/uv') ;;
    tts) required=('tts/pyproject.toml' 'tts/uv.lock') ;;
    tts-irodori)
      required=('tts-irodori/pyproject.toml' 'tts-irodori/uv.lock' 'tts-irodori/Irodori-TTS/infer.py')
      ;;
    *) echo "::error::Unknown tool: $name" >&2; return 1 ;;
  esac
  for relative in "${required[@]}"; do
    if [[ ! -s "$TOOLS_ROOT/$relative" ]]; then
      echo "::error::Missing or empty tool payload: $relative" >&2
      return 1
    fi
  done
  if [[ "$name" == uv && ! -x "$TOOLS_ROOT/bin/uv" ]]; then
    echo "::error::uv is not executable: bin/uv" >&2
    return 1
  fi
}
