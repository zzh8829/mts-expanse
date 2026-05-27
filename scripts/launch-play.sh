#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FACTORIO="${FACTORIO:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
MTS_MOD_DIR="${MTS_MOD_DIR:-/tmp/multi-team-support}"
WORK_DIR="${WORK_DIR:-/tmp/mts-expanse-play}"
PORT="${PORT:-34217}"
CLIENT_A_NAME="${CLIENT_A_NAME:-MTSClientA}"
CLIENT_B_NAME="${CLIENT_B_NAME:-MTSClientB}"
AUTO_CLAIM="${AUTO_CLAIM:-false}"
MOD_SETUP="${MOD_SETUP:-vanilla-quality}"
DRY_RUN="${DRY_RUN:-false}"
RESET_SAVE="${RESET_SAVE:-true}"
WAIT_FOR_CLIENTS="${WAIT_FOR_CLIENTS:-$AUTO_CLAIM}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-360}"
STEAM_PLAYER_DATA="${STEAM_PLAYER_DATA:-}"
STEAM_PLAYER_DATA_BACKUP="${STEAM_PLAYER_DATA_BACKUP:-$WORK_DIR/steam-player-data.backup.json}"
PLAYER_PROBE_MARKER="MTS_EXPANSE_LAUNCH_PROBE"

MOD_NAME="$(python3 -c 'import json; print(json.load(open("info.json"))["name"])')"
VERSION="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])')"
MTS_VERSION=""
PACKAGE_NAME="${MOD_NAME}_${VERSION}"

FACTORIO_CONTENTS="$(cd "$(dirname "$FACTORIO")/.." && pwd)"
READ_DATA="${READ_DATA:-$FACTORIO_CONTENTS/data}"
MODS="$WORK_DIR/mods"
SERVER_CONFIG="$WORK_DIR/server/config.ini"
CLIENT_A_CONFIG="$WORK_DIR/client-a/config.ini"
CLIENT_B_CONFIG="$WORK_DIR/client-b/config.ini"
SERVER_WRITE_DATA="$WORK_DIR/server/write-data"
CLIENT_A_WRITE_DATA="$WORK_DIR/client-a/write-data"
CLIENT_B_WRITE_DATA="$WORK_DIR/client-b/write-data"
SERVER_SETTINGS="$WORK_DIR/server-settings.json"
SAVE="$WORK_DIR/server/saves/mts-expanse-${MOD_SETUP}.zip"
ACTIVE_MTS_MOD_DIR="$MTS_MOD_DIR"

case "$MOD_SETUP" in
    vanilla)
        MOD_ELEVATED=false
        MOD_QUALITY=false
        MOD_SPACE_AGE=false
        MOD_SETUP_LABEL="MTS + Expanse + vanilla"
        MOD_SETUP_SAVE_LABEL="vanilla"
        MOD_SETUP_ENABLED_MODS="none"
        MOD_SETUP_NOTE=""
        ;;
    vanilla-quality)
        MOD_ELEVATED=false
        MOD_QUALITY=true
        MOD_SPACE_AGE=false
        MOD_SETUP_LABEL="MTS + Expanse + vanilla + Quality"
        MOD_SETUP_SAVE_LABEL="vanilla + Quality"
        MOD_SETUP_ENABLED_MODS="quality"
        MOD_SETUP_NOTE=""
        ;;
    space-age)
        MOD_ELEVATED=true
        MOD_QUALITY=true
        MOD_SPACE_AGE=true
        MOD_SETUP_LABEL="MTS + Expanse + vanilla + Elevated Rails + Space Age"
        MOD_SETUP_SAVE_LABEL="vanilla + Elevated Rails + Space Age"
        MOD_SETUP_ENABLED_MODS="elevated-rails, quality, space-age"
        MOD_SETUP_NOTE="Quality is enabled because Space Age depends on it"
        ;;
    space-age-quality)
        MOD_ELEVATED=true
        MOD_QUALITY=true
        MOD_SPACE_AGE=true
        MOD_SETUP_LABEL="MTS + Expanse + vanilla + Elevated Rails + Space Age + Quality"
        MOD_SETUP_SAVE_LABEL="vanilla + Elevated Rails + Space Age + Quality"
        MOD_SETUP_ENABLED_MODS="elevated-rails, quality, space-age"
        MOD_SETUP_NOTE=""
        ;;
    *)
        echo "Unknown MOD_SETUP: $MOD_SETUP" >&2
        echo "Use one of: vanilla, vanilla-quality, space-age, space-age-quality" >&2
        exit 1
        ;;
esac

log() {
    printf '\n==> %s\n' "$*"
}

