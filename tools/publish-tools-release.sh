#!/usr/bin/env bash
# ビルド済みツール成果物をtools-latestの事前リリースへ公開する。
set -euo pipefail

OUT_DIR="${1:?成果物ディレクトリを指定してください}"
TAG="${TAG:-tools-latest}"
GH_TOKEN="${GH_TOKEN:?GitHub認証トークンを指定してください}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAGはtools-で始まる名前を指定してください: $TAG" >&2
  exit 1
}
[[ -d "$OUT_DIR" ]] || {
  echo "::error::成果物ディレクトリがありません: $OUT_DIR" >&2
  exit 1
}
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[[ -f "$OUT_DIR/tools-info.json" && -f "$OUT_DIR/SHA256SUMS.txt" ]] || {
  echo "::error::tools-info.jsonまたはSHA256SUMS.txtがありません" >&2
  exit 1
}

(
  cd "$OUT_DIR"
  shasum -a 256 -c SHA256SUMS.txt
)

binary_assets=()
metadata_assets=()
for file in "$OUT_DIR"/*; do
  [[ -f "$file" ]] || continue
  case "${file##*/}" in
    tools-info.json | SHA256SUMS.txt) metadata_assets+=("$file") ;;
    tools-*.zip) binary_assets+=("$file") ;;
  esac
done
[[ "${#binary_assets[@]}" -gt 0 ]] || {
  echo "::error::アップロードするツール成果物がありません: $OUT_DIR" >&2
  exit 1
}

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists; replacing assets."
else
  gh release create "$TAG" \
    --target main \
    --title "Tools" \
    --notes "Tree Voice Assistantの外部ツール配布物です。アプリが起動時に取得します。" \
    --prerelease
fi
# 通常リリースへ戻すとアプリ本体のreleases/latestを隠すため、常に事前リリースを維持する。
gh release edit "$TAG" --prerelease

# 旧資産を残したまま新ZIPを先に置き、最後にmanifestを切り替える。
gh release upload "$TAG" "${binary_assets[@]}" --clobber
gh release upload "$TAG" "${metadata_assets[@]}" --clobber

# 公開成功後にだけ、新manifestから参照されなくなった旧資産を削除する。
keep_assets=" "
for file in "${binary_assets[@]}" "${metadata_assets[@]}"; do
  keep_assets+=" ${file##*/} "
done
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if [[ "$keep_assets" != *" $name "* ]]; then
    gh release delete-asset "$TAG" "$name" --yes
  fi
done < <(gh release view "$TAG" --json assets --jq '.assets[].name')
