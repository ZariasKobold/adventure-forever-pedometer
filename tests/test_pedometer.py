"""Tests for Adventure Forever Pedometer.

Run from this folder:  python -m unittest discover tests
Needs Python 3.10+ and lupa (embedded Lua 5.1, the Lua version WoW uses): pip install lupa
Loads the addon's real Lua files with a minimal stub of the WoW API.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from lupa import lua51

ADDON = "AdventureForeverPedometer"
ADDON_DIR = Path(__file__).resolve().parent.parent
TOC = ADDON_DIR / f"{ADDON}_Forever.toc"
FALLBACK_TOC = ADDON_DIR / f"{ADDON}.toc"

# Minimal WoW API: frames are inert objects whose methods do nothing.
STUBS = r"""
local inert = setmetatable({}, { __index = function() return function() end end })
local function newFrame() return setmetatable({}, { __index = function() return function() end end }) end
CreateFrame = function() return newFrame() end
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return unpack(out)
end
print = function() end
SlashCmdList = {}
UISpecialFrames = {}
C_Timer = { After = function() end }
GetTime = function() return 0 end
time = function() return 0 end
UIParent = inert
"""


def to_py(value):
    """Convert Lua tables into Python lists/dicts, recursively."""
    if lua51.lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(value[k]) for k in sorted(keys)]
    return {k: to_py(v) for k, v in value.items()}


def toc_files(toc: Path = TOC) -> list[str]:
    return [ln.strip() for ln in toc.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")]


def load():
    """Run the addon's files in TOC order; returns (lua, namespace P, globals created)."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    before = set(lua.globals().keys())
    ns = lua.table()
    for rel in toc_files():
        code = (ADDON_DIR / rel).read_text(encoding="utf-8")
        lua.eval("function(s, n) return assert(loadstring(s, '@' .. n)) end")(code, rel)(ADDON, ns)
    created = set(lua.globals().keys()) - before
    return lua, ns, created


class PedometerAddonTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.p, self.created = load()
        self.p.db = self.lua.eval("{ characters = {}, options = { badge = true } }")

    # The addon itself

    def test_tocs_match_and_list_real_files(self):
        self.assertEqual(toc_files(TOC), toc_files(FALLBACK_TOC))
        for rel in toc_files():
            self.assertTrue((ADDON_DIR / rel).is_file(), rel)
        header = TOC.read_text(encoding="utf-8")
        self.assertIn("## Interface: 16001", header)
        self.assertIn("## SavedVariables: AdventureForeverPedometerDB", header)

    def test_only_intended_globals(self):
        allowed = {"SLASH_ADVENTUREFOREVERPEDOMETER1", "SLASH_ADVENTUREFOREVERPEDOMETER2",
                   "AdventureForeverPedometer_OnCompartmentClick"}
        self.assertEqual(self.created - allowed, set())

    def test_lua51_only(self):
        forbidden = re.compile(r"\b(require|dofile|loadfile|io\.\w+|os\.\w+|setfenv|getfenv|goto)\b")
        single_backslash = re.compile(r'"[^"]*[^\\]\\[A-Za-z][^"]*"')
        for rel in toc_files():
            for n, line in enumerate((ADDON_DIR / rel).read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("--", 1)[0]
                self.assertIsNone(forbidden.search(code), f"{rel}:{n}")
                self.assertIsNone(single_backslash.search(code), f"{rel}:{n}: texture paths need \\\\")

    # Counting

    def test_combat_rules(self):
        pace = lambda speed, **s: self.p.Pace(speed, self.lua.table_from(s))  # noqa: E731
        # Out of combat the speed counts as is, even fast mounts.
        self.assertEqual(pace(30, combat=False), 30)
        self.assertEqual(pace(None, combat=False, moving=True), 0)
        # A charge counts like running, not a 40-yard stride.
        self.assertEqual(pace(40, combat=True, moving=True, lastPace=7), 14)
        self.assertEqual(pace(7, combat=True, moving=True, lastPace=7), 7)
        # A hidden speed counts as your last pace while you move, nothing while you stand.
        self.assertEqual(pace(None, combat=True, moving=True, lastPace=8), 8)
        self.assertEqual(pace(None, combat=True, moving=False, lastPace=8), 0)
        # Knockbacks: flung through the air without pressing a key counts nothing.
        self.assertEqual(pace(25, combat=True, airborne=True, moving=False, lastPace=7), 0)
        self.assertEqual(pace(25, combat=True, airborne=True, moving=True, lastPace=7), 7)

    def test_measures_real_movement(self):
        step = lambda a, b, dt: self.p.Step(  # noqa: E731
            a and self.lua.table_from(a), b and self.lua.table_from(b), dt)
        here = {"x": 100, "y": 200, "z": 10, "map": 0}
        # A flight path: 30 yards a second, counted as the distance actually covered.
        self.assertAlmostEqual(step(here, {"x": 115, "y": 200, "z": 10, "map": 0}, 0.5), 15)
        # Swimming or flying up and down counts too (3D).
        self.assertAlmostEqual(step(here, {"x": 100, "y": 200, "z": 13, "map": 0}, 1.0), 3)
        self.assertEqual(step(here, here, 0.5), 0)                                      # standing still
        self.assertIsNone(step(here, {"x": 115, "y": 200, "z": 10, "map": 1}, 0.5))     # loading screen
        self.assertIsNone(step(here, {"x": 900, "y": 200, "z": 10, "map": 0}, 0.5))     # hearthstone
        self.assertIsNone(step(None, here, 0.5))                                        # first sample
        self.assertIsNone(step(here, here, 8))                                          # long gap

    def test_travel_counts_this_session_and_all_time(self):
        rec = self.lua.eval("{ distance = { foot = 100 }, combat = 0 }")  # an old record, no session yet
        self.p.AddTravel(rec, "foot", 17, False)
        self.p.AddTravel(rec, "mounted", 50, True)
        rec = to_py(rec)
        self.assertEqual(rec["distance"]["foot"], 117)
        self.assertEqual(rec["session"]["distance"]["foot"], 17)
        self.assertEqual(rec["session"]["distance"]["mounted"], 50)
        self.assertEqual((rec["combat"], rec["session"]["combat"]), (50, 50))
        self.assertEqual(self.p.TotalYards(self.lua.table_from(rec["session"]["distance"])), 67)

    def test_numbers_for_people(self):
        self.assertEqual(self.p.Distance(50), "50 yards")
        self.assertEqual(self.p.Distance(1760 * 2.5), "2.50 miles")
        self.assertEqual(self.p.Distance(1760 * 31), "31.0 miles")
        self.assertEqual(self.p.Commas(1234567.8), "1,234,567")
        self.assertEqual(self.p.StepsFrom(85), 100)
        self.assertEqual(self.p.PlayedFor(30), "under a minute")
        self.assertEqual(self.p.PlayedFor(3600 + 5 * 60), "1 hour 5 minutes")

    def test_totals_add_up_characters(self):
        a = self.p.GetRecord(self.p, "Ana-Realm")
        b = self.p.GetRecord(self.p, "Bo-Realm")
        self.p.AddTravel(a, "foot", 100, False)
        self.p.AddTravel(b, "foot", 50, True)
        self.p.AddTravel(b, "taxi", 1000, False)
        total = to_py(self.p.Totals(self.p))
        self.assertEqual((total["distance"]["foot"], total["distance"]["taxi"], total["combat"]), (150, 1000, 50))
        notes = list(self.p.WindowNotes(self.p, self.p.Totals(self.p), True).values())
        self.assertTrue(any("Bo-Realm" in n for n in notes))

    # Bringing over what the guide counted

    def test_imports_guide_distance_once(self):
        guide = self.lua.eval("""{ journey = {
            ["Ana-Realm"] = { distance = { foot = 1000, taxi = 5000, mounted = 0, flying = 0, swim = 20 },
                              combat = 80, class = "DRUID", instances = { deadmines = { visits = 3 } } },
            ["Bo-Realm"] = { instances = {} },                     -- visits only, nothing to bring
        } }""")
        self.assertEqual(self.p.ImportFromGuide(self.p, guide), 1)
        rec = to_py(self.p.db.characters)["Ana-Realm"]
        self.assertEqual((rec["distance"]["foot"], rec["distance"]["taxi"], rec["distance"]["swim"]), (1000, 5000, 20))
        self.assertEqual((rec["combat"], rec["class"]), (80, "DRUID"))
        self.assertNotIn("instances", rec)                        # visits stay with the guide
        # Only once: a second login doesn't double anyone's miles.
        self.assertEqual(self.p.ImportFromGuide(self.p, guide), 0)
        self.assertEqual(to_py(self.p.db.characters)["Ana-Realm"]["distance"]["foot"], 1000)

    def test_import_without_the_guide(self):
        self.assertEqual(self.p.ImportFromGuide(self.p, None), 0)
        self.assertEqual(self.p.ImportFromGuide(self.p, self.lua.eval("{ journey = 'junk' }")), 0)

    # Places

    def test_place_keys(self):
        key = self.p.PlaceKey
        self.assertEqual(key("The Deadmines"), "deadmines")
        self.assertEqual(key("Deadmines"), "deadmines")
        self.assertEqual(key("Zul'Farrak"), "zulfarrak")
        self.assertIsNone(key(""))
        self.assertIsNone(key(None))

    def test_arriving_counts_visits(self):
        self.lua.execute("""
            agf_where = { "The Deadmines", "party" }
            agf_now = 86400 * 10
            time = function() return agf_now end
            GetInstanceInfo = function() return agf_where[1], agf_where[2] end
            GetRealZoneText = function() return agf_where[1] end
            UnitName = function() return "Me" end
            GetRealmName = function() return "Realm" end
            UnitClass = function() return "Druid", "DRUID", 11 end""")
        self.p.Arrive(self.p)
        self.p.Arrive(self.p)                                  # a reload inside: not another visit
        self.lua.execute("agf_where = { 'Westfall', 'none' }")
        self.p.Arrive(self.p)
        self.lua.execute("agf_where = { 'The Deadmines', 'party' }")
        self.p.Arrive(self.p)
        places = to_py(self.p.Mine(self.p).places)
        self.assertEqual(places["deadmines"]["visits"], 2)
        self.assertEqual(places["deadmines"]["kind"], "dungeon")
        self.assertEqual(places["westfall"]["visits"], 1)
        self.assertEqual(places["westfall"]["kind"], "zone")
        text = self.p.PlacesText(self.p, self.p.Mine(self.p).places, 86400 * 12)
        self.assertIn("The Deadmines", text)
        self.assertIn("2 visits, last 2 days ago", text)
        self.assertLess(text.index("The Deadmines"), text.index("Westfall"))   # dungeons, then zones

    def test_imports_guide_visits_once(self):
        guide = self.lua.eval("""{ journey = {
            ["Me-Realm"] = { here = "deadmines", class = "DRUID",
                instances = { deadmines = { visits = 3, last = 100 } },
                instanceNames = { deadmines = "Deadmines" },
                zones = { Westfall = { visits = 5, last = 50 } } },
            ["Alt-Realm"] = { instances = {}, zones = {} } } }""")
        self.assertEqual(self.p.ImportVisits(self.p, guide), 1)
        rec = to_py(self.p.db.characters["Me-Realm"])
        self.assertEqual(rec["places"]["deadmines"], {"name": "Deadmines", "kind": "dungeon", "visits": 3, "last": 100})
        self.assertEqual(rec["places"]["westfall"]["visits"], 5)
        self.assertEqual(rec["here"], "deadmines")       # standing there: no extra visit at login
        self.assertEqual(self.p.ImportVisits(self.p, guide), 0)    # only once
        self.assertEqual(self.p.ImportVisits(self.p, None), 0)
        # Totals add characters together.
        self.p.db.characters["Alt-Realm"].places = self.lua.eval(
            "{ deadmines = { name = 'The Deadmines', kind = 'dungeon', visits = 2, last = 300 } }")
        total = to_py(self.p.PlaceTotals(self.p))
        self.assertEqual((total["deadmines"]["visits"], total["deadmines"]["last"]), (5, 300))


if __name__ == "__main__":
    unittest.main()