log_setup_summary() {
    log "Using mod setup: $MOD_SETUP ($MOD_SETUP_LABEL)"
    log "Enabled optional mods: $MOD_SETUP_ENABLED_MODS"
    log "Auto-claim Landing Pen: $AUTO_CLAIM"
    log "Wait for final player probe: $WAIT_FOR_CLIENTS"
    if [[ -n "$MOD_SETUP_NOTE" ]]; then
        log "$MOD_SETUP_NOTE"
    fi
}

detect_steam_player_data() {
    local steam_userdata="${STEAM_USERDATA_DIR:-$HOME/Library/Application Support/Steam/userdata}"
    [[ -d "$steam_userdata" ]] || return 1

    local matches=()
    while IFS= read -r -d '' path; do
        matches+=("$path")
    done < <(find "$steam_userdata" -path '*/427520/remote/player-data.json' -type f -print0 2>/dev/null)

    if ((${#matches[@]} == 0)); then
        return 1
    fi

    python3 - "${matches[@]}" <<'PY'
import os
import sys

print(max(sys.argv[1:], key=os.path.getmtime))
PY
}

restore_steam_player_data() {
    if [[ -n "$STEAM_PLAYER_DATA" && -f "$STEAM_PLAYER_DATA_BACKUP" ]]; then
        cp -p "$STEAM_PLAYER_DATA_BACKUP" "$STEAM_PLAYER_DATA"
        rm -f "$STEAM_PLAYER_DATA_BACKUP"
    fi
}

trap restore_steam_player_data EXIT

write_config() {
    local config="$1"
    local write_data="$2"
    mkdir -p "$write_data/config" "$write_data/saves" "$write_data/script-output" "$write_data/temp"
    cat > "$config" <<EOF
[path]
read-data=$READ_DATA
write-data=$write_data

[general]
locale=en

[other]
verbose-logging=true
EOF
}

render_mod_list() {
    cat <<EOF
{
  "mods": [
    {"name": "base", "enabled": true},
    {"name": "elevated-rails", "enabled": $MOD_ELEVATED},
    {"name": "quality", "enabled": $MOD_QUALITY},
    {"name": "space-age", "enabled": $MOD_SPACE_AGE},
    {"name": "multi-team-support", "enabled": true},
    {"name": "$MOD_NAME", "enabled": true}
  ]
}
EOF
}

write_mod_list() {
    render_mod_list > "$MODS/mod-list.json"
}

write_server_settings() {
    cat > "$SERVER_SETTINGS" <<'EOF'
{
  "name": "MTS Expanse Local Play",
  "description": "Local MTS Expanse play server",
  "tags": [],
  "max_players": 4,
  "visibility": {
    "public": false,
    "lan": false
  },
  "username": "",
  "password": "",
  "token": "",
  "game_password": "",
  "require_user_verification": false,
  "max_upload_in_kilobytes_per_second": 0,
  "ignore_player_limit_for_returning_players": false,
  "allow_commands": "true",
  "autosave_interval": 0,
  "autosave_slots": 1,
  "afk_autokick_interval": 0,
  "auto_pause": false,
  "auto_pause_when_players_connect": false,
  "only_admins_can_pause_the_game": false
}
EOF
}

prepare_mts_mod() {
    ACTIVE_MTS_MOD_DIR="$MTS_MOD_DIR"
    if [[ "$AUTO_CLAIM" != "true" ]]; then
        return
    fi

    ACTIVE_MTS_MOD_DIR="$WORK_DIR/multi-team-support-autoclaim"
    rm -rf "$ACTIVE_MTS_MOD_DIR"
    cp -R "$MTS_MOD_DIR" "$ACTIVE_MTS_MOD_DIR"
    LC_ALL=C LC_CTYPE=C LANG=C perl -0pi -e 's/landing_pen_enabled\s*=\s*true/landing_pen_enabled              = false/' \
        "$ACTIVE_MTS_MOD_DIR/scripts/admin_flags.lua"
}

backup_logs() {
    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"
    for log_file in \
        "$SERVER_WRITE_DATA/factorio-current.log" \
        "$CLIENT_A_WRITE_DATA/factorio-current.log" \
        "$CLIENT_B_WRITE_DATA/factorio-current.log" \
        "$WORK_DIR/server.stdout.log" \
        "$WORK_DIR/server-console.log"; do
        if [[ -f "$log_file" ]]; then
            mv "$log_file" "$log_file.$stamp.bak"
        fi
    done
}

kill_stack() {
    for session in mts-expanse-client-b mts-expanse-client-a mts-expanse-server; do
        tmux kill-session -t "$session" 2>/dev/null || true
    done

    local deadline=$((SECONDS + 90))
    while pgrep -af "$WORK_DIR" >/dev/null 2>&1; do
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for old MTS Expanse play processes to exit." >&2
            pgrep -af "$WORK_DIR" >&2 || true
            exit 1
        fi
        sleep 1
    done

    deadline=$((SECONDS + 30))
    while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
        if (( SECONDS > deadline )); then
            echo "Port $PORT is still busy." >&2
            lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
            exit 1
        fi
        sleep 1
    done
}

run_server_factorio() {
    "$FACTORIO" --config "$SERVER_CONFIG" --mod-directory "$MODS" "$@"
}

wait_for_server() {
    local deadline=$((SECONDS + 120))
    until [[ -f "$SERVER_WRITE_DATA/factorio-current.log" ]] && rg -q 'Hosting game at IP' "$SERVER_WRITE_DATA/factorio-current.log"; do
        if ! tmux has-session -t mts-expanse-server 2>/dev/null; then
            echo "Server session exited before hosting." >&2
            [[ -f "$SERVER_WRITE_DATA/factorio-current.log" ]] && tail -160 "$SERVER_WRITE_DATA/factorio-current.log" >&2 || true
            exit 1
        fi
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for server to host." >&2
            [[ -f "$SERVER_WRITE_DATA/factorio-current.log" ]] && tail -160 "$SERVER_WRITE_DATA/factorio-current.log" >&2 || true
            exit 1
        fi
        sleep 1
    done
}

wait_for_client_identity() {
    local expected="$1"
    local unexpected="${2:-}"
    local deadline=$((SECONDS + 180))
    local log_file="$SERVER_WRITE_DATA/factorio-current.log"
    until rg -q "\\[JOIN\\] $expected joined|$expected claimed slot|$expected force=team-" "$WORK_DIR/server-console.log" "$log_file" 2>/dev/null; do
        if [[ -n "$unexpected" ]] && rg -q "\\[JOIN\\] $unexpected joined|$unexpected claimed slot|$unexpected force=team-" "$WORK_DIR/server-console.log" "$log_file" 2>/dev/null; then
            echo "Saw $unexpected while waiting for $expected; Steam player-data was switched too early or not restored." >&2
            [[ -f "$log_file" ]] && tail -160 "$log_file" >&2 || true
            exit 1
        fi
        local sessions=(mts-expanse-server mts-expanse-client-a)
        if [[ "$expected" == "$CLIENT_B_NAME" ]]; then
            sessions+=(mts-expanse-client-b)
        fi
        for session in "${sessions[@]}"; do
            if ! tmux has-session -t "$session" 2>/dev/null; then
                echo "$session exited while waiting for $expected." >&2
                [[ -f "$log_file" ]] && tail -160 "$log_file" >&2 || true
                exit 1
            fi
        done
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for $expected to join with the expected identity." >&2
            [[ -f "$log_file" ]] && tail -220 "$log_file" >&2 || true
            exit 1
        fi
        sleep 1
    done
}

emit_player_probe() {
    local lua
    lua="local marker='$PLAYER_PROBE_MARKER'; for _,p in pairs(game.connected_players) do log('['..marker..'] '..p.name..' force='..p.force.name..' surface='..p.surface.name..' character='..tostring(p.character ~= nil)..' controller='..tostring(p.controller_type)) end"
    tmux send-keys -t mts-expanse-server "/sc $lua" C-m
}

wait_for_clients() {
    local deadline=$((SECONDS + TIMEOUT_SECONDS))
    local log_file="$SERVER_WRITE_DATA/factorio-current.log"
    local next_probe=0
    local lua_confirmed=false
    until rg -q "\\[$PLAYER_PROBE_MARKER\\] $CLIENT_A_NAME force=team-1 surface=team-1-expanse character=true" "$log_file" 2>/dev/null &&
        rg -q "\\[$PLAYER_PROBE_MARKER\\] $CLIENT_B_NAME force=team-2 surface=team-2-expanse character=true" "$log_file" 2>/dev/null; do
        for session in mts-expanse-server mts-expanse-client-a mts-expanse-client-b; do
            if ! tmux has-session -t "$session" 2>/dev/null; then
                echo "$session exited while waiting for clients." >&2
                [[ -f "$log_file" ]] && tail -180 "$log_file" >&2 || true
                exit 1
            fi
        done
        if (( SECONDS >= next_probe )); then
            emit_player_probe
            if [[ "$lua_confirmed" == "false" ]]; then
                sleep 1
                emit_player_probe
                lua_confirmed=true
            fi
            next_probe=$((SECONDS + 5))
        fi
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for clients on Expanse surfaces." >&2
            [[ -f "$log_file" ]] && tail -220 "$log_file" >&2 || true
            exit 1
        fi
        sleep 2
    done
}

set_factorio_username() {
    local name="$1"
    jq --arg user "$name" \
        '.username = $user | .["service-username"] = $user | del(.["service-token"])' \
        "$STEAM_PLAYER_DATA_BACKUP" > "$STEAM_PLAYER_DATA"
    touch "$STEAM_PLAYER_DATA"
}

if [[ "$DRY_RUN" == "true" ]]; then
    log_setup_summary
    log "Would create $MOD_SETUP_SAVE_LABEL play save at $SAVE"
    render_mod_list
    exit 0
fi

if [[ ! -x "$FACTORIO" ]]; then
    echo "Factorio binary not found or not executable: $FACTORIO" >&2
    exit 1
fi
if [[ ! -f "$MTS_MOD_DIR/info.json" ]]; then
    echo "multi-team-support source not found at: $MTS_MOD_DIR" >&2
    exit 1
fi
MTS_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MTS_MOD_DIR/info.json")"
if [[ -z "$STEAM_PLAYER_DATA" ]]; then
    STEAM_PLAYER_DATA="$(detect_steam_player_data || true)"
fi
if [[ ! -f "$STEAM_PLAYER_DATA" ]]; then
    echo "Steam player-data file not found. Set STEAM_PLAYER_DATA to your Steam Factorio player-data.json." >&2
    exit 1
fi

log "Stopping old play stack"
kill_stack

log "Preparing isolated play profiles"
log_setup_summary
mkdir -p "$MODS" "$WORK_DIR/server/saves" "$WORK_DIR/client-a" "$WORK_DIR/client-b"
write_config "$SERVER_CONFIG" "$SERVER_WRITE_DATA"
write_config "$CLIENT_A_CONFIG" "$CLIENT_A_WRITE_DATA"
write_config "$CLIENT_B_CONFIG" "$CLIENT_B_WRITE_DATA"
write_server_settings
prepare_mts_mod
if [[ "$AUTO_CLAIM" == "true" ]]; then
    log "Using temporary MTS copy with Landing Pen disabled for auto-claim"
else
    log "Using MTS Landing Pen menu; click Start a new team or join from the menu"
fi
rm -f "$MODS/$PACKAGE_NAME" "$MODS/multi-team-support_$MTS_VERSION"
ln -s "$ROOT" "$MODS/$PACKAGE_NAME"
ln -s "$ACTIVE_MTS_MOD_DIR" "$MODS/multi-team-support_$MTS_VERSION"
write_mod_list
backup_logs

if [[ "$RESET_SAVE" == "true" || ! -f "$SAVE" ]]; then
    log "Creating $MOD_SETUP_SAVE_LABEL play save"
    run_server_factorio --create "$SAVE" >/dev/null
    backup_logs
fi

log "Starting server on 127.0.0.1:$PORT"
tmux new-session -d -s mts-expanse-server \
    "exec '$FACTORIO' --config '$SERVER_CONFIG' --mod-directory '$MODS' --start-server '$SAVE' --server-settings '$SERVER_SETTINGS' --bind 127.0.0.1:$PORT --console-log '$WORK_DIR/server-console.log'"
wait_for_server

log "Launching $CLIENT_A_NAME"
cp -p "$STEAM_PLAYER_DATA" "$STEAM_PLAYER_DATA_BACKUP"
set_factorio_username "$CLIENT_A_NAME"
tmux new-session -d -s mts-expanse-client-a \
    "SteamAppId=427520 SteamGameId=427520 exec '$FACTORIO' --config '$CLIENT_A_CONFIG' --mod-directory '$MODS' --mp-connect 127.0.0.1:$PORT --disable-audio --window-size 960x540 --force-graphics-preset low"
wait_for_client_identity "$CLIENT_A_NAME" "$CLIENT_B_NAME"

log "Launching $CLIENT_B_NAME"
set_factorio_username "$CLIENT_B_NAME"
tmux new-session -d -s mts-expanse-client-b \
    "SteamAppId=427520 SteamGameId=427520 exec '$FACTORIO' --config '$CLIENT_B_CONFIG' --mod-directory '$MODS' --mp-connect 127.0.0.1:$PORT --disable-audio --window-size 960x540 --force-graphics-preset low"
wait_for_client_identity "$CLIENT_B_NAME" ""
restore_steam_player_data

if [[ "$WAIT_FOR_CLIENTS" == "true" ]]; then
    log "Waiting for clients on Expanse surfaces"
    wait_for_clients
fi

log "MTS Expanse play stack is running"
tmux list-panes -a -F '#{session_name} #{pane_pid} #{pane_current_command} #{pane_dead}' | rg 'mts-expanse'
