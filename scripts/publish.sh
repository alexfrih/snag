#!/usr/bin/env bash
# Publish a release: upload the notarized zip to GitHub Releases, regenerate the
# EdDSA-signed Sparkle appcast, and push the Pages-hosted feed.
# Run AFTER scripts/release.sh.   Usage: scripts/publish.sh <version>   e.g. 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: publish.sh <version>  (e.g. 0.2.0)}"
APP_NAME="Snag"
ZIP="dist/${APP_NAME}.zip"
TAG="v${VERSION}"
REPO="alexfrih/snag"
GEN="$(find .build -path '*/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)"

[ -f "${ZIP}" ] || { echo "missing ${ZIP} — run scripts/release.sh first"; exit 1; }
[ -x "${GEN}" ] || { echo "generate_appcast not found — run a build first"; exit 1; }

echo "==> GitHub release ${TAG}"
gh release create "${TAG}" "${ZIP}" --repo "${REPO}" --title "${APP_NAME} ${VERSION}" --notes "${APP_NAME} ${VERSION}" \
  || gh release upload "${TAG}" "${ZIP}" --repo "${REPO}" --clobber

# Isolate the zip: generate_appcast scans a directory, and dist/ also holds the
# website .dmg — only the Sparkle .zip belongs in the feed.
echo "==> generate EdDSA-signed appcast"
mkdir -p docs dist/sparkle
cp "${ZIP}" dist/sparkle/
"${GEN}" --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" -o docs/appcast.xml dist/sparkle

echo "==> publish feed (GitHub Pages)"
git add docs/appcast.xml
git commit -m "Publish appcast for ${TAG}" || true
git push origin main

echo "==> done — feed: https://alexfrih.github.io/snag/appcast.xml"
