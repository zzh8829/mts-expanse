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

Use the existing publish script for Mod Portal uploads:

```bash
scripts/publish-mod-portal.sh
```

Keep the README player-focused because the Mod Portal renders it as the public
mod page. Put local paths, test procedures, and implementation notes in `docs/`.
