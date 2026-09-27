# Saved invasion event IDs

The supplied 2026-09-26 server log runs Factorio 2.0.77, MTS 0.6.6, and
MTS Expanse 0.1.19. It contains 484 identical errors at
`utils/datastore/session_data.lua:521`:

```text
bad argument #2 of 2 to 'get_player' (string expected, got nil)
```

437 originate in hungry-chest payment updates, 37 in completed-cell updates,
and 10 in the invasion scheduler's GUI update. These GUI events carry no
`player_index`, yet arrive at the unrelated `on_player_untrusted` handler.

## Cause

Expanse generated seven custom event IDs during the control stage, registered
handlers for those IDs, and saved the IDs inside its root and team state.
`Global.register` restored the old state on load, replacing the IDs used by
senders without replacing the handlers registered during the control stage.
Changes in event allocation therefore routed saved IDs to the wrong handlers.

The reported GUI-to-untrusted collision matches a two-ID shift. The log does
not establish which mod addition, update, or registration change caused it.
With this shift, an invasion warning reaches the resource GUI handler, a
detonation reaches the mission GUI handler, and a biter wave reaches the
warning handler. The scheduler still removes each timer and increments its
diagnostic counter. Consequently, a nonzero `triggered_events` counter alone
does not prove that any enemies were created.

## Fix

`maps/expanse/events.lua` owns the current control-stage IDs. All senders and
receivers use that same module, including chest updates, missions, victory,
map reset, and scheduled invasions. IDs are no longer saved in new states.
Old saved IDs are ignored and removed when defaults are refreshed; no storage
is modified in `on_load`.

Existing schedules already identify events by names such as
`invasion_trigger`, so pending timers survive and resolve to the current IDs.
Factories, research, expansion progress, candidate selection, and invasion
timing settings are unchanged. Events that an older version already consumed
incorrectly cannot be reconstructed from this log and are not replayed.

## Regression

`scripts/test-event-reload.py` creates disposable saves using the published
0.1.19 source. It adds two event allocations before reloading the same save.
The baseline must reproduce the exact logged error and count a triggered wave
while producing no invasion enemies.

The working tree must deliver GUI updates, warnings, detonations, and waves
to their correct handlers on both plain reload and version upgrade. The test
checks actual units, worms, nests, and blast damage, as well as future queued
events, chest payment, existing buildings, stored items, and research. It runs
in vanilla and Space Age, with and without official MTS 0.6.6, and rejects any
Lua stack trace in the fixed runs. Player saves and live servers are untouched.

Verified with Factorio 2.0.77 on 2026-09-26: all four baseline configurations
reproduced the error; all eight fixed reload/upgrade runs passed. The standard
standalone/package suite and official MTS compatibility suite also passed.
