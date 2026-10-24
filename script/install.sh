#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPLACE=0
case "${1:-}" in
    '') ;;
    --replace) REPLACE=1 ;;
    -h|--help)
        printf 'Aufruf: %s [--replace]\n' "$0"
        printf 'Verschiebt den geprüften Build nach /Applications. Startet kein Spiel.\n'
        exit 0 ;;
    *) printf 'Unbekannte Option.\n' >&2; exit 2 ;;
esac
[[ "$#" -le 1 ]] || { printf 'Zu viele Optionen.\n' >&2; exit 2; }
di2_require_idle

python3 - "$DI2_BUILT_APP" "/Applications/$DI2_APP_NAME" "$REPLACE" <<'PY'
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

source, destination = map(Path, sys.argv[1:3])
replace = sys.argv[3] == '1'
identifier = 'local.deadisland2.launcher'

def inspect(path):
    if path.is_symlink() or not path.is_dir():
        raise SystemExit(f'Keine reguläre Launcher-App: {path}')
    info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != identifier:
        raise SystemExit(f'Fremde App wird nicht ersetzt: {path}')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(path)], check=True)

inspect(source)
if destination.exists() or destination.is_symlink():
    if not replace:
        raise SystemExit('Launcher bereits installiert. Bewusst mit --replace erneut ausführen.')
    inspect(destination)
if source.stat().st_dev != destination.parent.stat().st_dev:
    raise SystemExit('Build und /Applications müssen auf demselben Dateisystem liegen. DI2_BUILD_DIR entsprechend setzen.')

exchange = Path(tempfile.mkdtemp(prefix='.di2-launcher-swap-', dir=destination.parent))
previous = exchange / 'previous.app'
previous_saved = False
candidate_moved = False
success = False
try:
    if destination.exists():
        os.rename(destination, previous)
        previous_saved = True
    os.rename(source, destination)
    candidate_moved = True
    inspect(destination)
    success = True
except BaseException:
    if candidate_moved:
        os.rename(destination, source)
    if previous_saved:
        os.rename(previous, destination)
    raise
finally:
    if success:
        shutil.rmtree(exchange)
    elif not any(exchange.iterdir()):
        exchange.rmdir()
    else:
        print(f'Vorherige App zur Wiederherstellung erhalten: {exchange}', file=sys.stderr)
print(f'Installiert: {destination}')
PY
