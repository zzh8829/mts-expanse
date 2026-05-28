#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${MTS_MOD_DIR:-}" ]]; then
    echo "Set MTS_MOD_DIR to an unpacked multi-team-support checkout for patched local testing." >&2
    exit 1
fi

export MTS_DEV_MODE=true
export AUTO_CLAIM="${AUTO_CLAIM:-true}"

exec "$ROOT/scripts/launch-play.sh" "$@"
