# Development Guide

This document keeps local testing and developer-facing details out of the
mod-portal README.

## Verification

Run the standalone test suite:

```bash
scripts/test.sh
```

Run the MTS compatibility probe against the latest official installed
`multi-team-support_*.zip`:

```bash
scripts/test-mts.sh
```

Run the focused forfeit cleanup regressions (all biter/spitter/worm tiers,
pentapods and their legs, demolishers and their segments, nests, attacks in
flight, hungry chest inventories, real character crafting queues, refund
spills, and cross-surface/force isolation):

```bash
python3 scripts/test-forfeit.py
```

These use disposable native Factorio saves in vanilla and Space Age, both
standalone and with MTS. They verify immediate removal, repeat resets, and no
delayed enemies while preserving research, map progress, and unrelated entities.

Run the saved event-ID regression against the published 0.1.19 baseline and the
working tree, in standalone/MTS and vanilla/Space Age:

```bash
python3 scripts/test-event-reload.py
```

This changes custom-event allocation between save and load, reproduces the
reported `get_player(nil)` error, then checks actual invasion enemies and blast
damage after both a plain reload and an upgrade. It also checks paid chest
progress, future timers, factories, and research. See
[the invasion diagnosis](invasion-event-routing.md) for the failure mechanism.

Use a specific official MTS zip when needed:

```bash
MTS_MOD_ZIP=/path/to/multi-team-support_<version>.zip scripts/test-mts.sh
```

Use an unpacked MTS checkout only for explicit local MTS development:

```bash
MTS_DEV_MODE=true MTS_MOD_DIR=/path/to/multi-team-support scripts/test-mts.sh
```

The automated graphical two-client Quality smoke patches an unpacked local MTS
checkout so it can bypass the Landing Pen and auto-claim separate teams:

```bash
MTS_MOD_DIR=/path/to/multi-team-support scripts/test-two-player-quality.sh
```

## Local Player Launcher

Use this when manually testing the real MTS join/create-team menu with local
Factorio clients:

```bash
scripts/launch-play.sh
```

The launcher uses the latest official installed `multi-team-support_*.zip` and
the local MTS Expanse checkout. Set `MTS_MOD_ZIP` only when testing a specific
official MTS zip.

Available launcher setups:

1. `MOD_SETUP=vanilla`: MTS + Expanse + vanilla.
2. `MOD_SETUP=vanilla-quality`: MTS + Expanse + vanilla + Quality.
3. `MOD_SETUP=space-age`: MTS + Expanse + vanilla + Elevated Rails + Space Age.
   Quality is enabled because Space Age depends on it.
4. `MOD_SETUP=space-age-quality`: MTS + Expanse + vanilla + Elevated Rails +
   Space Age + Quality.

If `MOD_SETUP` is omitted, the launcher uses `vanilla-quality`.

Audit the selected setup without opening clients:

```bash
MOD_SETUP=vanilla DRY_RUN=true scripts/launch-play.sh
```

The dry run prints the setup label, effective optional mods, save path, and
generated `mod-list.json`.

By default the launcher starts a headless server and two graphical clients on
`127.0.0.1:34217`, then leaves both clients in the MTS Landing Pen. In each
client, click **Start a new team** or use the join-team menu.

Use the patched local-MTS launcher only when an automated smoke run should
bypass the Landing Pen menu:

```bash
MTS_MOD_DIR=/path/to/multi-team-support MOD_SETUP=vanilla scripts/launch-play-patched-mts.sh
```

`scripts/launch-play-patched-mts.sh` sets `AUTO_CLAIM=true` by default and
copies the unpacked MTS checkout before patching Landing Pen startup flags.

For a manual menu test, only enable the final probe after you are ready for
Factorio's Lua console warning:

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

## Remote API

The public remote interface is:

```lua
remote.call("mts_expanse", "get_state", force_name)
remote.call("mts_expanse", "reset", force_name)
remote.call("mts_expanse", "probe_rocket_delivery", force_name)
```

Pass `force_name` in MTS games to inspect or reset a specific team. Omitting it
uses the default standalone Expanse state.

## Admin Commands

These commands bypass hungry chest payment while preserving the normal Expanse
frontier lifecycle: the hungry chest for the opened tile is removed, the tile is
generated, and new frontier hungry chests are created.

