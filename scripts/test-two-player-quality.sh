#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FACTORIO="${FACTORIO:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
MTS_MOD_DIR="${MTS_MOD_DIR:-}"
MTS_MOD_ZIP="${MTS_MOD_ZIP:-}"
WORK_DIR="${WORK_DIR:-/tmp/mts-expanse-two-client-quality-smoke}"
PORT="${PORT:-34217}"
CLIENT_A_NAME="${CLIENT_A_NAME:-MTSClientA}"
CLIENT_B_NAME="${CLIENT_B_NAME:-MTSClientB}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-420}"
AUTO_CLAIM="${AUTO_CLAIM:-true}"
STEAM_PLAYER_DATA="${STEAM_PLAYER_DATA:-}"
STEAM_PLAYER_DATA_BACKUP="${STEAM_PLAYER_DATA_BACKUP:-$WORK_DIR/steam-player-data.backup.json}"

MOD_NAME="$(python3 -c 'import json; print(json.load(open("info.json"))["name"])')"
VERSION="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])')"
MTS_VERSION=""
PACKAGE_NAME="${MOD_NAME}_${VERSION}"
PROBE="mts-expanse-two-client-probe_0.1.0"
ACTIVE_MTS_MOD_DIR="$MTS_MOD_DIR"

FACTORIO_CONTENTS="$(cd "$(dirname "$FACTORIO")/.." && pwd)"
READ_DATA="${READ_DATA:-$FACTORIO_CONTENTS/data}"
SERVER_WRITE_DATA="$WORK_DIR/server/write-data"
SERVER_CONFIG="$WORK_DIR/server/config.ini"
CLIENT_A_WRITE_DATA="$WORK_DIR/client-a/write-data"
CLIENT_A_CONFIG="$WORK_DIR/client-a/config.ini"
CLIENT_B_WRITE_DATA="$WORK_DIR/client-b/write-data"
CLIENT_B_CONFIG="$WORK_DIR/client-b/config.ini"
MODS="$WORK_DIR/mods"
SAVE="$WORK_DIR/server/saves/two-player-quality.zip"
SERVER_SETTINGS="$WORK_DIR/server-settings.json"
SERVER_LOG="$WORK_DIR/server.log"
CLIENT_A_LOG="$WORK_DIR/client-a.log"
CLIENT_B_LOG="$WORK_DIR/client-b.log"
OK_FILE="$SERVER_WRITE_DATA/script-output/mts-expanse-two-client-smoke-ok.txt"
PENDING_FILE="$SERVER_WRITE_DATA/script-output/mts-expanse-two-client-smoke-pending.txt"

server_pid=""
client_a_pid=""
client_b_pid=""

