# Architecture Decisions

This document records the stable design decisions for MTS Expanse. Keep it free
of machine-local paths, account identifiers, and one-off session state.

## Project Boundary

MTS Expanse is a standalone Factorio 2.0 mod fork of ComfyFactorio's Expanse
scenario, ported by zz for Multi-Team Support.

The mod carries only the Expanse dependency closure needed to run the scenario
as a normal mod. Comfy backend services, Discord hooks, hotpatch behavior,
scenario restart/update behavior, and server-panel integrations are disabled or
shimmed because those systems are not available in a standalone mod install.

The upstream reference for the initial port was ComfyFactorio `develop` at
`6b299401`, tag `1.0.775`.

## Runtime Ownership Model

Standalone play uses one Expanse state for the default player force.

When `multi-team-support` is active, state is keyed by MTS team force. Each team
force owns its own active gameplay surface named:

```text
<force-name>-expanse
```

GUI routing, statistics, hungry chest progress, admin commands, rocket delivery,
mission progress, and remote API calls all resolve through the player's current
team force. Code should avoid singleton assumptions such as `game.forces.player`
or `game.surfaces[1]` for gameplay state.

## Shared Virtual Meta Map

MTS mode uses a single virtual source surface:

```text
mts-expanse-meta-source
```

Canonical random results are stored in `expanse.meta_map.cells`. The meta map is
the source of truth for cell-level roll data, including:

- terrain and source chunk materialization inputs
- cell tier and custom tier rolls
- hungry chest item and quality price entries
- invasion candidate decisions and positions
- any future random data that must match across teams

Team surfaces materialize from the meta map. A cell roll should be authored once
and reused by every force so equivalent coordinates have equivalent gameplay
content across teams.

The source surface must not be consumed or mutated in a way that makes later
teams receive different content. Cloning a cell for one team must leave the
canonical inputs available for other teams.

## Enemy Policy

Natural enemy autoplace is not valid gameplay for this fork. Biters should come
only from Expanse's cell-based generation and invasion systems.

The mod strips natural enemy entities from the shared source surface and team
surfaces around generated/cloned areas. This keeps admin-open, normal hungry
chest unlocks, and invasion flow compatible with MTS. If a future change adds
enemy content, it must write that decision into the meta map when cross-team
synchronization is enabled.

## Cross-Team Synchronization Toggles

The mod settings expose synchronization controls for:

- hungry chest contents
- cell roll content
- invasion and biter rolls

The synchronized path should use `expanse.meta_map.cells`. The unsynchronized
path may roll per team, but it still must remain scoped to that team's state and
surface.

## Admin Open Semantics

Admin open commands bypass hungry chest payment only. They must still run the
normal frontier lifecycle:

1. identify the target closed frontier cell
2. remove the hungry chest for that cell
3. materialize/open the cell
4. create new frontier hungry chests around the opened territory

There should not be a setting that changes admin-open into a separate content
mode. If `/expanse-open` fails to produce new frontier chests, that is a bug in
the frontier lifecycle, not a toggleable behavior.

## Game Modes

The mod selects an Expanse mode from active mods:

- `vanilla` when Space Age is not enabled
- `space-age` when Space Age is enabled

Space Missions, mission costs/rewards, and planet-themed content belong only to
Space Age mode. Vanilla mode must not show or process Space Missions.

The shared orbit-platform path is intentionally disabled for MTS. Space Age
rocket delivery uses the team's Expanse surface and support surfaces instead of
forcing teams onto a shared orbit platform.

## Rocket Delivery

Rocket launch and delivery handling must resolve the owning force and team
surface before updating Expanse state. A launch on one team's surface must not
advance missions, statistics, or chest state for another team.

The remote probe `remote.call("mts_expanse", "probe_rocket_delivery",
force_name)` exists so automated tests can validate this path without requiring
a full manual launch sequence.

## MTS Host Handling

Any MTS team host should be a Factorio admin for local testing and team
administration. The mod also reconciles a host's Factorio force if MTS records
them as a team leader but the engine has them on the wrong force after a join or
restart.

This is not an admin-list replacement for public servers. It is a runtime guard
for the MTS team-host flow.

## Verification Baseline

The repeatable verification suite is:

```bash
scripts/test.sh
MTS_MOD_DIR=/tmp/multi-team-support scripts/test-mts.sh
MTS_MOD_DIR=/tmp/multi-team-support scripts/test-two-player-quality.sh
```

`scripts/test.sh` covers Lua syntax, base-only create/benchmark, Space
Age/Quality create/benchmark, remote API probes, and packaged zip loading.

`scripts/test-mts.sh` covers MTS ownership, shared meta-map behavior, per-team
state separation, rocket delivery probes, and natural-enemy stripping.

`scripts/test-two-player-quality.sh` is the local graphical multiplayer smoke
test for two real clients.

The local play launcher is:

```bash
scripts/launch-play.sh
```

It uses the latest official installed `multi-team-support_*.zip` and keeps the
MTS Landing Pen enabled by default for manual play. Use the patched local-MTS
launcher only when an automated smoke run should bypass the join/create team
menu:

```bash
MTS_MOD_DIR=/tmp/multi-team-support scripts/launch-play-patched-mts.sh
```

See `docs/multiplayer-testing.md` for the full multiplayer procedure.
