#!/bin/bash
# Build WhereFrom.app (release) and package it into a distributable DMG with a
# drag-to-Applications layout. Output: dist/WhereFrom-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="WhereFrom.app"
VOL="WhereFrom"
DIST="dist"
DMG="$DIST/WhereFrom-$VERSION.dmg"
STAGE="$DIST/stage"

echo "Building ${APP}…"
./make-app.sh >/dev/null

echo "Staging DMG contents…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

echo "Creating ${DMG}…"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGE"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | awk '{print $1}')

echo "Done → $DMG  ($SIZE)"
echo "sha256: $SHA"