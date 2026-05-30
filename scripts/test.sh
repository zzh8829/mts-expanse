#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LUA_COMPILER="${LUA_COMPILER:-/opt/homebrew/opt/lua@5.4/bin/luac}"
FACTORIO="${FACTORIO:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
WORK_DIR="${WORK_DIR:-/tmp/mts-expanse-test}"

MOD_NAME="$(python3 -c 'import json; print(json.load(open("info.json"))["name"])' < /dev/null)"
VERSION="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])' < /dev/null)"
PACKAGE_NAME="${MOD_NAME}_${VERSION}"

FACTORIO_CONTENTS="$(cd "$(dirname "$FACTORIO")/.." && pwd)"
READ_DATA="${READ_DATA:-$FACTORIO_CONTENTS/data}"
WRITE_DATA="$WORK_DIR/write-data"
CONFIG="$WORK_DIR/config.ini"
SOURCE_MODS="$WORK_DIR/source-mods"
ZIP_MODS="$WORK_DIR/zip-mods"
PROBE_MODS="$WORK_DIR/probe-mods"
ZIP_PATH="$ROOT/../${PACKAGE_NAME}.zip"

log() {
    printf '\n==> %s\n' "$*"
}

write_config() {
    mkdir -p "$WRITE_DATA/config" "$WRITE_DATA/saves" "$WRITE_DATA/script-output" "$WRITE_DATA/temp"
    cat > "$CONFIG" <<EOF
[path]
read-data=$READ_DATA
write-data=$WRITE_DATA

[general]
locale=en

[other]
verbose-logging=true
EOF
}

write_mod_list() {
    local dest="$1"
    local optional="$2"
    local probe="${3:-false}"
    local probe_line=""
    if [[ "$probe" == "true" ]]; then
        probe_line=','
        probe_line+='
    {"name": "mts-expanse-test-probe", "enabled": true}'
    fi
    mkdir -p "$dest"
    if [[ "$optional" == "space-age" ]]; then
        cat > "$dest/mod-list.json" <<EOF
{
  "mods": [
    {"name": "base", "enabled": true},
    {"name": "elevated-rails", "enabled": true},
    {"name": "quality", "enabled": true},
    {"name": "space-age", "enabled": true},
    {"name": "$MOD_NAME", "enabled": true}$probe_line
  ]
}
EOF
    else
        cat > "$dest/mod-list.json" <<EOF
{
  "mods": [
    {"name": "base", "enabled": true},
    {"name": "elevated-rails", "enabled": false},
    {"name": "quality", "enabled": false},
    {"name": "space-age", "enabled": false},
    {"name": "$MOD_NAME", "enabled": true}$probe_line
  ]
}
EOF
    fi
}

