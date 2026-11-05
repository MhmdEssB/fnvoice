#!/bin/bash
# Builds FnVoice without Xcode and produces build/FnVoice.app (local signature).
# Usage: bash build.sh            -> builds build/FnVoice.app
#         bash build.sh --install  -> builds, then replaces /Applications/FnVoice.app
set -euo pipefail

cd "$(dirname "$0")"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="build"
APP="$OUT/FnVoice.app"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS"

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find FnVoice -name '*.swift' | sort)

for ARCH in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library \
        -target "$ARCH-apple-macos14.0" -sdk "$SDK" \
        "${SOURCES[@]}" -o "$OUT/FnVoice-$ARCH"
done
lipo -create "$OUT/FnVoice-arm64" "$OUT/FnVoice-x86_64" -output "$APP/Contents/MacOS/FnVoice"
rm "$OUT/FnVoice-arm64" "$OUT/FnVoice-x86_64"

cp FnVoice/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp FnVoice/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R FnVoice/Resources/en.lproj FnVoice/Resources/fr.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# The identifier and designated requirement are fixed, so macOS keeps the
# microphone, audio capture and Accessibility permissions across rebuilds.
codesign --force --sign - --identifier com.mhmdessb.fnvoice -r='designated => identifier "com.mhmdessb.fnvoice"' --entitlements FnVoice/FnVoice.entitlements "$APP"

echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x FnVoice 2>/dev/null || true
    sleep 1
    rm -rf /Applications/FnVoice.app
    cp -R "$APP" /Applications/FnVoice.app
    open /Applications/FnVoice.app
    echo "Installed and relaunched: /Applications/FnVoice.app"
fi
