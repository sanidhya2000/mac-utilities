#!/bin/bash
# Packages a built .app into a distributable .dmg.
# Usage: make-dmg.sh <AppName>
set -euo pipefail

APP_NAME="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"
VERSION="$(cat "$ROOT/apps/$APP_NAME/VERSION" 2>/dev/null || echo 1.0.0)"

[ -d "$APP" ] || { echo "no app at $APP — run build-app.sh first"; exit 1; }

echo "==> Packaging $APP_NAME $VERSION"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"

# An Applications symlink makes the drag-to-install gesture obvious.
ln -s /Applications "$STAGE/Applications"

# A short note covering the Gatekeeper prompt, which every first-time user hits
# on an unsigned build.
cat > "$STAGE/Read me first.txt" <<EOF
$APP_NAME $VERSION

1. Drag $APP_NAME into the Applications folder beside this file.

2. The first time you open it, macOS will say the developer cannot be
   verified. That is expected: this build is not signed with a paid Apple
   Developer certificate.

   Right-click $APP_NAME in Applications, choose Open, then click Open
   in the dialog. You only need to do this once.

   If that dialog will not let you through, open
   System Settings > Privacy & Security and click "Open Anyway".

3. $APP_NAME runs in the menu bar. It has no Dock icon and no main window.

To check it is working:
   /Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME --diagnose
EOF

rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG" > /dev/null

rm -rf "$STAGE"
echo "    $DMG  ($(du -h "$DMG" | cut -f1))"
