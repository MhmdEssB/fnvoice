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

# 1. On-device engine (Parakeet v3 through FluidAudio), built by SwiftPM as a dynamic library.
#    Apple silicon only: Intel Macs have no Neural Engine.
(cd LocalASR && swift build -c release --arch arm64)
LIBDIR="LocalASR/.build/arm64-apple-macosx/release"
[[ -f "$LIBDIR/libParakeetKit.dylib" ]] || LIBDIR="LocalASR/.build/release"
INTERFACE="$(find LocalASR/.build -path '*arm64*' -name 'ParakeetKit.swiftinterface' -print -quit)"
[[ -n "$INTERFACE" ]] || { echo "ParakeetKit interface not found (was LocalASR built?)" >&2; exit 1; }
# The app imports ParakeetKit through its stable interface: it does not need FluidAudio's modules.
mkdir -p "$OUT/modules/ParakeetKit.swiftmodule"
cp "$INTERFACE" "$OUT/modules/ParakeetKit.swiftmodule/arm64-apple-macos.swiftinterface"

# 2. The app
xcrun swiftc -O -parse-as-library \
    -target "arm64-apple-macos14.0" -sdk "$SDK" \
    -I "$OUT/modules" -L "$LIBDIR" -lParakeetKit \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${SOURCES[@]}" -o "$APP/Contents/MacOS/FnVoice"
mkdir -p "$APP/Contents/Frameworks"
cp "$LIBDIR/libParakeetKit.dylib" "$APP/Contents/Frameworks/"
codesign --force --sign - "$APP/Contents/Frameworks/libParakeetKit.dylib"
rm -rf "$OUT/modules"

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
