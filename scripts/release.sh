#!/usr/bin/env bash
# Build + codesign (Developer ID, Sparkle embedded) + notarize + staple Snag.app,
# then package a notarized + stapled Snag.dmg (drag-to-Applications) for the website.
# Sparkle auto-update uses the .zip (published to GitHub Releases by publish.sh).
# One-time setup (keeps Apple creds out of the script):
#   xcrun notarytool store-credentials solarbeam-notary \
#     --apple-id "<your apple id>" --team-id VP9U3RSL2K
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Snag"
BUNDLE="dist/${APP_NAME}.app"
DMG="dist/${APP_NAME}.dmg"
SIGN_ID="${SIGN_ID:-Developer ID Application: Solar Beam (VP9U3RSL2K)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-solarbeam-notary}"

echo "==> build"
swift build -c release

echo "==> assemble ${BUNDLE}"
rm -rf dist
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Frameworks"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp scripts/Info.plist "${BUNDLE}/Contents/Info.plist"
cp -R ".build/release/Sparkle.framework" "${BUNDLE}/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

echo "==> codesign (inside-out, hardened runtime)"
sign() { codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "$@"; }
FW="${BUNDLE}/Contents/Frameworks/Sparkle.framework"
# Sparkle's nested helpers must be signed before the framework and the app.
while IFS= read -r -d '' x; do sign "$x"; done < <(find "${FW}" -name "*.xpc" -print0)
[ -e "${FW}/Versions/B/Updater.app" ] && sign "${FW}/Versions/B/Updater.app"
[ -e "${FW}/Versions/B/Autoupdate" ] && sign "${FW}/Versions/B/Autoupdate"
sign "${FW}"
sign "${BUNDLE}"
codesign --verify --strict --verbose=2 "${BUNDLE}"

echo "==> notarize + staple app"
ZIP="dist/${APP_NAME}.zip"
ditto -c -k --keepParent "${BUNDLE}" "${ZIP}"
xcrun notarytool submit "${ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${BUNDLE}"
rm -f "${ZIP}"; ditto -c -k --keepParent "${BUNDLE}" "${ZIP}"

echo "==> package ${DMG} (drag-to-Applications)"
STAGE="$(mktemp -d)"
cp -R "${BUNDLE}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"

echo "==> codesign + notarize + staple dmg"
codesign --force --timestamp --sign "${SIGN_ID}" "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

echo "==> done"
echo "Notarized app:                       ${BUNDLE}"
echo "Disk image (website download):       ${DMG}"
echo "Update archive (Sparkle, publish.sh): ${ZIP}"
