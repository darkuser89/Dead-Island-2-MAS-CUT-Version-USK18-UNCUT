#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only

DI2_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Only used for optional build-time validation/icon import, not game selection
# by the launcher. The running launcher always uses its adjacent app.
DI2_GAME_APP="${DI2_GAME_APP:-/Applications/DeadIsland2.app}"
DI2_APP_NAME="Dead Island 2 Uncut.app"

if ! command -v python3 >/dev/null 2>&1; then
    printf 'Python 3 wird für die Pfad- und Prozessprüfungen benötigt.\n' >&2
    exit 1
fi

# Resolve paths without creating build files inside the checkout.
DI2_BUILD_ROOT="$(python3 - "$DI2_SOURCE_ROOT" "${DI2_BUILD_DIR:-$HOME/Library/Developer/DeadIsland2UncutLauncher}" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).resolve()
build = Path(sys.argv[2]).expanduser().resolve()
if build == source or source in build.parents:
    raise SystemExit('DI2_BUILD_DIR muss außerhalb des Quellcodeordners liegen.')
print(build)
PY
)"
DI2_BUILT_APP="$DI2_BUILD_ROOT/$DI2_APP_NAME"

di2_require_idle() {
    python3 - "$DI2_GAME_APP/Contents/MacOS/DeadIsland2" "$DI2_BUILT_APP/Contents/MacOS/Launcher" "/Applications/$DI2_APP_NAME/Contents/MacOS/Launcher" <<'PY'
import subprocess
import sys
result = subprocess.run(['/bin/ps', '-ww', '-axo', 'pid=,comm='], capture_output=True, text=True)
if result.returncode:
    raise SystemExit('Prozessstatus nicht lesbar; sicherer Vorgang abgebrochen.')
targets = set(sys.argv[1:])
for line in result.stdout.splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) == 2 and fields[1] in targets:
        raise SystemExit('Bitte zuerst die App-Store-Spielinstanz und den Starthelfer regulär beenden.')
PY
}
