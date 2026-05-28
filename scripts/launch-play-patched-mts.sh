#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export MTS_DEV_MODE=true
export MTS_MOD_DIR="${MTS_MOD_DIR:-/tmp/multi-team-support}"
export AUTO_CLAIM="${AUTO_CLAIM:-true}"

exec "$ROOT/scripts/launch-play.sh" "$@"