log() {
    printf '\n==> %s\n' "$*"
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

cleanup() {
    set +e
    if [[ -n "${client_b_pid:-}" ]]; then kill "$client_b_pid" 2>/dev/null; fi
    if [[ -n "${client_a_pid:-}" ]]; then kill "$client_a_pid" 2>/dev/null; fi
    if [[ -n "${server_pid:-}" ]]; then kill "$server_pid" 2>/dev/null; fi
    wait "$client_b_pid" 2>/dev/null
    wait "$client_a_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
    restore_steam_player_data
}

trap cleanup EXIT

if [[ ! -x "$FACTORIO" ]]; then
    echo "Factorio binary not found or not executable: $FACTORIO" >&2
    exit 1
fi

if [[ -n "$MTS_MOD_ZIP" ]]; then
    echo "scripts/test-two-player-quality.sh patches an unpacked local MTS checkout for auto-claim." >&2
    echo "Use scripts/launch-play.sh for official zipped MTS player testing." >&2
    exit 1
fi

if [[ -z "$MTS_MOD_DIR" ]]; then
    echo "Set MTS_MOD_DIR to an unpacked multi-team-support checkout for patched local smoke testing." >&2
    exit 1
fi

if [[ ! -f "$MTS_MOD_DIR/info.json" ]]; then
    echo "multi-team-support source not found at: $MTS_MOD_DIR" >&2
    echo "Set MTS_MOD_DIR to an unpacked multi-team-support checkout for patched local smoke testing." >&2
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

write_mod_list() {
    cat > "$MODS/mod-list.json" <<EOF
{
  "mods": [
    {"name": "base", "enabled": true},
    {"name": "elevated-rails", "enabled": false},
    {"name": "quality", "enabled": true},
    {"name": "space-age", "enabled": false},
    {"name": "multi-team-support", "enabled": true},
    {"name": "$MOD_NAME", "enabled": true},
    {"name": "mts-expanse-two-client-probe", "enabled": true}
  ]
}
EOF
}

write_server_settings() {
    cat > "$SERVER_SETTINGS" <<'EOF'
{
  "name": "MTS Expanse Two Client Quality Smoke",
  "description": "Local MTS Expanse two-client Quality smoke test",
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

write_probe_mod() {
    local dest="$MODS/$PROBE"
    mkdir -p "$dest"
    cat > "$dest/info.json" <<EOF
{
  "name": "mts-expanse-two-client-probe",
  "version": "0.1.0",
  "title": "MTS Expanse Two Client Probe",
  "author": "local",
  "factorio_version": "2.0",
  "dependencies": ["base", "quality", "multi-team-support", "$MOD_NAME"]
}
EOF
    cat > "$dest/control.lua" <<'EOF'
local OK_FILE = 'mts-expanse-two-client-smoke-ok.txt'
local PENDING_FILE = 'mts-expanse-two-client-smoke-pending.txt'

local function write(path, msg)
    helpers.write_file(path, msg .. '\n', false)
end

local function pending(msg)
    write(PENDING_FILE, 'tick=' .. game.tick .. ' ' .. msg)
end

local function fail(msg)
    write(PENDING_FILE, 'FAILED tick=' .. game.tick .. ' ' .. msg)
    error('[two-client-probe] ' .. msg)
end

local function append_children(element, out)
    if not (element and element.valid) then return end
    out[#out + 1] = element
    for _, child in pairs(element.children or {}) do
        append_children(child, out)
    end
end

local function has_expanse_buttons(player)
    local elements = {}
    append_children(player.gui.top, elements)
    local stats = false
    local missions = false
    for _, element in pairs(elements) do
        if element.type == 'sprite-button' and element.sprite == 'item/requester-chest' then
            stats = true
        elseif element.type == 'sprite-button' and element.sprite == 'item/rocket-part' then
            missions = true
        end
    end
    return stats and not missions
end

local function first_named_child(root, name)
    if not (root and root.valid) then return nil end
    if root.name == name then return root end
    for _, child in pairs(root.children or {}) do
        local found = first_named_child(child, name)
        if found then return found end
    end
    return nil
end

local function connected_players()
    local players = {}
    for _, player in pairs(game.players) do
        if player.connected then
            players[#players + 1] = player
        end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    return players
end

local function check_player(player)
    if not player.force.name:match('^team%-%d+$') then
        return nil, player.name .. ' not on team force: ' .. player.force.name
    end
    if not player.admin then
        return nil, player.name .. ' was not promoted to admin as an MTS team host'
    end
    if player.controller_type ~= defines.controllers.character then
        return nil, player.name .. ' not in character controller: ' .. tostring(player.controller_type)
    end
    if not (player.character and player.character.valid) then
        return nil, player.name .. ' has no valid character'
    end
    local state = remote.call('mts_expanse', 'get_state', player.force.name)
    if type(state) ~= 'table' then
        return nil, player.name .. ' missing mts_expanse state for ' .. player.force.name
    end
    local expected_surface = player.force.name .. '-expanse'
    if state.mode ~= 'vanilla' then
        return nil, player.name .. ' expected vanilla mode, got ' .. tostring(state.mode)
    end
    if type(state.settings) ~= 'table' then
        return nil, player.name .. ' missing settings'
    end
    if state.settings.sync_cell_content ~= true then
        return nil, player.name .. ' sync cell content setting disabled'
    end
    if state.settings.sync_invasions ~= true then
        return nil, player.name .. ' sync invasions setting disabled'
    end
    if state.active_surface_name ~= expected_surface then
        return nil, player.name .. ' wrong state surface: ' .. tostring(state.active_surface_name)
    end
    if player.surface.name ~= expected_surface then
        return nil, player.name .. ' on wrong surface: ' .. player.surface.name
    end
    if player.character.surface.name ~= expected_surface then
        return nil, player.name .. ' character on wrong surface: ' .. player.character.surface.name
    end
    if remote.call('mts-v1', 'get_surface_owner', expected_surface) ~= player.force.name then
        return nil, player.name .. ' MTS owner mismatch for ' .. expected_surface
    end
    if not has_expanse_buttons(player) then
        return nil, player.name .. ' missing vanilla Expanse stats button or still has Space Missions button'
    end
    local chest_count = game.surfaces[expected_surface].count_entities_filtered{
        name = 'requester-chest',
        force = 'neutral'
    }
    if chest_count < 1 then
        return nil, player.name .. ' has no hungry chest on ' .. expected_surface
    end
    return string.format('%s,%s,%s,%s,%d,%s',
        player.name,
        player.force.name,
        expected_surface,
        state.active_surface_name,
        chest_count,
        state.mode)
end

script.on_init(function()
    if not script.active_mods['quality'] then
        fail('quality mod is not active')
    end
    if script.active_mods['space-age'] then
        fail('space-age must be disabled for vanilla + quality smoke')
    end
end)

script.on_nth_tick(30, function()
    local players = connected_players()
    if #players < 2 then
        pending('waiting for two connected players; connected=' .. #players)
        return
    end

    local rows = {}
    for _, player in pairs(players) do
        if player.force.name == 'spectator' or player.surface.name == 'landing-pen' then
            pending(player.name .. ' is waiting in Landing Pen; click Start a new team')
            return
        end
        local row, err = check_player(player)
        if not row then
            pending(err)
            return
        end
        rows[#rows + 1] = row
    end

    if rows[1]:match(',team%-(%d+),') == rows[2]:match(',team%-(%d+),') then
        pending('players are not on separate teams')
        return
    end

    write(OK_FILE, table.concat(rows, '\n'))
    script.on_nth_tick(30, nil)
end)
EOF
}

prepare_mts_mod() {
    ACTIVE_MTS_MOD_DIR="$MTS_MOD_DIR"
    if [[ "$AUTO_CLAIM" != "true" ]]; then
        return
    fi

    ACTIVE_MTS_MOD_DIR="$WORK_DIR/multi-team-support-autoclaim"
    rm -rf "$ACTIVE_MTS_MOD_DIR"
    mkdir -p "$ACTIVE_MTS_MOD_DIR"
    cp -R "$MTS_MOD_DIR"/. "$ACTIVE_MTS_MOD_DIR"/
    LC_ALL=C LC_CTYPE=C LANG=C perl -0pi -e 's/landing_pen_enabled\s*=\s*true/landing_pen_enabled              = false/' \
        "$ACTIVE_MTS_MOD_DIR/scripts/admin_flags.lua"
}

run_factorio() {
    "$FACTORIO" --config "$SERVER_CONFIG" --mod-directory "$MODS" "${@:1}"
}

wait_for_log() {
    local pattern="$1"
    local deadline=$((SECONDS + 90))
    until rg -q "$pattern" "$SERVER_LOG" "$WORK_DIR/server.stdout.log" 2>/dev/null; do
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for server log pattern: $pattern" >&2
            tail -120 "$SERVER_LOG" >&2 || true
            exit 1
        fi
        sleep 1
    done
}

wait_for_client_identity() {
    local expected="$1"
    local unexpected="$2"
    local deadline=$((SECONDS + 180))
    until rg -q "\\[JOIN\\] $expected joined|$expected claimed slot|$expected force=team-" "$SERVER_LOG" "$SERVER_WRITE_DATA/factorio-current.log" 2>/dev/null; do
        if [[ -n "$unexpected" ]] && rg -q "\\[JOIN\\] $unexpected joined|$unexpected claimed slot|$unexpected force=team-" "$SERVER_LOG" "$SERVER_WRITE_DATA/factorio-current.log" 2>/dev/null; then
            echo "Saw $unexpected while waiting for $expected; Steam player-data was switched too early or not restored." >&2
            tail -120 "$SERVER_LOG" >&2 || true
            exit 1
        fi
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for $expected to join with the expected identity." >&2
            tail -160 "$SERVER_LOG" >&2 || true
            exit 1
        fi
        sleep 1
    done
}

wait_for_ok() {
    local deadline=$((SECONDS + TIMEOUT_SECONDS))
    until [[ -f "$OK_FILE" ]]; do
        if (( SECONDS > deadline )); then
            echo "Timed out waiting for two-client OK file." >&2
            if [[ -f "$PENDING_FILE" ]]; then
                echo "Last probe status:" >&2
                cat "$PENDING_FILE" >&2
            fi
            echo "Server log tail:" >&2
            tail -160 "$SERVER_LOG" >&2 || true
            echo "Client A log tail:" >&2
            tail -80 "$CLIENT_A_LOG" >&2 || true
            echo "Client B log tail:" >&2
            tail -80 "$CLIENT_B_LOG" >&2 || true
            exit 1
        fi
        if [[ -f "$PENDING_FILE" ]]; then
            printf '\r%s' "$(cat "$PENDING_FILE")"
        fi
        sleep 2
    done
    printf '\n'
}

set_factorio_username() {
    local name="$1"
    jq --arg user "$name" \
        '.username = $user | .["service-username"] = $user | del(.["service-token"])' \
        "$STEAM_PLAYER_DATA_BACKUP" > "$STEAM_PLAYER_DATA"
    touch "$STEAM_PLAYER_DATA"
}

rm -rf "$WORK_DIR"
mkdir -p "$MODS" "$WORK_DIR/server/saves" "$WORK_DIR/client-a" "$WORK_DIR/client-b"
write_config "$SERVER_CONFIG" "$SERVER_WRITE_DATA"
write_config "$CLIENT_A_CONFIG" "$CLIENT_A_WRITE_DATA"
write_config "$CLIENT_B_CONFIG" "$CLIENT_B_WRITE_DATA"
write_mod_list
write_server_settings
prepare_mts_mod
ln -s "$ROOT" "$MODS/$PACKAGE_NAME"
ln -s "$ACTIVE_MTS_MOD_DIR" "$MODS/multi-team-support_$MTS_VERSION"
write_probe_mod
cp -p "$STEAM_PLAYER_DATA" "$STEAM_PLAYER_DATA_BACKUP"

if [[ "$AUTO_CLAIM" == "true" ]]; then
    log "Using temporary MTS copy with Landing Pen default disabled for auto-claim"
fi

log "Creating vanilla + Quality save"
run_factorio --create "$SAVE" >/dev/null

log "Starting local server on 127.0.0.1:$PORT"
"$FACTORIO" \
    --config "$SERVER_CONFIG" \
    --mod-directory "$MODS" \
    --start-server "$SAVE" \
    --server-settings "$SERVER_SETTINGS" \
    --bind "127.0.0.1:$PORT" \
    --console-log "$SERVER_LOG" \
    >"$WORK_DIR/server.stdout.log" 2>&1 &
server_pid=$!
wait_for_log 'Hosting game at IP ADDRESS|Info ServerMultiplayerManager.cpp'

log "Launching client A as $CLIENT_A_NAME"
set_factorio_username "$CLIENT_A_NAME"
SteamAppId=427520 SteamGameId=427520 "$FACTORIO" \
    --config "$CLIENT_A_CONFIG" \
    --mod-directory "$MODS" \
    --mp-connect "127.0.0.1:$PORT" \
    --disable-audio \
    --window-size 960x540 \
    --force-graphics-preset low \
    >"$CLIENT_A_LOG" 2>&1 &
client_a_pid=$!
wait_for_client_identity "$CLIENT_A_NAME" "$CLIENT_B_NAME"

log "Launching client B as $CLIENT_B_NAME"
set_factorio_username "$CLIENT_B_NAME"
SteamAppId=427520 SteamGameId=427520 "$FACTORIO" \
    --config "$CLIENT_B_CONFIG" \
    --mod-directory "$MODS" \
    --mp-connect "127.0.0.1:$PORT" \
    --disable-audio \
    --window-size 960x540 \
    --force-graphics-preset low \
    >"$CLIENT_B_LOG" 2>&1 &
client_b_pid=$!
wait_for_client_identity "$CLIENT_B_NAME" ""
restore_steam_player_data

log "Waiting for two-player probe"
wait_for_ok

log "Two-player vanilla + Quality smoke passed"
cat "$OK_FILE"
