#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FACTORIO="${FACTORIO:-$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio}"
FACTORIO_MODS_DIR="${FACTORIO_MODS_DIR:-$HOME/Library/Application Support/factorio/mods}"
MTS_MOD_ZIP="${MTS_MOD_ZIP:-}"
MTS_MOD_DIR="${MTS_MOD_DIR:-}"
MTS_DEV_MODE="${MTS_DEV_MODE:-false}"
WORK_DIR="${WORK_DIR:-/tmp/mts-expanse-mts-test}"

MOD_NAME="$(python3 -c 'import json; print(json.load(open("info.json"))["name"])')"
VERSION="$(python3 -c 'import json; print(json.load(open("info.json"))["version"])')"
MTS_VERSION=""
PACKAGE_NAME="${MOD_NAME}_${VERSION}"
ACTIVE_MTS_MOD_SOURCE=""
ACTIVE_MTS_MOD_LINK_NAME=""
MTS_SOURCE_LABEL=""

FACTORIO_CONTENTS="$(cd "$(dirname "$FACTORIO")/.." && pwd)"
READ_DATA="${READ_DATA:-$FACTORIO_CONTENTS/data}"
WRITE_DATA="$WORK_DIR/write-data"
CONFIG="$WORK_DIR/config.ini"
MODS="$WORK_DIR/mods"
PROBE="mts-expanse-mts-probe_0.1.0"

log() {
    printf '\n==> %s\n' "$*"
}

latest_installed_mts_zip() {
    [[ -d "$FACTORIO_MODS_DIR" ]] || return 1
    python3 - "$FACTORIO_MODS_DIR" <<'PY'
import glob
import os
import re
import sys

paths = glob.glob(os.path.join(sys.argv[1], "multi-team-support_*.zip"))
if not paths:
    raise SystemExit(1)

def version_key(path):
    match = re.match(r"^multi-team-support_(.+)\.zip$", os.path.basename(path))
    if not match:
        return ()
    parts = re.split(r"([0-9]+)", match.group(1))
    return tuple(int(part) if part.isdigit() else part for part in parts)

print(max(paths, key=version_key))
PY
}

