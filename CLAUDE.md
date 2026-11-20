# CLAUDE.md: Adventure Forever Pedometer

A World of Warcraft: Forever addon: distance traveled (on foot, mounted, flying, swimming, flight paths), this session and all time, with a step badge by the minimap; and places visited (dungeons, raids, zones: how often, when last). Split out of Adventure Guide Forever (the sibling `AdventureGuideForever/` folder, its own repo) in Nov 2026. Repo: https://github.com/ZariasKobold/adventure-forever-pedometer (public, branch `main`).

## Layout

The repo root is the addon folder players install.

| File | What it is |
|---|---|
| `Core.lua` | Namespace `P`, saved variables (`AdventureForeverPedometerDB`), `/pedometer` and `/steps`, and the one-time imports of what the guide counted (`AdventureGuideForeverDB.journey[*]`) at `PLAYER_LOGIN`: distance (`P:ImportFromGuide`, flag `importedFromGuide`) and visits (`P:ImportVisits`, flag `importedVisits`). |
| `UI.lua` | `P.Backdrop`, `P.Text`: the guide's dark-and-gold look. |
| `Pedometer.lua` | Counting: position-based in the open world (`UnitPosition`), speed-based in dungeons, combat rules (`P.Pace`), `P.Step`, records per character, session vs all time, `/pedometer status`. |
| `Badge.lua` | The step badge beside the minimap calendar (this session's steps). |
| `Places.lua` | Visits per character (`characters[key].places`, keyed by `P.PlaceKey(name)`: lowercase, no "The " or punctuation), counted on arrival (`P:Arrive`; `rec.here` stops a reload counting twice), and the guide import. |
| `Window.lua` | The `/pedometer` window: a Distance page and a Places page (`P:ShowWindow("places")`). |
| `tests/` | `python -m unittest discover tests` (needs `lupa`). Must pass before any change is done. |

Add any new Lua file to **both** TOCs (`AdventureForeverPedometer_Forever.toc` and the fallback `AdventureForeverPedometer.toc`); a test checks they match.

## Forever rules

Same platform as the guide (Interface 16001, the modern Midnight API on Lua 5.1):
- Lua 5.1 only; no `require`, `io`, `os`, `goto`. Every file starts `local _, P = ...`; allowed globals are listed at the top of `Core.lua`, and a test fails on any new one.
- Secret values: check API returns with `P:Readable(x)` before comparing or truth-testing them.
- One event frame per module with a handler table. Texture paths need double backslashes.
- Distance never leaves the player's computer.

## Releases

- Version lives only in both TOCs' `## Version:` line. Bump, commit, tag `vX.Y.Z`, push the tag.
- Zip: `git archive --format=zip --prefix=AdventureForeverPedometer/ -o AdventureForeverPedometer-vX.Y.Z.zip vX.Y.Z` (tests and this file are left out by `.gitattributes`), run from this folder, then attach it to a GitHub release. **Keep every release's zip here in this folder** (Dalton asked for that; `*.zip` is git-ignored, so they stay local).
- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
