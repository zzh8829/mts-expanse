# Multiplayer Testing Skill

Use this playbook when an agent needs to verify MTS Expanse with real local
multiplayer clients, not just headless map creation or benchmark probes.

## Goal

Prove that two local Factorio clients can join one local server, claim separate
Multi-Team Support teams, and load into separate Expanse gameplay surfaces.

For MTS Expanse, the decisive success condition is:

```text
MTSClientA,team-1,team-1-expanse,team-1-expanse,4,vanilla
MTSClientB,team-2,team-2-expanse,team-2-expanse,4,vanilla
```

That means each connected player is on a team force, standing on that team's
Expanse surface, and `remote.call("mts_expanse", "get_state", force_name)`
matches the surface MTS owns through `remote.call("mts-v1", "get_surface_owner",
surface_name)`.

## Preflight

Run the automated checks first:

```bash
scripts/test.sh
scripts/test-mts.sh
```

`scripts/test-mts.sh` uses the latest official installed
`multi-team-support_*.zip` by default. Set `MTS_MOD_ZIP` only when testing a
specific official zip.

The automated two-client Quality smoke is a patched local-MTS developer test
because it bypasses the Landing Pen menu:

```bash
MTS_MOD_DIR=/path/to/multi-team-support scripts/test-two-player-quality.sh
```

Confirm no old Factorio smoke processes are still running. Do not use a broad
`ps | rg factorio` check as a blocker for cleanup because it can match the
checking shell itself; filter on the exact work directory instead:

```bash
pgrep -af '/tmp/mts-expanse-two-client-quality-smoke|/tmp/mts-expanse-play' || true
```

Use the Steam Factorio binary currently tested with this repo:

```bash
FACTORIO="$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio"
```

## Important Steam Build Behavior

Direct graphical launches of the Steam build may exit with:

```text
Steam requires game restart, restarting...
```

Set these environment variables for GUI client launches:

```bash
SteamAppId=427520 SteamGameId=427520 "$FACTORIO" ...
```

For graphical Steam clients, the Steam remote `player-data.json` decides the
username. In this setup, profile-local `write-data/player-data.json` is ignored
by the Steam build for the joining username.

Never switch usernames on a timer. Set the global Steam player-data to
`MTSClientA`, launch client A, and wait for the fresh server log to show
`MTSClientA` joined before changing the file to `MTSClientB`. After client B is
confirmed in the fresh server log, restore the original Steam player-data file.

## Server Settings

The local server must disable auth verification and avoid public/LAN publishing:

```json
{
  "visibility": { "public": false, "lan": false },
  "require_user_verification": false,
  "game_password": "",
  "allow_commands": "true",
  "auto_pause": false,
  "auto_pause_when_players_connect": false
}
```

`require_user_verification=false` lets clients with custom local names join, but
the Steam remote player-data file still controls what name each graphical Steam
client sends.

## Player Identity Helper

The launcher scripts auto-detect the newest Steam Factorio `player-data.json`
under `$HOME/Library/Application Support/Steam/userdata`. If that is not the
right profile, set `STEAM_PLAYER_DATA` explicitly before launching.

Use serialized global player-data updates with identity confirmation:

```bash
STEAM_PLAYER_DATA="${STEAM_PLAYER_DATA:?set this to Steam Factorio player-data.json}"
STEAM_PLAYER_DATA_BACKUP="/tmp/mts-expanse-steam-player-data.backup.json"

cp -p "$STEAM_PLAYER_DATA" "$STEAM_PLAYER_DATA_BACKUP"
restore_steam_player_data() {
    if [[ -f "$STEAM_PLAYER_DATA_BACKUP" ]]; then
        cp -p "$STEAM_PLAYER_DATA_BACKUP" "$STEAM_PLAYER_DATA"
        rm -f "$STEAM_PLAYER_DATA_BACKUP"
    fi
}
trap restore_steam_player_data EXIT

set_factorio_username() {
    local name="$1"
    jq --arg user "$name" \
        '.username = $user | .["service-username"] = $user | del(.["service-token"])' \
        "$STEAM_PLAYER_DATA_BACKUP" > "$STEAM_PLAYER_DATA"
    touch "$STEAM_PLAYER_DATA"
}
```