write_probe_mod() {
    local dest="$1/mts-expanse-test-probe_0.1.0"
    mkdir -p "$dest"
    cat > "$dest/info.json" <<EOF
{
  "name": "mts-expanse-test-probe",
  "version": "0.1.0",
  "title": "MTS Expanse Test Probe",
  "author": "local",
  "factorio_version": "2.0",
  "dependencies": ["base", "$MOD_NAME"]
}
EOF
    cat > "$dest/control.lua" <<'EOF'
local function assert_state(label)
    local state = remote.call('mts_expanse', 'get_state')
    local expected_mode = script.active_mods['space-age'] and 'space-age' or 'vanilla'
    local expected_support = script.active_mods['space-age'] and 'space-age-surface-hub' or 'disabled'
    if type(state) ~= 'table' then
        error(label .. ': get_state did not return a table')
    end
    if not state.active_surface_index or not game.surfaces[state.active_surface_index] then
        error(label .. ': active Expanse surface is missing')
    end
    if state.mode ~= expected_mode then
        error(label .. ': wrong mode ' .. tostring(state.mode))
    end
    if state.mission_support_mode ~= expected_support then
        error(label .. ': wrong mission support mode ' .. tostring(state.mission_support_mode))
    end
    if state.space_missions_enabled ~= (script.active_mods['space-age'] and true or false) then
        error(label .. ': wrong space mission enabled state ' .. tostring(state.space_missions_enabled))
    end
    if script.active_mods['space-age'] and type(state.mission_levels) ~= 'table' then
        error(label .. ': mission levels table is missing')
    end
    if not script.active_mods['space-age'] and state.mission_levels ~= nil then
        error(label .. ': vanilla mode should not expose mission levels')
    end
    if type(state.settings) ~= 'table' then
        error(label .. ': settings table is missing')
    end
    if state.settings.cell_size ~= 15 then
        error(label .. ': unexpected cell size setting ' .. tostring(state.settings.cell_size))
    end
    if state.settings.sync_cell_content ~= true then
        error(label .. ': sync cell content setting should default true')
    end
    if state.settings.sync_invasions ~= true then
        error(label .. ': sync invasions setting should default true')
    end
    return state
end

local function first_hungry_chest(label)
    local state = assert_state(label)
    local surface = game.surfaces[state.active_surface_name]
    local container_info = state.containers and state.containers[1]
    if not (container_info and container_info.left_top) then
        error(label .. ': remote state did not expose hungry chest target')
    end
    local chest
    for _, candidate in pairs(surface.find_entities_filtered{name = 'requester-chest', force = 'neutral'}) do
        if candidate.unit_number == container_info.unit_number then
            chest = candidate
            break
        end
    end
    chest = chest or surface.find_entities_filtered{name = 'requester-chest', force = 'neutral'}[1]
    if not chest then
        error(label .. ': hungry chest missing')
    end
    return state, surface, chest, container_info
end

local function assert_hungry_chest_hidden(label)
    local _, _, chest, container_info = first_hungry_chest(label)
    local point = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    local section = point and point.get_section(1)
    if container_info.revealed ~= false then
        error(label .. ': hungry chest should start hidden')
    end
    if (container_info.price_count or 0) ~= 0 or (container_info.remaining or 0) ~= 0 then
        error(label .. ': hidden hungry chest exposed price data')
    end
    if section then
        error(label .. ': hidden hungry chest exposed requester slots')
    end
end

local function reveal_first_hungry_chest(label)
    local probe = remote.call('mts_expanse', 'probe_reveal_first_hungry_chest')
    if type(probe) ~= 'table' or probe.ok ~= true then
        error(label .. ': hungry chest reveal probe failed: ' .. tostring(probe and probe.error))
    end
    if probe.before_revealed ~= false or probe.before_price_count ~= 0 or probe.before_section ~= false then
        error(label .. ': hungry chest was revealed before click')
    end
    return assert_state(label .. ' revealed')
end

local function assert_hungry_chest_reroll(label)
    local probe = remote.call('mts_expanse', 'probe_reroll_first_hungry_chest')
    if type(probe) ~= 'table' or probe.ok ~= true then
        error(
            label .. ': hungry chest reroll probe failed: error=' .. tostring(probe and probe.error) ..
            ' before=' .. tostring(probe and probe.before_signature) ..
            ' after=' .. tostring(probe and probe.after_signature) ..
            ' before_generation=' .. tostring(probe and probe.before_generation) ..
            ' after_generation=' .. tostring(probe and probe.after_generation)
        )
    end
end

local function assert_lake_fallback_hungry_chest(label)
    local probe = remote.call('mts_expanse', 'probe_lake_fallback_hungry_chest')
    if type(probe) ~= 'table' or probe.ok ~= true then
        error(
            label .. ': lake fallback hungry chest probe failed: error=' .. tostring(probe and probe.error) ..
            ' revealed=' .. tostring(probe and probe.revealed) ..
            ' opened=' .. tostring(probe and probe.opened) ..
            ' before_adjacent_out_of_map=' .. tostring(probe and probe.before_adjacent_out_of_map) ..
            ' price_count=' .. tostring(probe and probe.price_count) ..
            ' request_name=' .. tostring(probe and probe.request_name)
        )
    end
    if probe.before_adjacent_out_of_map ~= false then
        error(label .. ': lake fallback probe chest still touched out-of-map')
    end
end

local function assert_admin_open_chest_lifecycle()
    local probe = remote.call('mts_expanse', 'probe_admin_open')
    if type(probe) ~= 'table' then
        error('admin-open probe did not return a table')
    end
    if probe.ok ~= true then
        error(
            'admin-open probe failed: opened=' .. tostring(probe.opened) ..
            ' removed_chests=' .. tostring(probe.removed_chests) ..
            ' created_chests=' .. tostring(probe.created_chests) ..
            ' target_removed=' .. tostring(probe.target_removed) ..
            ' before_chests=' .. tostring(probe.before_chests) ..
            ' after_chests=' .. tostring(probe.after_chests) ..
            ' before_size=' .. tostring(probe.before_size) ..
            ' after_size=' .. tostring(probe.after_size) ..
            ' natural_enemy_count=' .. tostring(probe.natural_enemy_count) ..
            ' expected_invasion_candidate=' .. tostring(probe.expected_invasion_candidate) ..
            ' invasion_candidate_blocked_by_water=' .. tostring(probe.invasion_candidate_blocked_by_water) ..
            ' before_invasion_candidates=' .. tostring(probe.before_invasion_candidates) ..
            ' after_invasion_candidates=' .. tostring(probe.after_invasion_candidates) ..
            ' before_schedule=' .. tostring(probe.before_schedule) ..
            ' after_schedule=' .. tostring(probe.after_schedule) ..
            ' error=' .. tostring(probe.error)
        )
    end
end

local function assert_cell_open_biters()
    local probe = remote.call('mts_expanse', 'probe_cell_open_biters')
    if type(probe) ~= 'table' then
        error('cell-open biter probe did not return a table')
    end
    if probe.ok ~= true then
        error(
            'cell-open biter probe failed: opened=' .. tostring(probe.opened) ..
            ' spawned=' .. tostring(probe.spawned) ..
            ' before_cell_biters=' .. tostring(probe.before_cell_biters) ..
            ' after_cell_biters=' .. tostring(probe.after_cell_biters) ..
            ' natural_enemy_count=' .. tostring(probe.natural_enemy_count) ..
            ' source_prepared=' .. tostring(probe.source_prepared) ..
            ' error=' .. tostring(probe.error)
        )
    end
end

local function assert_admin_open_variants()
    local probe = remote.call('mts_expanse', 'probe_admin_open_variants')
    if type(probe) ~= 'table' then
        error('admin-open variants probe did not return a table')
    end
    if probe.ok ~= true then
        local open_at = probe.open_at or {}
        local open_frontier = probe.open_frontier or {}
        error(
            'admin-open variants probe failed: open_at_opened=' .. tostring(open_at.opened) ..
            ' open_at_created_chests=' .. tostring(open_at.created_chests) ..
            ' open_at_before_chests=' .. tostring(open_at.before_chests) ..
            ' open_at_after_chests=' .. tostring(open_at.after_chests) ..
            ' frontier_opened=' .. tostring(open_frontier.opened) ..
            ' frontier_created_chests=' .. tostring(open_frontier.created_chests) ..
            ' frontier_before_chests=' .. tostring(open_frontier.before_chests) ..
            ' frontier_after_chests=' .. tostring(open_frontier.after_chests) ..
            ' container_count=' .. tostring(probe.container_count) ..
            ' error=' .. tostring(probe.error)
        )
    end
end

local function assert_frontier_repair()
    local probe = remote.call('mts_expanse', 'probe_frontier_repair')
    if type(probe) ~= 'table' then
        error('frontier repair probe did not return a table')
    end
    if probe.ok ~= true then
        error(
            'frontier repair probe failed: before_chests=' .. tostring(probe.before_chests) ..
            ' cleared_chests=' .. tostring(probe.cleared_chests) ..
            ' created_chests=' .. tostring(probe.created_chests) ..
            ' after_chests=' .. tostring(probe.after_chests) ..
            ' registry_count=' .. tostring(probe.registry_count) ..
            ' error=' .. tostring(probe.error)
        )
    end
end

local function assert_invasion_tracking(label)
    local probe = remote.call('mts_expanse', 'probe_invasion_tracking')
    if type(probe) ~= 'table' then
        error(label .. ': invasion tracking probe did not return a table')
    end
    if probe.ok ~= true then
        local regular = probe.regular or {}
        local admin = probe.admin or {}
        local tracker = probe.tracker or {}
        error(
            label .. ': invasion tracking probe failed: regular_ok=' .. tostring(regular.ok) ..
            ' regular_pending=' .. tostring(regular.pending) ..
            ' admin_ok=' .. tostring(admin.ok) ..
            ' admin_scheduled=' .. tostring(admin.scheduled_events) ..
            ' tracker_pending=' .. tostring(tracker.pending) ..
            ' tracker_required=' .. tostring(tracker.required) ..
            ' tracker_scheduled=' .. tostring(tracker.scheduled_events) ..
            ' before_schedule=' .. tostring(probe.before_schedule) ..
            ' error=' .. tostring(probe.error or regular.error or admin.error)
        )
    end
    return probe
end

local function assert_invasion_triggers(label, probe)
    local state = assert_state(label)
    local tracker = state.invasion_tracker or {}
    if (tracker.warning_events or 0) <= (probe.before_warning_events or 0)
        or (tracker.detonated_events or 0) <= (probe.before_detonated_events or 0)
        or (tracker.triggered_events or 0) <= (probe.before_triggered_events or 0)
    then
        error(
            label .. ': scheduled invasion did not trigger: warnings=' .. tostring(tracker.warning_events) ..
            ' detonated=' .. tostring(tracker.detonated_events) ..
            ' triggered=' .. tostring(tracker.triggered_events) ..
            ' before_warnings=' .. tostring(probe.before_warning_events) ..
            ' before_detonated=' .. tostring(probe.before_detonated_events) ..
            ' before_triggered=' .. tostring(probe.before_triggered_events) ..
            ' scheduled_events=' .. tostring(tracker.scheduled_events) ..
            ' next_scheduled_tick=' .. tostring(tracker.next_scheduled_tick) ..
            ' game_tick=' .. tostring(game.tick)
        )
    end
end

local function assert_vanilla_rocket_gating()
    if script.active_mods['space-age'] then
        return
    end
    local probe = remote.call('mts_expanse', 'probe_vanilla_rocket_gating')
    if type(probe) ~= 'table' then
        error('vanilla rocket gating probe did not return a table')
    end
    if probe.ok ~= true then
        error(
            'vanilla rocket gating probe failed: opened=' .. tostring(probe.opened) ..
            ' created_chests=' .. tostring(probe.created_chests) ..
            ' before_silos=' .. tostring(probe.before_silos) ..
            ' after_silos=' .. tostring(probe.after_silos) ..
            ' registered_silos=' .. tostring(probe.registered_silos) ..
            ' rocket_recipe_enabled=' .. tostring(probe.rocket_recipe_enabled) ..
            ' error=' .. tostring(probe.error)
        )
    end
end

local function assert_rocket_delivery()
    local expected_mode = script.active_mods['space-age'] and 'space-age' or 'vanilla'
    local expected_support = script.active_mods['space-age'] and 'space-age-surface-hub' or 'disabled'
    local probe = remote.call('mts_expanse', 'probe_rocket_delivery')
    if type(probe) ~= 'table' then
        error('rocket probe did not return a table')
    end
    if not script.active_mods['space-age'] then
        if probe.ok ~= false or probe.error ~= 'space missions disabled' then
            error('vanilla rocket probe should report disabled missions')
        end
        if probe.mode ~= expected_mode or probe.support_mode ~= expected_support then
            error('vanilla rocket probe returned wrong disabled state')
        end
        return
    end
    if probe.ok ~= true then
        error('rocket probe failed: ' .. tostring(probe.error))
    end
    if probe.mode ~= expected_mode then
        error('rocket probe wrong mode ' .. tostring(probe.mode))
    end
    if probe.support_mode ~= expected_support then
        error('rocket probe wrong support mode ' .. tostring(probe.support_mode))
    end
    if not (probe.started_level and probe.level and probe.level > probe.started_level) then
        error('rocket probe did not advance mission level; started=' .. tostring(probe.started_level) .. ' level=' .. tostring(probe.level) .. ' item=' .. tostring(probe.item) .. ' inserted=' .. tostring(probe.inserted) .. ' error=' .. tostring(probe.error))
    end
end

local function fill_first_hungry_chest(label)
    local probe = remote.call('mts_expanse', 'probe_complete_first_hungry_chest')
    if type(probe) ~= 'table' or probe.ok ~= true then
        error(
            label .. ': hungry chest completion probe failed: before_size=' .. tostring(probe and probe.before_size) ..
            ' after_size=' .. tostring(probe and probe.after_size) ..
            ' tile=' .. tostring(probe and probe.tile) ..
            ' error=' .. tostring(probe and probe.error)
        )
    end
    return {
        surface_name = probe.surface_name,
        left_top = probe.left_top,
        before_size = probe.before_size,
        cell_size = probe.cell_size or 15
    }
end

local function assert_hungry_chest_expanded(label, context)
    local state = assert_state(label)
    local surface = game.surfaces[context.surface_name]
    if (state.size or 0) <= context.before_size then
        local container = state.containers and state.containers[1]
        local details = container and (' remaining=' .. tostring(container.remaining) .. ' price_count=' .. tostring(container.price_count)) or ' no tracked containers'
        local chest_count = surface and surface.count_entities_filtered{name = 'requester-chest', force = 'neutral'} or -1
        error(label .. ': satisfied hungry chest did not increase Expanse size; state_size=' .. tostring(state.size) .. ' before_size=' .. tostring(context.before_size) .. ' container_count=' .. tostring(state.container_count) .. ' chest_count=' .. tostring(chest_count) .. ' scan_tick=' .. tostring(state.last_hungry_scan_tick) .. ' completion_tick=' .. tostring(state.last_hungry_completion_tick) .. ' removed_invalid_tick=' .. tostring(state.last_hungry_removed_invalid_tick) .. ';' .. details)
    end
    local center = {
        x = context.left_top.x + math.floor(context.cell_size * 0.5),
        y = context.left_top.y + math.floor(context.cell_size * 0.5)
    }
    local tile = surface.get_tile(center)
    if not tile.valid then
        error(label .. ': satisfied hungry chest target tile is not generated at ' .. center.x .. ',' .. center.y)
    end
    if tile.name == 'out-of-map' then
        error(label .. ': satisfied hungry chest did not unlock target cell')
    end
end

local completion_context

script.on_nth_tick(
	    30,
	    function()
	        if completion_context and completion_context.done then
	            return
	        end
	        if not completion_context then
	            assert_state('before reset')
            local ok = remote.call('mts_expanse', 'reset')
            if ok ~= true then
                error('reset did not return true')
            end
            assert_hungry_chest_hidden('after reset')
            assert_hungry_chest_reroll('after reset')
            ok = remote.call('mts_expanse', 'reset')
            if ok ~= true then
                error('reset after reroll probe did not return true')
            end
            assert_hungry_chest_hidden('after reroll reset')
            assert_lake_fallback_hungry_chest('after reroll reset')
            ok = remote.call('mts_expanse', 'reset')
            if ok ~= true then
                error('reset after lake fallback probe did not return true')
            end
            assert_hungry_chest_hidden('after lake fallback reset')
            completion_context = fill_first_hungry_chest('after reset')
            return
        end
        if not completion_context.post_completion_probes_done then
		        assert_hungry_chest_expanded('after chest completion', completion_context)
		        assert_admin_open_chest_lifecycle()
		        assert_cell_open_biters()
		        assert_admin_open_variants()
	        assert_frontier_repair()
	        assert_vanilla_rocket_gating()
	        assert_rocket_delivery()
            completion_context.invasion_probe = assert_invasion_tracking('after invasion tracking')
            completion_context.invasion_verify_tick = completion_context.invasion_probe.verify_tick or (game.tick + 120)
            completion_context.post_completion_probes_done = true
            return
        end
        if game.tick < completion_context.invasion_verify_tick then
            return
        end
        assert_invasion_triggers('after invasion trigger', completion_context.invasion_probe)
	        helpers.write_file('mts-expanse-probe-ok.txt', (script.active_mods['space-age'] and 'space-age' or 'vanilla') .. ' ok\n', false)
	        completion_context.done = true
	    end
	)
EOF
}

