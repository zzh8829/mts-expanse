# MTS Expanse

Build a factory on a tiny island of land, feed the hungry chests, and expand
one cell at a time.

![MTS Expanse gameplay screenshot](https://raw.githubusercontent.com/zzh8829/mts-expanse/main/mts-expanse.png)

MTS Expanse is a standalone Factorio 2.0 mod port of ComfyFactorio's Expanse
scenario, rebuilt to work cleanly with Multi-Team Support. It turns map
expansion into the central progression loop: every new chunk of land has a cost,
and every team has to decide which direction is worth opening next.

## What You Do

- Start on a compact Expanse surface with limited space.
- Find hungry requester chests on the edge of your territory.
- Deliver the requested items to unlock new land.
- Use reroll tokens when a chest asks for something you cannot afford yet.
- Push outward into stronger terrain tiers, richer resources, and higher risk.
- Watch marked invasion sites and prepare before enemies arrive.
- In Space Age games, run Expanse space missions from your team's own surface.

The result is a tighter factory game where land is earned instead of freely
claimed. Expansion becomes a team decision, not just a radar-and-rail problem.

## Multiplayer

MTS Expanse is designed for Multi-Team Support servers.

With Multi-Team Support enabled, every team gets a separate Expanse surface and
its own progression state. Teams can play in parallel without sharing land,
hungry chest progress, rocket deliveries, statistics, or invasion timers.

For fair competitive starts, the mod can synchronize cell content between teams:
the same coordinates produce the same terrain rolls, hungry chest requests, and
invasion candidates. Each team still has its own surface and its own progress.

## Solo And Co-op

You can also play without Multi-Team Support. In a regular single-team game,
Expanse runs as a normal standalone mod on the default player force.

## Space Age

Space Age support is automatic:

- Without Space Age, Expanse runs in vanilla mode. Space Missions are disabled,
  and players use normal rocket silos to launch rockets and produce space
  science.
- With Space Age, Expanse enables Space Missions, planet-themed terrain tiers,
  and team-scoped rocket delivery.

MTS Expanse does not force teams onto a shared orbit platform. Space Age mission
delivery is routed through the owning team so one team's rockets do not advance
another team's missions.

## Server Settings

The mod exposes settings for expansion price scaling, cell size, synchronized
team content, invasions, enemy evolution, Space Age mission handling, and admin
open limits.

Most servers can start with the defaults. Competitive MTS servers usually want
to keep synchronized cell content and synchronized invasions enabled.

## Admin Tools

Admins can open nearby frontier cells for testing, moderation, or recovery:

```text
/expanse-open [radius]
/expanse-open-at <x> <y> [radius]
/expanse-open-frontier [rings]
```

These commands still run the normal Expanse frontier lifecycle, including new
hungry chest creation. In MTS games, they apply only to the admin player's
current team.

## Compatibility

Required:

- Factorio 2.0

Optional:

- Multi-Team Support
- Space Age
- Quality
- Elevated Rails when using Space Age

## Credits

MTS Expanse is a downstream port of ComfyFactorio's Expanse scenario. The
original scenario code and much of the supporting utility code come from the
ComfyFactorio project and contributors:

https://github.com/ComfyFactory/ComfyFactorio

This mod is not an official ComfyFactorio release. The inherited code remains
under the GPL-3.0 license included with this repository.

## More Information

- [Architecture notes](https://github.com/zzh8829/mts-expanse/blob/main/docs/architecture-decisions.md)
- [Development and testing guide](https://github.com/zzh8829/mts-expanse/blob/main/docs/development.md)
- [Multiplayer testing notes](https://github.com/zzh8829/mts-expanse/blob/main/docs/multiplayer-testing.md)
- [Source repository](https://github.com/zzh8829/mts-expanse)