mts_version_from_zip_name() {
    local base
    base="$(basename "$1")"
    if [[ "$base" =~ ^multi-team-support_([^/]+)\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

mts_version_from_dir() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$1/info.json"
}

resolve_mts_mod() {
    local source=""
    if [[ "$MTS_DEV_MODE" == "true" ]]; then
        source="${MTS_MOD_DIR:-$MTS_MOD_ZIP}"
    else
        source="$MTS_MOD_ZIP"
        if [[ -z "$source" && -n "$MTS_MOD_DIR" && "$MTS_MOD_DIR" == *.zip ]]; then
            source="$MTS_MOD_DIR"
        fi
    fi
    if [[ -z "$source" ]]; then
        source="$(latest_installed_mts_zip || true)"
    fi

    if [[ -z "$source" ]]; then
        echo "Could not find Multi-Team Support. Install the official zip in $FACTORIO_MODS_DIR or set MTS_MOD_ZIP." >&2
        exit 1
    fi

    if [[ -f "$source" && "$source" == *.zip ]]; then
        if ! MTS_VERSION="$(mts_version_from_zip_name "$source")"; then
            echo "MTS zip must be named multi-team-support_<version>.zip: $source" >&2
            exit 1
        fi
        ACTIVE_MTS_MOD_SOURCE="$source"
        ACTIVE_MTS_MOD_LINK_NAME="multi-team-support_$MTS_VERSION.zip"
        MTS_SOURCE_LABEL="$source"
    elif [[ -d "$source" ]]; then
        if [[ "$MTS_DEV_MODE" != "true" ]]; then
            echo "Unpacked Multi-Team Support dirs are only for explicit dev testing." >&2
            echo "Use the official installed zip with scripts/test-mts.sh, or set MTS_DEV_MODE=true." >&2
            exit 1
        fi
        if [[ ! -f "$source/info.json" ]]; then
            echo "multi-team-support source not found at: $source" >&2
            exit 1
        fi
        MTS_VERSION="$(mts_version_from_dir "$source")"
        ACTIVE_MTS_MOD_SOURCE="$source"
        ACTIVE_MTS_MOD_LINK_NAME="multi-team-support_$MTS_VERSION"
        MTS_SOURCE_LABEL="$source"
    else
        echo "Multi-Team Support source must be an official zip for scripts/test-mts.sh: $source" >&2
        exit 1
    fi
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
    local mode="$1"
    local elevated=false
    local quality=false
    local space_age=false
    if [[ "$mode" == "space-age" ]]; then
        elevated=true
        quality=true
        space_age=true
    fi
    cat > "$MODS/mod-list.json" <<EOF
{
  "mods": [
    {"name": "base", "enabled": true},
    {"name": "elevated-rails", "enabled": $elevated},
    {"name": "quality", "enabled": $quality},
    {"name": "space-age", "enabled": $space_age},
    {"name": "multi-team-support", "enabled": true},
    {"name": "$MOD_NAME", "enabled": true},
    {"name": "mts-expanse-mts-probe", "enabled": true}
  ]
}
EOF
}

write_probe_mod() {
    local dest="$MODS/$PROBE"
    mkdir -p "$dest"
    cat > "$dest/info.json" <<EOF
{
  "name": "mts-expanse-mts-probe",
  "version": "0.1.0",
  "title": "MTS Expanse MTS Probe",
  "author": "local",
  "factorio_version": "2.0",
  "dependencies": ["base", "? space-age", "multi-team-support", "$MOD_NAME"]
}
EOF
    cat > "$dest/control.lua" <<'EOF'
local function fail(msg) error('[mts-probe] ' .. msg) end
local function write(msg) helpers.write_file('mts-probe-ok.txt', msg .. '\n', true) end

local function assert_hungry_chest_requests(surface_name, unit_number)
    local surface = game.surfaces[surface_name]
    if not surface then fail(surface_name .. ' missing for chest probe') end
    local chests = surface.find_entities_filtered{name = 'requester-chest', force = 'neutral'}
    if #chests < 1 then fail(surface_name .. ' hungry chest missing') end
    local chest = chests[1]
    if unit_number then
        for _, candidate in pairs(chests) do
            if candidate.unit_number == unit_number then
                chest = candidate
                break
            end
        end
    end
    if unit_number and chest.unit_number ~= unit_number then fail(surface_name .. ' revealed hungry chest missing') end
    local point = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    if not point then fail(surface_name .. ' hungry chest logistic point missing') end
    local section = point.get_section(1)
    if not section then fail(surface_name .. ' hungry chest request section missing') end
    local ok, slot = pcall(function() return section.get_slot(1) end)
    if not ok or not slot then fail(surface_name .. ' hungry chest request slot missing') end
    if not (slot.value and slot.value.type == 'item' and slot.value.name and slot.min and slot.min > 0) then
        fail(surface_name .. ' hungry chest request slot empty')
    end
    return slot.value.name
end

local function assert_hungry_chest_hidden(force_name, state)
    local surface = game.surfaces[state.active_surface_name]
    if not surface then fail(force_name .. ' missing active surface for hidden chest probe') end
    local container_info = state.containers and state.containers[1]
    if not (container_info and container_info.left_top) then fail(force_name .. ' remote state did not expose hungry chest target') end
    local chest
    for _, candidate in pairs(surface.find_entities_filtered{name = 'requester-chest', force = 'neutral'}) do
        if candidate.unit_number == container_info.unit_number then
            chest = candidate
            break
        end
    end
    chest = chest or surface.find_entities_filtered{name = 'requester-chest', force = 'neutral'}[1]
    if not chest then fail(force_name .. ' hungry chest missing for hidden probe') end
    local point = chest.get_logistic_point(defines.logistic_member_index.logistic_container)
    local section = point and point.get_section(1)
    if container_info.revealed ~= false then fail(force_name .. ' hungry chest should start hidden') end
    if (container_info.price_count or 0) ~= 0 or (container_info.remaining or 0) ~= 0 then
        fail(force_name .. ' hidden hungry chest exposed price data')
    end
    if section then fail(force_name .. ' hidden hungry chest exposed requester slots') end
end

local function reveal_first_hungry_chest(force_name)
    local probe = remote.call('mts_expanse', 'probe_reveal_first_hungry_chest', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(force_name .. ' hungry chest reveal probe failed: ' .. tostring(probe and probe.error))
    end
    if probe.before_revealed ~= false or probe.before_price_count ~= 0 or probe.before_section ~= false then
        fail(force_name .. ' hungry chest was revealed before click')
    end
    return remote.call('mts_expanse', 'get_state', force_name), probe.request_name, probe.unit_number
end

local function find_unlock_left_top(surface, position, cell_size)
    local vectors = {{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
    for _, vector in pairs(vectors) do
        local tile = surface.get_tile(position.x + vector[1], position.y + vector[2])
        if tile.name == 'out-of-map' then
            return {
                x = tile.position.x - tile.position.x % cell_size,
                y = tile.position.y - tile.position.y % cell_size
            }
        end
    end
    for dx = -3, 3, 1 do
        for dy = -3, 3, 1 do
            local tile = surface.get_tile(position.x + dx, position.y + dy)
            if tile.name == 'out-of-map' then
                return {
                    x = tile.position.x - tile.position.x % cell_size,
                    y = tile.position.y - tile.position.y % cell_size
                }
            end
        end
    end
    return nil
end

local function fill_first_hungry_chest(force_name, state)
    local probe = remote.call('mts_expanse', 'probe_complete_first_hungry_chest', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(
            force_name .. ' hungry chest completion probe failed: before_size=' .. tostring(probe and probe.before_size) ..
            ' after_size=' .. tostring(probe and probe.after_size) ..
            ' tile=' .. tostring(probe and probe.tile) ..
            ' error=' .. tostring(probe and probe.error)
        )
    end
    return {
        force_name = force_name,
        surface_name = probe.surface_name,
        left_top = probe.left_top,
        before_size = probe.before_size,
        cell_size = probe.cell_size or (state.settings and state.settings.cell_size) or 15
    }
end

local function assert_hungry_chest_expanded(context)
    local state = remote.call('mts_expanse', 'get_state', context.force_name)
    local surface = game.surfaces[context.surface_name]
    if (state.size or 0) <= context.before_size then
        local container = state.containers and state.containers[1]
        local details = container and (' remaining=' .. tostring(container.remaining) .. ' price_count=' .. tostring(container.price_count)) or ' no tracked containers'
        local chest_count = surface and surface.count_entities_filtered{name = 'requester-chest', force = 'neutral'} or -1
        fail(context.force_name .. ' satisfied hungry chest did not increase Expanse size; state_size=' .. tostring(state.size) .. ' before_size=' .. tostring(context.before_size) .. ' container_count=' .. tostring(state.container_count) .. ' chest_count=' .. tostring(chest_count) .. ' scan_tick=' .. tostring(state.last_hungry_scan_tick) .. ' completion_tick=' .. tostring(state.last_hungry_completion_tick) .. ' removed_invalid_tick=' .. tostring(state.last_hungry_removed_invalid_tick) .. ';' .. details)
    end
    local center = {
        x = context.left_top.x + math.floor(context.cell_size * 0.5),
        y = context.left_top.y + math.floor(context.cell_size * 0.5)
    }
    local tile = surface.get_tile(center)
    if not tile.valid then
        fail(context.force_name .. ' satisfied hungry chest target tile is not generated at ' .. center.x .. ',' .. center.y)
    end
    if tile.name == 'out-of-map' then
        fail(
            context.force_name .. ' satisfied hungry chest did not unlock target cell: surface=' .. tostring(context.surface_name) ..
            ' active_surface=' .. tostring(state.active_surface_name) ..
            ' left_top=' .. tostring(context.left_top.x) .. ',' .. tostring(context.left_top.y) ..
            ' center=' .. tostring(center.x) .. ',' .. tostring(center.y) ..
            ' state_size=' .. tostring(state.size) ..
            ' before_size=' .. tostring(context.before_size) ..
            ' completion_tick=' .. tostring(state.last_hungry_completion_tick) ..
            ' scan_tick=' .. tostring(state.last_hungry_scan_tick) ..
            ' grid_open=' .. tostring(state.grid_open)
        )
    end
end

local function assert_synced_hungry_chest_reroll()
    local probe = remote.call('mts_expanse', 'probe_synced_hungry_chest_reroll', 'team-1', 'team-2')
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(
            'synced hungry chest reroll probe failed: error=' .. tostring(probe and probe.error) ..
            ' initial_a=' .. tostring(probe and probe.initial_a) ..
            ' initial_b=' .. tostring(probe and probe.initial_b) ..
            ' reroll_a=' .. tostring(probe and probe.reroll_a) ..
            ' reroll_b=' .. tostring(probe and probe.reroll_b) ..
            ' generation_a=' .. tostring(probe and probe.generation_a) ..
            ' generation_b=' .. tostring(probe and probe.generation_b)
        )
    end
end

local function assert_nonorbit_support(force_name, surface_name)
    local nonorbit = game.surfaces[surface_name]
    if not nonorbit then fail(surface_name .. ' support surface missing') end
    if #nonorbit.find_entities_filtered{name = 'cargo-landing-pad', force = force_name} < 1 then fail(force_name .. ' cargo pad missing') end
    if #nonorbit.find_entities_filtered{name = 'rocket-silo', force = force_name} < 1 then fail(force_name .. ' rocket silo missing') end
    if remote.call('mts-v1', 'get_surface_owner', surface_name) ~= force_name then fail(surface_name .. ' MTS owner mismatch') end
end

local function assert_mode(state, force_name)
    local expected_mode = script.active_mods['space-age'] and 'space-age' or 'vanilla'
    local expected_support = script.active_mods['space-age'] and 'space-age-surface-hub' or 'disabled'
    if state.mode ~= expected_mode then fail(force_name .. ' wrong mode: ' .. tostring(state.mode)) end
    if state.mission_support_mode ~= expected_support then fail(force_name .. ' wrong mission support mode: ' .. tostring(state.mission_support_mode)) end
    if state.space_missions_enabled ~= (script.active_mods['space-age'] and true or false) then fail(force_name .. ' wrong space mission enabled state') end
end

local function assert_rocket_delivery(force_name)
    local probe = remote.call('mts_expanse', 'probe_rocket_delivery', force_name)
    if type(probe) ~= 'table' then fail(force_name .. ' rocket probe did not return a table') end
    local expected_mode = script.active_mods['space-age'] and 'space-age' or 'vanilla'
    local expected_support = script.active_mods['space-age'] and 'space-age-surface-hub' or 'disabled'
    if not script.active_mods['space-age'] then
        if probe.ok ~= false or probe.error ~= 'space missions disabled' then fail(force_name .. ' rocket probe should report disabled missions') end
        if probe.mode ~= expected_mode then fail(force_name .. ' rocket probe wrong mode: ' .. tostring(probe.mode)) end
        if probe.support_mode ~= expected_support then fail(force_name .. ' rocket probe wrong support mode: ' .. tostring(probe.support_mode)) end
        return 'disabled'
    end
    if probe.ok ~= true then fail(force_name .. ' rocket probe failed: ' .. tostring(probe.error)) end
    if probe.mode ~= expected_mode then fail(force_name .. ' rocket probe wrong mode: ' .. tostring(probe.mode)) end
    if probe.support_mode ~= expected_support then fail(force_name .. ' rocket probe wrong support mode: ' .. tostring(probe.support_mode)) end
    if not (probe.started_level and probe.level and probe.level > probe.started_level) then
        fail(force_name .. ' rocket probe did not advance mission level; started=' .. tostring(probe.started_level) .. ' level=' .. tostring(probe.level) .. ' item=' .. tostring(probe.item) .. ' inserted=' .. tostring(probe.inserted) .. ' error=' .. tostring(probe.error))
    end
    return probe.item
end

local function assert_vanilla_rocket_gating(force_name)
    if script.active_mods['space-age'] then
        return
    end
    local probe = remote.call('mts_expanse', 'probe_vanilla_rocket_gating', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(
            force_name .. ' vanilla rocket gating probe failed: opened=' .. tostring(probe and probe.opened) ..
            ' created_chests=' .. tostring(probe and probe.created_chests) ..
            ' before_silos=' .. tostring(probe and probe.before_silos) ..
            ' after_silos=' .. tostring(probe and probe.after_silos) ..
            ' registered_silos=' .. tostring(probe and probe.registered_silos) ..
            ' rocket_recipe_enabled=' .. tostring(probe and probe.rocket_recipe_enabled) ..
            ' error=' .. tostring(probe and probe.error)
        )
    end
end

local function assert_mts_nauvis_cleanup(force_name)
    local probe = remote.call('mts_expanse', 'probe_mts_nauvis_cleanup', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(
            force_name .. ' MTS Nauvis cleanup probe failed: surface=' .. tostring(probe and probe.surface_name) ..
            ' before_exists=' .. tostring(probe and probe.before_exists) ..
            ' after_exists=' .. tostring(probe and probe.after_exists) ..
            ' deleted=' .. tostring(probe and probe.deleted) ..
            ' cleanup_tick=' .. tostring(probe and probe.cleanup_tick) ..
            ' error=' .. tostring(probe and probe.error)
        )
    end
    return probe
end

local function assert_invasion_tracking(force_name)
    local probe = remote.call('mts_expanse', 'probe_invasion_tracking', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        local regular = probe and probe.regular or {}
        local admin = probe and probe.admin or {}
        local tracker = probe and probe.tracker or {}
        fail(
            force_name .. ' invasion tracking probe failed: regular_ok=' .. tostring(regular.ok) ..
            ' regular_pending=' .. tostring(regular.pending) ..
            ' admin_ok=' .. tostring(admin.ok) ..
            ' admin_scheduled=' .. tostring(admin.scheduled_events) ..
            ' tracker_pending=' .. tostring(tracker.pending) ..
            ' tracker_required=' .. tostring(tracker.required) ..
            ' tracker_scheduled=' .. tostring(tracker.scheduled_events) ..
            ' before_schedule=' .. tostring(probe and probe.before_schedule) ..
            ' error=' .. tostring(probe and (probe.error or regular.error or admin.error))
        )
    end
    return probe
end

local function assert_cell_open_biters(force_name)
    local probe = remote.call('mts_expanse', 'probe_cell_open_biters', force_name)
    if type(probe) ~= 'table' or probe.ok ~= true then
        fail(
            force_name .. ' cell-open biter probe failed: opened=' .. tostring(probe and probe.opened) ..
            ' spawned=' .. tostring(probe and probe.spawned) ..
            ' before_cell_biters=' .. tostring(probe and probe.before_cell_biters) ..
            ' after_cell_biters=' .. tostring(probe and probe.after_cell_biters) ..
            ' natural_enemy_count=' .. tostring(probe and probe.natural_enemy_count) ..
            ' source_prepared=' .. tostring(probe and probe.source_prepared) ..
            ' error=' .. tostring(probe and probe.error)
        )
    end
    return probe
end

local function assert_invasion_triggers(force_name, probe)
    local state = remote.call('mts_expanse', 'get_state', force_name)
    local tracker = state and state.invasion_tracker or {}
    if (tracker.warning_events or 0) <= (probe.before_warning_events or 0)
        or (tracker.detonated_events or 0) <= (probe.before_detonated_events or 0)
        or (tracker.triggered_events or 0) <= (probe.before_triggered_events or 0)
    then
        fail(
            force_name .. ' scheduled invasion did not trigger: warnings=' .. tostring(tracker.warning_events) ..
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

local function mts_nauvis_surface_name(force_name)
    if script.active_mods['space-age'] then
        local slot = force_name:match('^team%-(%d+)$')
        return slot and ('mts-nauvis-' .. slot) or (force_name .. '-nauvis')
    end
    return force_name .. '-nauvis'
end

local function prepare_mts_nauvis_cleanup_surface(force_name)
    local surface_name = mts_nauvis_surface_name(force_name)
    local surface = game.surfaces[surface_name]
    if not surface and script.active_mods['space-age'] and game.planets and game.planets[surface_name] then
        local planet = game.planets[surface_name]
        surface = (planet.surface and planet.surface.valid) and planet.surface or planet.create_surface()
    end
    if not surface then
        local nauvis = game.surfaces['nauvis']
        surface = game.create_surface(surface_name, nauvis and nauvis.map_gen_settings or {})
    end
    surface.request_to_generate_chunks({0, 0}, 1)
    surface.force_generate_chunk_requests()
    return surface_name
end

local function container_layout_signature(state)
    local rows = {}
    for _, container in pairs(state.containers or {}) do
        if container.position and container.left_top then
            rows[#rows + 1] = table.concat({
                math.floor(container.position.x * 100),
                math.floor(container.position.y * 100),
                math.floor(container.left_top.x),
                math.floor(container.left_top.y),
                math.floor(container.remaining or 0),
                container.price_count or 0
            }, ',')
        end
    end
    table.sort(rows)
    return table.concat(rows, ';')
end

local function assert_team(force_name)
    local ok = remote.call('mts_expanse', 'reset', force_name)
    if ok ~= true then fail(force_name .. ' reset did not return true') end

    local expected_surface = script.active_mods['space-age'] and force_name .. '-expanse' or force_name .. '-nauvis'
    local expected_source = script.active_mods['space-age'] and 'mts-expanse-meta-source' or 'nauvis'
    local expected_nonorbit = force_name .. '-NonOrbit'
    local state = remote.call('mts_expanse', 'get_state', force_name)
    if type(state) ~= 'table' then fail(force_name .. ' state missing') end
    if state.force_name ~= force_name then fail(force_name .. ' wrong force: ' .. tostring(state.force_name)) end
    local suffix = tostring(state.active_surface_name):sub(#expected_surface + 1)
    if tostring(state.active_surface_name):sub(1, #expected_surface) ~= expected_surface or (suffix ~= '' and not suffix:match('^%d+$')) then
        fail(force_name .. ' wrong surface: ' .. tostring(state.active_surface_name))
    end
    if state.source_surface ~= expected_source then fail(force_name .. ' wrong source: ' .. tostring(state.source_surface)) end
    if type(state.meta_map) ~= 'table' then fail(force_name .. ' missing virtual meta map summary') end
    if state.meta_map.source_surface ~= expected_source then fail(force_name .. ' wrong virtual source: ' .. tostring(state.meta_map.source_surface)) end
    if state.nonspace_surface ~= expected_nonorbit then fail(force_name .. ' wrong support surface: ' .. tostring(state.nonspace_surface)) end
    if type(state.cost_stats) ~= 'table' then fail(force_name .. ' cost stats missing') end
    if type(state.settings) ~= 'table' then fail(force_name .. ' settings missing') end
    if state.settings.cell_size ~= 15 then fail(force_name .. ' wrong cell size setting') end
    if state.settings.sync_cell_content ~= true then fail(force_name .. ' sync cell content setting disabled by default') end
    if state.settings.sync_invasions ~= true then fail(force_name .. ' sync invasions setting disabled by default') end
    assert_mode(state, force_name)
    if not game.surfaces[state.active_surface_name] then fail(force_name .. ' active surface missing') end
    if not game.surfaces[state.source_surface] then fail(force_name .. ' source surface missing') end
    local enemy_filters = {type = {'unit', 'turret', 'unit-spawner'}, force = 'enemy'}
    if game.surfaces[state.active_surface_name].count_entities_filtered(enemy_filters) > 0 then
        fail(force_name .. ' active surface has natural enemy entities')
    end
    if game.surfaces[state.source_surface].count_entities_filtered(enemy_filters) > 0 then
        fail(force_name .. ' virtual source surface has natural enemy entities')
    end
    if remote.call('mts-v1', 'get_surface_owner', state.active_surface_name) ~= force_name then fail(force_name .. ' active surface MTS owner mismatch') end
    local chest_count = game.surfaces[state.active_surface_name].count_entities_filtered{name = 'requester-chest', force = 'neutral'}
    if state.container_count ~= chest_count then fail(force_name .. ' container registry/chest count mismatch') end
    assert_hungry_chest_hidden(force_name, state)
    local request_name
    local revealed_unit_number
    state, request_name, revealed_unit_number = reveal_first_hungry_chest(force_name)
    local section_request_name = assert_hungry_chest_requests(state.active_surface_name, revealed_unit_number)
    if request_name ~= section_request_name then
        fail(force_name .. ' reveal probe request mismatch: ' .. tostring(request_name) .. ' vs ' .. tostring(section_request_name))
    end
    local completion = fill_first_hungry_chest(force_name, state)
    if script.active_mods['space-age'] then
        assert_nonorbit_support(force_name, expected_nonorbit)
    elseif game.surfaces[expected_nonorbit] then
        fail(force_name .. ' vanilla mode created mission support surface')
    end
    local rocket_item = assert_rocket_delivery(force_name)
    return state, request_name, rocket_item, completion, container_layout_signature(state)
end

local completion_context

script.on_nth_tick(30, function()
    if not completion_context then
        assert_synced_hungry_chest_reroll()
        local team1, request1, rocket1, completion1, layout1 = assert_team('team-1')
        local team2, request2, rocket2, completion2, layout2 = assert_team('team-2')
        if team1.shared_seed ~= team2.shared_seed then
            fail('team shared seeds differ: ' .. tostring(team1.shared_seed) .. ' vs ' .. tostring(team2.shared_seed))
        end
        if team1.source_surface ~= team2.source_surface then
            fail('team virtual source surfaces differ: ' .. tostring(team1.source_surface) .. ' vs ' .. tostring(team2.source_surface))
        end
        if not team1.meta_map or not team2.meta_map or team1.meta_map.cell_count < 1 or team1.meta_map.cell_count ~= team2.meta_map.cell_count then
            fail('team virtual meta map summaries differ')
        end
        if team1.biome_offset ~= team2.biome_offset then
            fail('team biome offsets differ: ' .. tostring(team1.biome_offset) .. ' vs ' .. tostring(team2.biome_offset))
        end
        if layout1 ~= layout2 then
            fail('team initial hungry chest layouts differ: ' .. tostring(layout1) .. ' vs ' .. tostring(layout2))
        end
        local invasion1 = remote.call('mts_expanse', 'probe_synced_invasion', 'team-1')
        local invasion2 = remote.call('mts_expanse', 'probe_synced_invasion', 'team-2')
        if type(invasion1) ~= 'table' or invasion1.ok ~= true then
            fail('team-1 synced invasion probe failed: ' .. tostring(invasion1 and invasion1.error))
        end
        if type(invasion2) ~= 'table' or invasion2.ok ~= true then
            fail('team-2 synced invasion probe failed: ' .. tostring(invasion2 and invasion2.error))
        end
        if invasion1.signature ~= invasion2.signature then
            fail('synced invasion signatures differ: ' .. tostring(invasion1.signature) .. ' vs ' .. tostring(invasion2.signature))
        end
        assert_vanilla_rocket_gating('team-1')
        assert_vanilla_rocket_gating('team-2')
        local cleanup_surface1
        local cleanup_surface2
        if script.active_mods['space-age'] then
            cleanup_surface1 = prepare_mts_nauvis_cleanup_surface('team-1')
            cleanup_surface2 = prepare_mts_nauvis_cleanup_surface('team-2')
        end
        completion_context = {
            team1 = team1,
            team2 = team2,
            request1 = request1,
            request2 = request2,
            rocket1 = rocket1,
            rocket2 = rocket2,
            completion1 = completion1,
            completion2 = completion2,
            cleanup_surface1 = cleanup_surface1,
            cleanup_surface2 = cleanup_surface2,
            layout1 = layout1,
            layout2 = layout2,
            ready_tick = game.tick + 90
        }
        return
    end
    if completion_context.done or game.tick < completion_context.ready_tick then
        return
    end
    if not completion_context.cleanup_requested then
        if script.active_mods['space-age'] then
            assert_mts_nauvis_cleanup('team-1')
            assert_mts_nauvis_cleanup('team-2')
        end
        completion_context.cleanup_requested = true
        completion_context.cleanup_verify_tick = game.tick + 30
        return
    end
    if game.tick < completion_context.cleanup_verify_tick then
        return
    end
    if not completion_context.post_cleanup_probes_done then
        if completion_context.cleanup_surface1 and game.surfaces[completion_context.cleanup_surface1] then
            fail('team-1 MTS Nauvis cleanup surface still exists: ' .. tostring(completion_context.cleanup_surface1))
        end
        if completion_context.cleanup_surface2 and game.surfaces[completion_context.cleanup_surface2] then
            fail('team-2 MTS Nauvis cleanup surface still exists: ' .. tostring(completion_context.cleanup_surface2))
        end
        assert_hungry_chest_expanded(completion_context.completion1)
        assert_hungry_chest_expanded(completion_context.completion2)
        for _, force_name in pairs({'team-1', 'team-2'}) do
            local admin_probe = remote.call('mts_expanse', 'probe_admin_open', force_name)
            if type(admin_probe) ~= 'table' or admin_probe.ok ~= true then
                fail(
                    force_name .. ' admin-open probe failed: opened=' .. tostring(admin_probe and admin_probe.opened) ..
                    ' removed_chests=' .. tostring(admin_probe and admin_probe.removed_chests) ..
                    ' created_chests=' .. tostring(admin_probe and admin_probe.created_chests) ..
                    ' target_removed=' .. tostring(admin_probe and admin_probe.target_removed) ..
                    ' before_chests=' .. tostring(admin_probe and admin_probe.before_chests) ..
                    ' after_chests=' .. tostring(admin_probe and admin_probe.after_chests) ..
                    ' natural_enemy_count=' .. tostring(admin_probe and admin_probe.natural_enemy_count) ..
                    ' expected_invasion_candidate=' .. tostring(admin_probe and admin_probe.expected_invasion_candidate) ..
                    ' invasion_candidate_blocked_by_water=' .. tostring(admin_probe and admin_probe.invasion_candidate_blocked_by_water) ..
                    ' before_invasion_candidates=' .. tostring(admin_probe and admin_probe.before_invasion_candidates) ..
                    ' after_invasion_candidates=' .. tostring(admin_probe and admin_probe.after_invasion_candidates) ..
                    ' before_schedule=' .. tostring(admin_probe and admin_probe.before_schedule) ..
                    ' after_schedule=' .. tostring(admin_probe and admin_probe.after_schedule) ..
                    ' error=' .. tostring(admin_probe and admin_probe.error)
                )
            end
            assert_cell_open_biters(force_name)
            local variants_probe = remote.call('mts_expanse', 'probe_admin_open_variants', force_name)
            if type(variants_probe) ~= 'table' or variants_probe.ok ~= true then
                local open_at = variants_probe and variants_probe.open_at or {}
                local open_frontier = variants_probe and variants_probe.open_frontier or {}
                fail(
                    force_name .. ' admin-open variants probe failed: open_at_opened=' .. tostring(open_at.opened) ..
                    ' open_at_created_chests=' .. tostring(open_at.created_chests) ..
                    ' open_at_before_chests=' .. tostring(open_at.before_chests) ..
                    ' open_at_after_chests=' .. tostring(open_at.after_chests) ..
                    ' frontier_opened=' .. tostring(open_frontier.opened) ..
                    ' frontier_created_chests=' .. tostring(open_frontier.created_chests) ..
                    ' frontier_before_chests=' .. tostring(open_frontier.before_chests) ..
                    ' frontier_after_chests=' .. tostring(open_frontier.after_chests) ..
                    ' container_count=' .. tostring(variants_probe and variants_probe.container_count) ..
                    ' error=' .. tostring(variants_probe and variants_probe.error)
                )
            end
            local repair_probe = remote.call('mts_expanse', 'probe_frontier_repair', force_name)
            if type(repair_probe) ~= 'table' or repair_probe.ok ~= true then
                fail(
                    force_name .. ' frontier repair probe failed: before_chests=' .. tostring(repair_probe and repair_probe.before_chests) ..
                    ' cleared_chests=' .. tostring(repair_probe and repair_probe.cleared_chests) ..
                    ' created_chests=' .. tostring(repair_probe and repair_probe.created_chests) ..
                    ' after_chests=' .. tostring(repair_probe and repair_probe.after_chests) ..
                    ' registry_count=' .. tostring(repair_probe and repair_probe.registry_count) ..
                    ' error=' .. tostring(repair_probe and repair_probe.error)
                )
            end
        end
        completion_context.invasion_probes = {
            ['team-1'] = assert_invasion_tracking('team-1'),
            ['team-2'] = assert_invasion_tracking('team-2')
        }
        completion_context.invasion_verify_tick = math.max(
            completion_context.invasion_probes['team-1'].verify_tick or (game.tick + 120),
            completion_context.invasion_probes['team-2'].verify_tick or (game.tick + 120)
        )
        completion_context.post_cleanup_probes_done = true
        return
    end
    if game.tick < completion_context.invasion_verify_tick then
        return
    end
    for _, force_name in pairs({'team-1', 'team-2'}) do
        assert_invasion_triggers(force_name, completion_context.invasion_probes[force_name])
    end
    local team1 = remote.call('mts_expanse', 'get_state', 'team-1')
    local team2 = remote.call('mts_expanse', 'get_state', 'team-2')
    if team1.active_surface_index == team2.active_surface_index then fail('team surfaces share an index') end
    if game.surfaces[team1.active_surface_name].index == game.surfaces[team2.active_surface_name].index then fail('team surfaces are the same surface') end

    if script.active_mods['space-age'] then
        if team1.space_platform_enabled ~= false or team2.space_platform_enabled ~= false then fail('space platform mode enabled') end
        for _, force_name in pairs({'team-1', 'team-2'}) do
            for _, platform in pairs(game.forces[force_name].platforms) do
                if platform.valid and platform.name == force_name .. '-Orbit' then fail(force_name .. ' orbit platform still exists') end
            end
        end
        write('space-age ok request1=' .. completion_context.request1 .. ' request2=' .. completion_context.request2 .. ' rocket1=' .. completion_context.rocket1 .. ' rocket2=' .. completion_context.rocket2)
    else
        write('base ok request1=' .. completion_context.request1 .. ' request2=' .. completion_context.request2 .. ' missions=' .. completion_context.rocket1 .. ',' .. completion_context.rocket2)
    end
    completion_context.done = true
end)
EOF
}

run_factorio() {
    "$FACTORIO" --config "$CONFIG" --mod-directory "$MODS" "${@:1}"
}

resolve_mts_mod

rm -rf "$WORK_DIR"
mkdir -p "$MODS"
write_config
ln -s "$ROOT" "$MODS/$PACKAGE_NAME"
ln -s "$ACTIVE_MTS_MOD_SOURCE" "$MODS/$ACTIVE_MTS_MOD_LINK_NAME"
write_probe_mod

log "Using Multi-Team Support $MTS_VERSION from $MTS_SOURCE_LABEL"

log "Creating and probing base-only MTS save"
write_mod_list base
run_factorio --create "$WORK_DIR/base.zip"
run_factorio --benchmark "$WORK_DIR/base.zip" --benchmark-ticks 360 --benchmark-runs 1 --benchmark-sanitize
grep -q '^base ok request1=' "$WRITE_DATA/script-output/mts-probe-ok.txt"

log "Creating and probing Space Age MTS save"
write_mod_list space-age
run_factorio --create "$WORK_DIR/space-age.zip"
run_factorio --benchmark "$WORK_DIR/space-age.zip" --benchmark-ticks 360 --benchmark-runs 1 --benchmark-sanitize
grep -q '^space-age ok request1=' "$WRITE_DATA/script-output/mts-probe-ok.txt"

log "MTS compatibility checks passed"