Launch and verify in this order:

```bash
set_factorio_username MTSClientA
# launch client A
# wait for fresh server log: [JOIN] MTSClientA joined the game

set_factorio_username MTSClientB
# launch client B
# wait for fresh server log: [JOIN] MTSClientB joined the game

restore_steam_player_data
```

Do not change from A to B until client A's identity is confirmed by the server.
Do not restore the original file until client B's identity is confirmed.

`scripts/test-two-player-quality.sh` and `scripts/launch-play.sh` already follow
this rule.

## Observer Mod

Use a temporary probe mod in the smoke test mod directory. It should wait until
two players are connected, then write an OK file only when every player:

- is connected
- has a force name matching `team-N`
- has `mts_expanse.get_state(force_name)` returning that force's state
- has `state.active_surface_name == force_name .. "-expanse"`
- is standing on `state.active_surface_name`
- has `mts-v1.get_surface_owner(state.active_surface_name) == force_name`
- has the Expanse top buttons present

The useful output file is:

```text
server/write-data/script-output/mts-expanse-two-client-smoke-ok.txt
```

Expected contents:

```text
MTSClientA,team-1,team-1-expanse,team-1-expanse,4,vanilla
MTSClientB,team-2,team-2-expanse,team-2-expanse,4,vanilla
```

Keep a pending file for diagnostics:

```text
server/write-data/script-output/mts-expanse-two-client-smoke-pending.txt
```

For example, before the second player clicks "Start a new team", the pending
file may say:

```text
MTSClientB not on team force: spectator
```

## Manual GUI Flow

Prefer the launch script:

```bash
cd /Users/zihao/Repos/factorio/mts-expanse
scripts/launch-play.sh
```

The player-facing launcher uses the latest official
`multi-team-support_*.zip` from Factorio's mods directory and the local
MTS Expanse checkout. Set `MTS_MOD_ZIP` only when testing a specific official
MTS zip.

Available launcher setups:

1. `MOD_SETUP=vanilla`: MTS + Expanse + vanilla.
2. `MOD_SETUP=vanilla-quality`: MTS + Expanse + vanilla + Quality.
3. `MOD_SETUP=space-age`: MTS + Expanse + vanilla + Elevated Rails + Space Age.
   Factorio also enables Quality here because Space Age depends on it.
4. `MOD_SETUP=space-age-quality`: MTS + Expanse + vanilla + Elevated Rails +
   Space Age + Quality.

If `MOD_SETUP` is omitted, the launcher uses `vanilla-quality`.

Audit the selected setup without opening clients:

```bash
MOD_SETUP=vanilla DRY_RUN=true scripts/launch-play.sh
```

The dry run prints the setup label, effective optional mods, save path, and
generated `mod-list.json`.

Example:

```bash
MOD_SETUP=vanilla scripts/launch-play.sh
```

That script starts a persistent local stack on `127.0.0.1:34217` in tmux
sessions `mts-expanse-server`, `mts-expanse-client-a`, and
`mts-expanse-client-b`. It rotates stale logs before matching readiness
patterns, waits for the server to host from the fresh log, serializes Steam
player-data username changes, confirms each client identity from the fresh
server log before moving on, then leaves both clients in the MTS Landing Pen by
default so the "Start a new team" and join-team menu is visible.

Use `scripts/launch-play-patched-mts.sh` only for automated smoke runs that
should patch a local unpacked MTS checkout, bypass the MTS Landing Pen, and
auto-claim separate teams. It sets `AUTO_CLAIM=true` by default, which also
enables the final server-side player probe by default:

```bash
MTS_MOD_DIR=/path/to/multi-team-support MOD_SETUP=vanilla scripts/launch-play-patched-mts.sh
```

Once Expanse has moved a team onto `team-N-expanse`, the mod removes the unused
MTS starter Nauvis surface for that team (`team-N-nauvis`, or `mts-nauvis-N`
with Space Age). It does not delete shared `nauvis` or
`mts-expanse-meta-source`. Set `mts-expanse-cleanup-mts-nauvis=false` if a test
needs to inspect the original MTS starter surface.

Manual test steps after the clients open:

1. In client A, click `Start a new team`.
2. In client B, either click `Start a new team` or request to join client A's
   team from the Landing Pen join list.
3. Inspect the clients directly. For a log-level confirmation that both players
   moved out of the Landing Pen and onto the expected Expanse surfaces, rerun
   with `WAIT_FOR_CLIENTS=true`.

Use this when you explicitly want the launcher to wait for that final probe:

```bash
WAIT_FOR_CLIENTS=true scripts/launch-play.sh
```

The launch script creates a fresh save by default so stale broken local play
saves cannot survive a restart. Set `RESET_SAVE=false` only when intentionally
continuing an existing world. The final player-state probe uses `/sc` through
the server tmux session, so Factorio prints the standard Lua-console
achievements warning and asks for command confirmation before the probe runs.

For a manual launch:

1. Stop old `mts-expanse-*` tmux sessions and wait until no process references
   `/tmp/mts-expanse-play`.
2. Move old `factorio-current.log` files aside before starting anything new.
3. Start the headless server with `--start-server`, `--bind 127.0.0.1:<port>`,
   and the auth-disabled server settings.
4. Wait for `Hosting game at IP` in the freshly created server log only.
5. Back up the Steam remote player-data file.
6. Set the Steam remote player-data to `MTSClientA`, then launch client A with
   `SteamAppId=427520 SteamGameId=427520`.
7. Wait for the fresh server log to show `MTSClientA` joined.
8. Set the Steam remote player-data to `MTSClientB`, then launch client B with
   the same environment variables.
9. Wait for the fresh server log to show `MTSClientB` joined, then restore the
   original Steam player-data file.
10. Run a server-side player probe and verify the fresh server log shows
   `MTSClientA force=team-1 surface=team-1-expanse character=true` and
   `MTSClientB force=team-2 surface=team-2-expanse character=true`.

If automation can only control one Factorio window, it is acceptable to:

1. Spawn client A into `team-1-expanse`.
2. Disconnect client A.
3. Spawn client B into `team-2-expanse`.
4. Reconnect client A.
5. Let the observer confirm both clients are simultaneously connected.

## Cleanup

Stop all temporary Factorio processes:

```bash
tmux kill-session -t mts-expanse-client-b 2>/dev/null || true
tmux kill-session -t mts-expanse-client-a 2>/dev/null || true
tmux kill-session -t mts-expanse-server 2>/dev/null || true
pkill -f '/tmp/mts-expanse-two-client-quality-smoke.*/client-a/config.ini' || true
pkill -f '/tmp/mts-expanse-two-client-quality-smoke.*/client-b/config.ini' || true
pkill -f '/tmp/mts-expanse-two-client-quality-smoke.*/server/config.ini' || true
```

Confirm no smoke processes remain:

```bash
pgrep -af '/tmp/mts-expanse-two-client-quality-smoke|/tmp/mts-expanse-play' || true
```

## Common Failures

`Steam requires game restart, restarting...`

Use `SteamAppId=427520 SteamGameId=427520` when launching the graphical client
directly from the terminal.

`UserWithThatNameAlreadyInGame`

The two clients are still sending the same Factorio username. Stop both clients,
restore Steam player-data from the backup, rotate stale logs, then relaunch with
the serialized identity sequence: A, wait for A in the fresh server log, B, wait
for B in the fresh server log, restore.

One client unexpectedly appears as the other client

The launch changed Steam player-data before the previous client identity was
confirmed. Stop both clients, restore the backup, rotate stale logs, and relaunch
with identity confirmation between every username change. Do not trust readiness
checks that matched logs from an earlier server process.

One client has no character after restart

Do not reuse a stale play save while validating launcher or player lifecycle
changes. Restart with the default `RESET_SAVE=true`, or delete
`/tmp/mts-expanse-play/server/saves/mts-expanse-quality.zip`, so the client-state
probe is checking a fresh world.

`MTSClientB not on team force: spectator`

The second client is connected but still in the Landing Pen. Click `Start a new
team`.

Headless create/benchmark passes, but multiplayer fails

Headless tests do not create real connected players. Use the GUI client smoke
when player lifecycle, Landing Pen, top buttons, or per-player team assignment
matters.
