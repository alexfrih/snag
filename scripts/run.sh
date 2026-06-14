#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Snag"
BUNDLE="dist/${APP_NAME}.app"

swift build -c release

rm -rf "dist"
mkdir -p "${BUNDLE}/Contents/MacOS"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "scripts/Info.plist" "${BUNDLE}/Contents/Info.plist"

pkill -x "${APP_NAME}" 2>/dev/null || true
open "${BUNDLE}"
echo "launched: ${BUNDLE}"
