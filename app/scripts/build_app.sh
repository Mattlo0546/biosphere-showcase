#!/bin/zsh
# Builds dist/Biosphere.app and dist/Biosphere.zip.
#
#   scripts/build_app.sh                 # release-style build: no paper PDFs inside (they're a separate download)
#   BUNDLE_PAPERS=1 scripts/build_app.sh # self-contained build with the PDFs inside (for offline hand-off)
#
# Version comes from app/VERSION. Signs with the "Biosphere Developer" certificate if it's in the keychain
# (stable identity → macOS permissions survive updates), otherwise ad-hoc. If ~/.biosphere-update-token
# exists, the read-only GitHub key is embedded so the app can fetch updates and the paper pack.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/Biosphere.app
VERSION=${VERSION:-$(cat VERSION)}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
IDENTITY="Biosphere Developer"
TOKEN_FILE=${TOKEN_FILE:-$HOME/.biosphere-update-token}

for arch in arm64 x86_64; do
  swift build -c release --triple $arch-apple-macosx14.0 2>&1 | tail -1
done
BIN=$(mktemp -d)/Biosphere
lipo -create -output "$BIN" \
  "$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/Biosphere" \
  "$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/Biosphere"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Biosphere"
if [[ "${BUNDLE_PAPERS:-0}" == "1" ]]; then
  rsync -a --delete Resources/ "$APP/Contents/Resources/"
else
  rsync -a --delete --exclude 'bank/*/papers/' Resources/ "$APP/Contents/Resources/"
fi

if [[ -s "$TOKEN_FILE" ]] && ! grep -qE '^(github_pat_|ghp_)[A-Za-z0-9_]+$' <(tr -d '[:space:]' < "$TOKEN_FILE"); then
  echo "error: $TOKEN_FILE doesn't contain a GitHub token (it should start with github_pat_)." >&2
  echo "       Copy the token on GitHub, then run: pbpaste > ~/.biosphere-update-token" >&2
  exit 1
fi
if [[ -s "$TOKEN_FILE" ]]; then
  python3 - "$TOKEN_FILE" "$APP/Contents/Resources/update.key" <<'PY'
import base64, sys
tok = open(sys.argv[1]).read().strip().encode()
key = b"biosphere-updates"
open(sys.argv[2], "w").write(base64.b64encode(bytes(b ^ key[i % len(key)] for i, b in enumerate(tok))).decode())
PY
  echo "Embedded update key."
else
  echo "warning: no $TOKEN_FILE, so this build can't check for updates or download the paper pack." >&2
fi

ICONSET=$(mktemp -d)/Biosphere.iconset
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Biosphere</string>
  <key>CFBundleDisplayName</key><string>Biosphere</string>
  <key>CFBundleIdentifier</key><string>app.biosphere.revision</string>
  <key>CFBundleExecutable</key><string>Biosphere</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Biosphere watches Downloads for papers you AirDrop back from your iPad so Hank can mark them.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Biosphere can import finished papers from your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Biosphere can import finished papers from Documents.</string>
</dict></plist>
PLIST

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\"."
else
  codesign --force --deep --sign - "$APP"
  echo "warning: signing certificate not found; ad-hoc signed (permissions won't survive updates)." >&2
fi
(cd dist && rm -f Biosphere.zip && ditto -c -k --keepParent Biosphere.app Biosphere.zip)
echo "Built $APP v$VERSION ($BUILD) — $(du -sh "$APP" | cut -f1), zip $(du -sh dist/Biosphere.zip | cut -f1)"