run_factorio() {
    "$FACTORIO" --config "$CONFIG" --mod-directory "$1" "${@:2}"
}

log "Checking Lua syntax"
find "$ROOT" -name '*.lua' -print0 | xargs -0 -n 1 "$LUA_COMPILER" -p

log "Preparing isolated Factorio test profile"
rm -rf "$WORK_DIR"
mkdir -p "$SOURCE_MODS" "$ZIP_MODS" "$PROBE_MODS"
write_config
ln -s "$ROOT" "$SOURCE_MODS/$PACKAGE_NAME"

log "Creating source-mod base-only save"
write_mod_list "$SOURCE_MODS" base
rm -f "$WORK_DIR/base.zip"
run_factorio "$SOURCE_MODS" --create "$WORK_DIR/base.zip"

log "Benchmarking source-mod base-only save"
run_factorio "$SOURCE_MODS" --benchmark "$WORK_DIR/base.zip" --benchmark-ticks 240 --benchmark-runs 1 --benchmark-sanitize

log "Creating source-mod Space Age save"
write_mod_list "$SOURCE_MODS" space-age
rm -f "$WORK_DIR/space-age.zip"
run_factorio "$SOURCE_MODS" --create "$WORK_DIR/space-age.zip"

log "Benchmarking source-mod Space Age save"
run_factorio "$SOURCE_MODS" --benchmark "$WORK_DIR/space-age.zip" --benchmark-ticks 240 --benchmark-runs 1 --benchmark-sanitize

