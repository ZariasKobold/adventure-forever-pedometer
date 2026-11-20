# Adventure Forever Pedometer

How far you've traveled in WoW Forever: on foot, mounted, flying, swimming, and by flight
path, per character, this session and all time. Plus where you've been: how many times
you've visited each dungeon, raid, and zone, and when last. Made by Draconic Designs, the people behind
Adventure Guide Forever (it used to be part of that addon).

## Use

- **`/pedometer`** (or `/steps`, or the addon compartment by the minimap) opens the window:
  - your total distance;
  - this session's distance and steps, and how long you've played;
  - each way of traveling, this session and all time;
  - marathons walked, and how much of it was in combat.

  If you have more than one character, click the corner to add them all up.
- **`/pedometer places`** (or the window's "Places visited" button) lists the dungeons,
  raids, and zones you've been to, most visited first, with when you were last there.
- **Step counter:** a small badge beside the minimap's calendar shows your steps this session.
  - Hover it for this session vs all time.
  - Click it to open the window.
  - Drag it to move it; right-click puts it back.
  - Turn it off in the window or with `/pedometer badge`.
- **`/pedometer status`** shows what the pedometer sees right now, for checking it works.

## How it counts

- **In the open world** it measures how far you actually moved, so flight paths, swimming,
  and flying all count properly.
- **In dungeons**, where the game hides your position, it uses your movement speed.
- **Fights are counted fairly.** Charges and leaps count only as far as you could have run,
  and being knocked back doesn't count at all.
- **Steps** assume a walking stride of about 0.85 yards.

## Coming from Adventure Guide Forever

Adventure Guide Forever counted distance before version 0.8.0, and visits to dungeons,
raids, and zones before 0.9.0. The first time you log in with this addon installed, it
brings each of those over for every character, once. You'll see a message in chat when it
does.

## Privacy

Everything (distance and places) stays on your computer, in `AdventureForeverPedometerDB`. Nothing is shared with
your group or anyone else.

## Install

Copy the `AdventureForeverPedometer` folder into
`World of Warcraft\_forever_\Interface\AddOns\`, then restart the game.

## Development

The addon's files sit at the root of this repo; `tests/` loads them in real Lua 5.1 with a
minimal stub of the WoW API. Needs Python 3.10+ and `lupa`:

```
pip install lupa
python -m unittest discover tests
```

Release zips leave out `tests/` (see `.gitattributes`):

```
git archive --format=zip --prefix=AdventureForeverPedometer/ -o AdventureForeverPedometer-vX.Y.Z.zip vX.Y.Z
```
