#!/bin/zsh
# Live dev loop: builds and runs "Biosphere Dev", then rebuilds + relaunches it a few seconds after you
# save any Swift file. Leave it running in a terminal; Ctrl-C to stop.
#
#   app/scripts/dev.sh
#
# • Biosphere Dev is a separate app (app.biosphere.dev) with its own data in ~/Biosphere-Dev (seeded once
#   from ~/Biosphere), so experiments never touch your real install, and it never self-updates.
# • It reads Hank's prompts/skills and the question bank straight from app/Resources: after editing those,
#   just press ⌘R in the app (no rebuild).
# • Debug build for this Mac only: no universal build, zip, signing ceremony or GitHub release.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/BiosphereDev.app"
STAMP=$(mktemp)
PID=""

make_bundle() {
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Biosphere Dev</string>
  <key>CFBundleDisplayName</key><string>Biosphere Dev</string>
  <key>CFBundleIdentifier</key><string>app.biosphere.dev</string>
  <key>CFBundleExecutable</key><string>Biosphere</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$(cat VERSION)-dev</string>
  <key>CFBundleVersion</key><string>0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Biosphere Dev watches Downloads for returned papers.</string>
</dict></plist>
PLIST
  if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    local iconset; iconset=$(mktemp -d)/Biosphere.iconset
    swift scripts/make_icon.swift "$iconset" && iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  fi
}

build() {
  # --skip-update/--disable-index-store skip ~5 s of package planning and indexing on every build.
  local out; out=$(swift build --skip-update --disable-index-store 2>&1); local code=$?
  print -r -- "$out" | grep -E "error:|Build complete" | grep -v "^\s" | tail -6
  return $code
}

install_binary() {
  cp .build/debug/Biosphere "$APP/Contents/MacOS/Biosphere"
  # Quick ad-hoc signature with a fixed identity requirement: macOS permissions (Downloads, Accessibility)
  # stick between rebuilds, and it takes ~0.3 s instead of 5–30 s with the keychain certificate.
  codesign --force --sign - -r='designated => identifier "app.biosphere.dev"' "$APP" >/dev/null 2>&1
}

launch() {
  if [[ -n "$PID" ]]; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  BIOSPHERE_RESOURCES="$PWD/Resources" "$APP/Contents/MacOS/Biosphere" &
  PID=$!
  echo "▶ Biosphere Dev is running. Save a .swift file to reload; ⌘R in the app reloads prompts/skills/bank."
}

cleanup() { [[ -n "$PID" ]] && kill "$PID" 2>/dev/null; rm -f "$STAMP"; echo; exit 0 }
trap cleanup INT TERM

echo "Building Biosphere Dev…"
make_bundle
if build; then install_binary; launch; else echo "✗ Build failed. Fix the error above and save; I'll retry."; fi
touch "$STAMP"

while sleep 0.7; do
  changed=$(find Sources -name '*.swift' -newer "$STAMP" 2>/dev/null | head -1)
  [[ -z "$changed" ]] && continue
  sleep 0.3; touch "$STAMP"            # let editors finish writing multi-file saves
  echo "⟳ ${changed#Sources/Biosphere/} changed. Rebuilding…"
  start=$SECONDS
  if build; then install_binary; launch; echo "✓ Live in $((SECONDS - start))s"
  else echo "✗ Build failed. Fix the error above and save again."; fi
done
