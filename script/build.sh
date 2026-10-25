#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

WITH_GAME_ICON=0
VALIDATE_GAME=0
for argument in "$@"; do
    case "$argument" in
        --with-game-icon) WITH_GAME_ICON=1 ;;
        --validate-game) VALIDATE_GAME=1 ;;
        -h|--help)
            printf 'Aufruf: %s [--with-game-icon] [--validate-game]\n' "$0"
            printf 'Baut und testet den Launcher. Installiert oder startet kein Spiel.\n'
            exit 0 ;;
        *) printf 'Unbekannte Option: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
    printf 'Der native Build und Test benötigen macOS auf Apple Silicon.\n' >&2
    exit 1
}
xcrun --find clang >/dev/null
di2_require_idle
mkdir -p "$DI2_BUILD_ROOT"
[[ ! -L "$DI2_BUILT_APP" ]] || { printf 'Buildziel darf kein Symlink sein.\n' >&2; exit 1; }
if [[ -e "$DI2_BUILT_APP" ]]; then
    EXISTING_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$DI2_BUILT_APP/Contents/Info.plist")"
    [[ "$EXISTING_ID" == local.deadisland2.launcher ]] || {
        printf 'Buildziel ist keine von diesem Projekt erzeugte Launcher-App.\n' >&2
        exit 1
    }
fi

STAGE="$(mktemp -d "$DI2_BUILD_ROOT/.build-stage.XXXXXX")"
LOCK="$DI2_BUILD_ROOT/.build.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    rmdir "$STAGE"
    printf 'Ein Build läuft bereits, oder eine verwaiste .build.lock liegt vor.\n' >&2
    exit 1
fi
BUILD_COMMITTED=0
cleanup() {
    if [[ -e "$STAGE/previous.app" && "$BUILD_COMMITTED" != 1 ]]; then
        printf 'Vorherigen Build zur Wiederherstellung erhalten: %s\n' "$STAGE/previous.app" >&2
    else
        rm -rf "$STAGE"
    fi
    rmdir "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

APP="$STAGE/$DI2_APP_NAME"
TEST_ROOT="$STAGE/runtime-tests"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TEST_ROOT/RuntimeProbe.app/Contents/MacOS"
COMMON_FLAGS=(-arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O1 -Wall -Wextra -Werror -I"$DI2_SOURCE_ROOT/Sources")

xcrun clang "${COMMON_FLAGS[@]}" -dynamiclib \
    -framework Foundation -framework CloudKit -framework Security \
    "$DI2_SOURCE_ROOT/Sources/RuntimeIdentity.m" -o "$APP/Contents/Resources/RuntimeIdentity.dylib"
/usr/bin/codesign --force --sign - --timestamp=none "$APP/Contents/Resources/RuntimeIdentity.dylib"

xcrun clang "${COMMON_FLAGS[@]}" -dynamiclib -framework Foundation \
    -install_name @rpath/libBoundaryObserver.dylib \
    "$DI2_SOURCE_ROOT/Tests/BoundaryObserver.m" -o "$TEST_ROOT/libBoundaryObserver.dylib"
xcrun clang "${COMMON_FLAGS[@]}" -framework Foundation \
    "$DI2_SOURCE_ROOT/Tests/RuntimeProbe.m" -L"$TEST_ROOT" -lBoundaryObserver \
    -Wl,-rpath,@executable_path/../../.. -o "$TEST_ROOT/RuntimeProbe.app/Contents/MacOS/RuntimeProbe"
cp "$DI2_SOURCE_ROOT/Tests/Info.plist" "$TEST_ROOT/RuntimeProbe.app/Contents/Info.plist"
BEFORE="$(/usr/bin/shasum -a 256 "$TEST_ROOT/RuntimeProbe.app/Contents/Info.plist")"
DYLD_INSERT_LIBRARIES="$APP/Contents/Resources/RuntimeIdentity.dylib" \
    "$TEST_ROOT/RuntimeProbe.app/Contents/MacOS/RuntimeProbe"
AFTER="$(/usr/bin/shasum -a 256 "$TEST_ROOT/RuntimeProbe.app/Contents/Info.plist")"
[[ "$BEFORE" == "$AFTER" ]]

xcrun clang "${COMMON_FLAGS[@]}" -framework AppKit -framework Security \
    "$DI2_SOURCE_ROOT/Sources/Launcher.m" -o "$APP/Contents/MacOS/Launcher"
cp "$DI2_SOURCE_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$DI2_SOURCE_ROOT/LICENSE" "$DI2_SOURCE_ROOT/README.md" "$APP/Contents/Resources/"
if [[ "$WITH_GAME_ICON" == 1 ]]; then
    ICON="$DI2_GAME_APP/Contents/Resources/DeadIsland.icns"
    [[ -f "$ICON" ]] || { printf 'Das lokale Spiel-Icon fehlt: %s\n' "$ICON" >&2; exit 1; }
    cp "$ICON" "$APP/Contents/Resources/GameIcon.icns"
    /usr/bin/plutil -insert CFBundleIconFile -string GameIcon "$APP/Contents/Info.plist"
fi
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
python3 "$DI2_SOURCE_ROOT/Tests/test_location.py" "$APP" "$TEST_ROOT"
if [[ "$VALIDATE_GAME" == 1 ]]; then
    "$APP/Contents/MacOS/Launcher" --validate-only "$DI2_GAME_APP"
fi

# Retain the previous verified build until the replacement is ready.
python3 - "$APP" "$DI2_BUILT_APP" "$STAGE/previous.app" <<'PY'
from pathlib import Path
import os
import sys
candidate, target, previous = map(Path, sys.argv[1:])
had_previous = target.exists()
if had_previous:
    os.rename(target, previous)
try:
    os.rename(candidate, target)
except BaseException:
    if had_previous:
        os.rename(previous, target)
    raise
PY
BUILD_COMMITTED=1
printf 'Build und isolierter Laufzeittest erfolgreich:\n%s\n' "$DI2_BUILT_APP"