log "Running scripted remote API probe"
ln -s "$ROOT" "$PROBE_MODS/$PACKAGE_NAME"
write_probe_mod "$PROBE_MODS"
write_mod_list "$PROBE_MODS" base true
rm -f "$WORK_DIR/probe.zip" "$WRITE_DATA/script-output/mts-expanse-probe-ok.txt"
run_factorio "$PROBE_MODS" --create "$WORK_DIR/probe.zip"
run_factorio "$PROBE_MODS" --benchmark "$WORK_DIR/probe.zip" --benchmark-ticks 300 --benchmark-runs 1 --benchmark-sanitize
test "$(cat "$WRITE_DATA/script-output/mts-expanse-probe-ok.txt")" = "vanilla ok"

log "Running scripted Space Age remote API probe"
write_mod_list "$PROBE_MODS" space-age true
rm -f "$WORK_DIR/probe-space-age.zip" "$WRITE_DATA/script-output/mts-expanse-probe-ok.txt"
run_factorio "$PROBE_MODS" --create "$WORK_DIR/probe-space-age.zip"
run_factorio "$PROBE_MODS" --benchmark "$WORK_DIR/probe-space-age.zip" --benchmark-ticks 300 --benchmark-runs 1 --benchmark-sanitize
test "$(cat "$WRITE_DATA/script-output/mts-expanse-probe-ok.txt")" = "space-age ok"

log "Building mod zip"
rm -rf "$WORK_DIR/$PACKAGE_NAME" "$ZIP_PATH"
rsync -a --exclude '.git' --exclude '*.zip' --exclude 'scripts/' "$ROOT/" "$WORK_DIR/$PACKAGE_NAME/"
(cd "$WORK_DIR" && zip -qr "$ZIP_PATH" "$PACKAGE_NAME")

log "Creating packaged-zip base-only save"
cp "$ZIP_PATH" "$ZIP_MODS/"
write_mod_list "$ZIP_MODS" base
rm -f "$WORK_DIR/zip-base.zip"
run_factorio "$ZIP_MODS" --create "$WORK_DIR/zip-base.zip"

log "All checks passed"
ls -lh "$ZIP_PATH"
