#!/bin/bash
#
# start.sh — Xcodeを起動せずにアプリをビルドして起動する。
#
# 使い方:
#   ./start.sh
#
# macOSデスクトップアプリにエミュレーター（シミュレーター）は存在しないため、
# xcodebuild でビルドした .app を `open` でそのまま起動する（Mac上でネイティブ動作）。
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="TreeVoiceAssistant/TreeVoiceAssistant.xcodeproj"
SCHEME="TreeVoiceAssistant"
CONFIGURATION="Debug"
DERIVED_DATA="$PWD/.build/derivedData"
MAX_ATTEMPTS=3
RETRY_WAIT=10

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild が見つかりません。Xcodeをインストールしてください。" >&2
    exit 1
fi

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "==> Resolving packages (attempt ${attempt}/${MAX_ATTEMPTS})..."
    if xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        -resolvePackageDependencies; then
        break
    fi
    echo "warning: パッケージ解決に失敗しました。${RETRY_WAIT}秒後に再試行します。" >&2
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
        echo "error: パッケージ解決に失敗しました（${MAX_ATTEMPTS}回試行）。" >&2
        exit 1
    fi
    sleep "$RETRY_WAIT"
done

echo "==> Building (${CONFIGURATION})..."
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    if xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        build; then
        break
    fi
    echo "warning: ビルドに失敗しました。${RETRY_WAIT}秒後に再試行します（attempt ${attempt}/${MAX_ATTEMPTS}）。" >&2
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
        echo "error: ビルドに失敗しました（${MAX_ATTEMPTS}回試行）。" >&2
        exit 1
    fi
    sleep "$RETRY_WAIT"
done

APP_PATH=$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "error: .app が見つかりませんでした。" >&2
    exit 1
fi

echo "==> Launching: $APP_PATH"
open "$APP_PATH"
