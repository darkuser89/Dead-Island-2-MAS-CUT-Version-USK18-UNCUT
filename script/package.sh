#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

[[ "$#" == 0 ]] || { printf 'Aufruf: %s\n' "$0" >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { printf 'Die App wird unter macOS paketiert.\n' >&2; exit 1; }
APP="$DI2_BUILT_APP"
[[ -d "$APP" && ! -L "$APP" ]] || { printf 'Zuerst ./script/build.sh ausführen.\n' >&2; exit 1; }
IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
[[ "$IDENTIFIER" == local.deadisland2.launcher ]] || { printf 'Keine Launcher-App.\n' >&2; exit 1; }
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { printf 'Ungültige App-Version.\n' >&2; exit 1; }
[[ -f "$APP/Contents/Resources/LICENSE" && -f "$APP/Contents/Resources/README.md" ]]
/usr/bin/codesign --verify --strict "$APP"
for binary in "$APP/Contents/MacOS/Launcher" "$APP/Contents/Resources/RuntimeIdentity.dylib"; do
    [[ "$(/usr/bin/lipo -archs "$binary")" == arm64 ]]
done

STAGE="$(mktemp -d "$DI2_BUILD_ROOT/.package-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ARCHIVE="Dead-Island-2-Uncut-macOS-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$ARCHIVE"

# Verify the actual distributable after extracting it, including executable
# permissions and sealed resources. No game is needed or started.
/usr/bin/ditto -x -k "$STAGE/$ARCHIVE" "$STAGE/unpacked"
UNPACKED="$STAGE/unpacked/$DI2_APP_NAME"
/usr/bin/codesign --verify --strict "$UNPACKED"
[[ -x "$UNPACKED/Contents/MacOS/Launcher" ]]
"$UNPACKED/Contents/MacOS/Launcher" --game-path >/dev/null
(
    cd "$STAGE"
    /usr/bin/shasum -a 256 "$ARCHIVE" >"$ARCHIVE.sha256"
    /usr/bin/shasum -a 256 -c "$ARCHIVE.sha256"
)

OUTPUT="$DI2_BUILD_ROOT/release"
[[ ! -L "$OUTPUT" ]] || { printf 'Releaseziel darf kein Symlink sein.\n' >&2; exit 1; }
mkdir -p "$OUTPUT"
mv "$STAGE/$ARCHIVE" "$STAGE/$ARCHIVE.sha256" "$OUTPUT/"
printf 'Geprüfter Download:\n%s\n' "$OUTPUT/$ARCHIVE"
