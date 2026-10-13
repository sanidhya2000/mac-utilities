#!/bin/bash
# Builds a SwiftPM executable into a signed .app bundle.
# Usage: build-app.sh <AppName> <BundleID> <DisplayName>
set -euo pipefail

APP_NAME="$1"
BUNDLE_ID="$2"
DISPLAY_NAME="${3:-$1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/apps/$APP_NAME"
OUT="$ROOT/dist/$APP_NAME.app"
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo 1.0.0)"

echo "==> Building $APP_NAME $VERSION"
cd "$SRC"

# One .dmg must cover Apple silicon and Intel. `--arch` would be the obvious
# way to get a universal binary, but it routes through xcbuild, which ships
# only with full Xcode. Building each triple separately and merging with lipo
# needs nothing beyond the Command Line Tools.
# Each triple gets its own scratch path. Sharing one .build across triples
# corrupts SwiftPM's command registry ("command ... not registered") as soon as
# the two alternate.
ARCH_BINARIES=()
for TRIPLE in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
  echo "    compiling $TRIPLE"
  SCRATCH="$SRC/.build/$TRIPLE"
  swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" > /dev/null
  ARCH_BIN="$(swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)/$APP_NAME"
  [ -f "$ARCH_BIN" ] || { echo "no binary for $TRIPLE at $ARCH_BIN"; exit 1; }
  ARCH_BINARIES+=("$ARCH_BIN")
done

BIN="$(mktemp -d)/$APP_NAME"
lipo -create -output "$BIN" "${ARCH_BINARIES[@]}"
echo "    universal: $(lipo -archs "$BIN")"

echo "==> Assembling bundle"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"

# Info.plist lives beside the sources so each app owns its own usage strings.
sed -e "s/__APP_NAME__/$APP_NAME/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__DISPLAY_NAME__/$DISPLAY_NAME/g" \
    -e "s/__VERSION__/$VERSION/g" \
    "$SRC/Resources/Info.plist.in" > "$OUT/Contents/Info.plist"

if [ -f "$SRC/Resources/AppIcon.icns" ]; then
  cp "$SRC/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
fi

echo "APPL????" > "$OUT/Contents/PkgInfo"

# Ad-hoc signature. A Developer ID identity, when available, is picked up from
# the CODESIGN_IDENTITY environment variable instead.
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS="$SRC/Resources/$APP_NAME.entitlements"
SIGN_ARGS=(--force --options runtime --timestamp=none --sign "$IDENTITY")
[ -f "$ENTITLEMENTS" ] && SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")

echo "==> Signing with identity: $IDENTITY"
codesign "${SIGN_ARGS[@]}" "$OUT"
codesign --verify --verbose "$OUT" 2>&1 | sed 's/^/    /'

echo "==> Built $OUT"
du -sh "$OUT" | sed 's/^/    /'
