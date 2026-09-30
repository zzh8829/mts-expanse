# Mission cargo throughput

Measured with Factorio 2.0.77, Space Age, and official Multi-Team Support 0.6.6.
The receiver is an ordinary 80-slot landing pad with no attached cargo bays.
Counts below are items actually deposited into and removed from its inventory,
not items dispatched or still in flight. Production uses the default 3,600 ticks.

## Cause and change

In 0.1.18, delivery ran only on the production tick, once per minute. The hidden
NonOrbit silo could open only one 10-slot pod at that time. Retry opportunities
were lost while its hatch was busy. Asteroid chunks each occupy one slot.

Dispatching every second fixed maximum M4 but still fell behind with all mission
upgrades. Mission reward transport now uses dedicated 80-slot pods, created
independently of the hidden source hatch. Only these pods skip the artificial
ascent; Factorio still handles descent, hatch occupancy, arrival, and incoming
cargo reservations. Pad and cargo-bay hatches accept both normal and reward pods.
Normal rocket and platform pod capacities are unchanged.

## Six-minute results

| Receiver / unlocked production | Expected | 0.1.18 received | Revised received |
| --- | ---: | ---: | ---: |
| NonOrbit, maximum M4, all three asteroid types | 270 | 60 | 270 |
| NonOrbit, every M4–M10 upgrade | 15,348 | 795 | 15,348 |
| NonOrbit, every upgrade, requests of twice each cycle's production | 15,348 | — | 15,348 |
| Platform support, every upgrade | 15,348 | — | 15,348 |

Every item matched its expected count at **each** one-minute checkpoint in the
revised runs, with no ground spills. Maximum production per minute is:

| Item | Items/minute |
| --- | ---: |
| Metallic / carbonic / oxide asteroid chunk | 15 each |
| Tungsten ore | 185 |
| Calcite | 95 |
| Scrap | 850 |
| Spoilage | 1,000 |
| Yumako / jellynut | 22 each |
| Pentapod egg | 10 |
| Lithium | 50 |
| Promethium asteroid chunk | 230 |
| Coal / sulfur | 20 each |
| Hot fluoroketone barrel | 9 |

Additional checks clear the pad once per second, hold it blocked for two
production cycles, then resume clearing. All cargo actually accepted into source
storage is eventually received, with no loss, duplication, or ground spills.
The separate request/capacity suite passes 102 checks across standalone/MTS and
NonOrbit/platform configurations. Base-only, Space Age, and packaged-mod load
checks also pass.

## Limits

Requests remain stock targets: stored plus incoming items count toward them.
Small targets can therefore constrain throughput even when the pad is emptied
quickly. Full pads, disabled requests, slow unloading, and exceptionally short
production intervals can still restrict delivery. Source storage stays bounded;
blocked passive production is not accumulated indefinitely.

Hidden mission inventories are staging storage: perishable rewards stay fresh
until dispatch. Items age normally in cargo pods, the receiving landing pad,
and player inventories. Older saves may have spoilage occupying a fruit's
overflow buffer. That waste is automatically discarded before production or
dispatch, without needing a spoilage request. Intentional spoilage rewards in
the shared source hub or their own spoilage buffer are preserved. Cleanup never
deletes anything from the receiving pad or other player storage.

Reproduce with `python3 scripts/test-cargo-throughput.py`. Run
`python3 scripts/test-cargo.py` for exact-quality requests, incoming/shared space,
inventory bars, circuits, team isolation, and other cargo regressions.
Run `python3 scripts/test-reward-spoilage.py` for legacy-save recovery and
perishable reward regression coverage.
