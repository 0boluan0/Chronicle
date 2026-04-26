#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Chronicle"
PROJECT_PATH="Chronicle.xcodeproj"
SCHEME="Chronicle"
CONFIGURATION="Debug"
DERIVED_DATA="build/local-run"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

kill_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_PATH"
}

verify_process() {
  sleep 1
  pgrep -x "$APP_NAME" >/dev/null
}

kill_app
build_app

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found at $APP_PATH" >&2
  exit 1
fi

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_PATH/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
