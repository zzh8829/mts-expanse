# MTS Expanse

MTS Expanse is a Factorio 2.0 mod fork of ComfyFactorio's Expanse scenario,
ported by zz for Multi-Team Support and packaged as a normal mod.

## Credits and Upstream

The original Expanse scenario code and much of the supporting utility code come
from the ComfyFactorio project:

https://github.com/ComfyFactory/ComfyFactorio

Full credit and acknowledgement go to the ComfyFactorio team and contributors for
creating Expanse and the Comfy framework this fork is based on. This repository
is a downstream fork/port focused on Multi-Team Support and standalone mod
packaging; it is not an official ComfyFactorio release.

The inherited code remains under the upstream GPL-3.0 license included in this
repository.

## Standalone Port

This port intentionally disables Comfy backend, panel, hotpatch, Discord, and
scenario-restart integrations so the map can run as a normal local/server mod.

Architecture notes are maintained in `docs/architecture-decisions.md`.
Multiplayer smoke-test instructions are maintained in
`docs/multiplayer-testing.md`.

## Multi-Team Support

`multi-team-support` is an optional dependency. When it is loaded, each MTS
team gets its own Expanse state on `team-N-expanse`, backed by the shared
virtual source surface `mts-expanse-meta-source` and a global `meta_map` that
caches per-cell roll data. Terrain source chunks, hungry chest prices,
tier/custom-tier rolls, and invasion candidate rolls are authored once in the
meta map and then materialized onto every team surface. Natural enemy autoplace
is stripped from both the virtual source and team surfaces; enemy units should
come from Expanse's cell/invasion flow only.

Expanse GUI, remote reset/state calls, research rewards, mission progress, and
rocket delivery are routed by the team force instead of the default `player`
force. Statistics and hungry chest progress are kept per team/surface.

Expanse has two runtime modes:

- `vanilla` when Space Age is not enabled.
- `space-age` when Space Age is enabled.

The mode is selected automatically from the active mods. Space Age mode enables
the Space Missions GUI, mission cost/reward tables, and planet-themed terrain
tiers. Vanilla mode disables Space Missions entirely. The orbit platform support
path stays disabled; Space Age mode uses the surface-hub rocket delivery path so
MTS teams do not get forced onto a shared orbit platform. Without Space Age,
Expanse does not spawn mission rocket silos or support surfaces; players use the
normal rocket silo path to launch rockets and produce space science.

Run the compatibility probe with an unpacked MTS checkout:

```bash
MTS_MOD_DIR=/tmp/multi-team-support scripts/test-mts.sh
```

Run the full local suite with:

```bash
scripts/test.sh
```

## Local Launch For Testing

Use the local launcher when you want to test the MTS join/create-team menu in
real Factorio clients. It uses your latest official `multi-team-support_*.zip`
from Factorio's mods directory and the local MTS Expanse checkout:

```bash
cd /Users/zihao/Repos/factorio/mts-expanse
scripts/launch-play.sh
```

Set `MTS_MOD_ZIP=/path/to/multi-team-support_<version>.zip` only when you need
to test against a specific official MTS zip.

Choose one of these setups with `MOD_SETUP`:

1. MTS + Expanse + vanilla:

   ```bash
   MOD_SETUP=vanilla scripts/launch-play.sh
   ```

2. MTS + Expanse + vanilla + Quality:

   ```bash
   MOD_SETUP=vanilla-quality scripts/launch-play.sh
   ```

3. MTS + Expanse + vanilla + Elevated Rails + Space Age:

   ```bash
   MOD_SETUP=space-age scripts/launch-play.sh
   ```

   Factorio requires Quality when Space Age is enabled, so this setup enables
   Quality as a dependency.

4. MTS + Expanse + vanilla + Elevated Rails + Space Age + Quality:

   ```bash
   MOD_SETUP=space-age-quality scripts/launch-play.sh
   ```

If `MOD_SETUP` is omitted, the launcher uses `vanilla-quality`.

To audit a setup without launching Factorio clients, add `DRY_RUN=true`:

```bash
MOD_SETUP=vanilla DRY_RUN=true scripts/launch-play.sh
```

The dry run prints the setup label, effective optional mods, save path, and
generated `mod-list.json`.

By default this starts a headless server and two graphical clients on
`127.0.0.1:34217`, then leaves both clients in the MTS Landing Pen. In each
client, click **Start a new team** or use the join-team menu.

After a team is moved onto its Expanse surface, MTS Expanse deletes that team's
unused MTS starter Nauvis surface (`team-N-nauvis`, or the Space Age
`mts-nauvis-N` variant). The shared vanilla `nauvis` surface and the private
Expanse source surface are kept. Disable this with the runtime-global setting
`mts-expanse-cleanup-mts-nauvis=false`.

For a patched local-MTS smoke run that bypasses the Landing Pen menu, use the
separate developer launcher with an unpacked MTS checkout:

```bash
MTS_MOD_DIR=/tmp/multi-team-support MOD_SETUP=vanilla scripts/launch-play-patched-mts.sh
```

`scripts/launch-play-patched-mts.sh` sets `AUTO_CLAIM=true` by default and
copies the unpacked MTS checkout before patching Landing Pen startup flags. For
a manual menu test with the official zip, only enable the final probe after you
are ready for Factorio's Lua console warning:

```bash
WAIT_FOR_CLIENTS=true scripts/launch-play.sh
```

That probe uses `/sc` in the server console, so Factorio prints the standard
"Lua console commands will disable achievements" warning and asks for command
confirmation before the probe runs.

Re-running the launcher stops old `mts-expanse-*` tmux sessions first. To stop
the stack manually:

```bash
tmux kill-session -t mts-expanse-client-b 2>/dev/null || true
tmux kill-session -t mts-expanse-client-a 2>/dev/null || true
tmux kill-session -t mts-expanse-server 2>/dev/null || true
```

The remote API is exposed as:

```lua
remote.call("mts_expanse", "get_state", force_name)
remote.call("mts_expanse", "reset", force_name)
remote.call("mts_expanse", "probe_rocket_delivery", force_name)
```

## Admin Commands

These commands bypass hungry chest payment while preserving the normal Expanse
frontier lifecycle: the hungry chest for the opened tile is removed, the tile is
generated, and new frontier hungry chests are created.

```text
/expanse-open [radius]
/expanse-open-at <x> <y> [radius]
/expanse-open-frontier [rings]
```

`/expanse-open` works from your current Expanse surface position. In MTS games,
the commands apply only to the admin player's current team. Any player who
starts/hosts an MTS team is automatically promoted to Factorio admin so team
hosts can use these tools without a separate server admin-list step.

## Mod Settings

The main Expanse tuning values are exposed as mod settings:

- Cell size
- Token chance per chest
- Chest value, minimum value, distance pricing, ore/fluid pricing, tier thresholds, and price roll count
- MTS sync toggles for per-cell hungry chest contents and invasion/biter rolls
- Source surface generation and shared virtual meta-map behavior
- Admin open radius/ring/cell limits
- Source surface generation, spoil time, enemy expansion, and enemy evolution tuning
- Invasion enablement, warning/detonation timing, wave counts, strike radius/damage, and attack radius
- Space Age support mode, hidden support surface size, mission processing interval, and rocket launch weight threshold

The large item-price and mission-cost tables remain data tables in
`maps/expanse/price_raffle.lua` and `maps/expanse/mission_data.lua`; they are
not expanded into hundreds of individual mod settings.