```text
/expanse-open [radius]
/expanse-open-at <x> <y> [radius]
/expanse-open-frontier [rings]
```

`/expanse-open` works from the admin player's current Expanse surface position.
In MTS games, the commands apply only to the admin player's current team.

## Mod Settings

The main Expanse tuning values are exposed as mod settings:

- Cell size.
- Token chance per chest.
- Chest value, minimum value, distance pricing, ore/fluid pricing, tier
  thresholds, and price roll count.
- MTS sync toggles for per-cell hungry chest contents and invasion/biter rolls.
- Source surface generation and shared virtual meta-map behavior.
- Admin open radius/ring/cell limits.
- Spoil time, enemy expansion, and enemy evolution tuning.
- Invasion enablement, warning/detonation timing, wave counts, strike
  radius/damage, and attack radius.
- Space Age support mode, hidden support surface size, mission processing
  interval, and rocket launch weight threshold.

The large item-price and mission-cost tables remain data tables in
`maps/expanse/price_raffle.lua` and `maps/expanse/mission_data.lua`; they are
not expanded into hundreds of individual mod settings.

## MTS Starter Surface Cleanup

After a team is moved onto its Expanse surface, MTS Expanse deletes that team's
unused MTS starter Nauvis surface (`team-N-nauvis`, or the Space Age
`mts-nauvis-N` variant). The shared vanilla `nauvis` surface and private
Expanse source surface are kept.

Disable this with the runtime-global setting:

```text
mts-expanse-cleanup-mts-nauvis=false
```

## Publishing

Before releases that change cargo delivery, run:

```bash
python3 scripts/test-cargo.py
python3 scripts/test-cargo-throughput.py
python3 scripts/test-reward-spoilage.py
```

This runs isolated native Factorio profiles for standalone and MTS with NonOrbit
and orbit-platform support. It checks request targets against existing and incoming
stock, exact quality, section state/multipliers, inventory bars and shared slots,
unavailable hatches, team ownership, deferred one-time rewards, actual pod arrival
without spills, and circuit requests. It also checks new rewards behind a hub
full of asteroids, bounded overflow storage and cleanup, and fair delivery through
a hatch that accepts only one pod per attempt. `CARGO_CASES=nonorbit,platform,mts,mts-platform`
selects cases. The test probe is excluded from release ZIPs.

The throughput suite measures actual pad inventory arrivals, clearing the pad
once per second, against every production cycle for six game minutes. It covers
maximum M4 production, all M4–M10 upgrades together, configured requests, platform
support, and blocked-pad recovery without lost stored cargo or ground spills.
`THROUGHPUT_CASES=m4,endgame,requested,platform,blocked` selects cases;
`CYCLES` and `DRAIN_EVERY` control duration and clearing cadence. `MEASURE_ONLY=1`
retains reports without failing the rate assertion for baseline comparisons.

The reward-spoilage suite creates and reloads native saves containing legacy
fruit buffers clogged with spoilage. It checks automatic recovery with spoilage
requested at zero, repeated spoilage, bounded storage, disabled requests and a
full pad, quality, actual fruit arrival, and retention/delivery of intentional
spoilage rewards. Native time verifies that only hidden mission rewards stay
fresh: items in the receiving pad and unrelated inventories still spoil normally.
`SPOILAGE_CASES=nonorbit,platform,mts,mts-platform` selects support configurations.

Before releases that change mission rewards or victory, run:

```bash
python3 scripts/test-victory.py
```

This uses disposable Factorio profiles to test one-time rewards, final mission
completion, continued production and factory preservation beyond the old reset
deadline, and upgrades with already queued victory resets. It covers standalone,
MTS, NonOrbit, orbit-platform, and vanilla configurations. Set `PREVIOUS_MOD_ZIP`
to the published `mts-expanse_0.1.12.zip` and `MTS_MOD_ZIP` to the desired official
Multi-Team Support ZIP if they are not in the script's default locations.

Use the existing publish script for Mod Portal uploads:

```bash
scripts/publish-mod-portal.sh
```

Keep the README player-focused because the Mod Portal renders it as the public
mod page. Put local paths, test procedures, and implementation notes in `docs/`.
