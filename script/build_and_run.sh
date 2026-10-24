#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--build-only" ]]; then
    shift
    exec "$SCRIPT_DIR/build.sh" "$@"
fi

"$SCRIPT_DIR/build.sh" "$@"
"$SCRIPT_DIR/install.sh" --replace
/usr/bin/open -n "/Applications/Dead Island 2 Uncut.app"
