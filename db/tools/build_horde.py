#!/usr/bin/env python3
"""Build the Horde 1-20 questing database in db/horde/ from every source we have.

Development tool only; nothing here ships. Run fetch_sources.py and
questie_extract.py first.

Sources, and what each is trusted for:
  ingame     db/ingame/ (NuuExperiments/Tools/QuestExport.py): what the Forever client
             itself says, from the quest-scan and quest-record experiments. Trusted
             first for names, levels, objective counts, givers, turn-ins, NPC
             positions and XP (worked out from the server's XP difficulty and
             multiplier in the client's quest cache); quests the server answered it
             does not have are left out. Optional: without it the build is what it was.
  ours       db/quests.json, db/npcs.json: taken from our guides, played on Forever.
             Notes, counts, positions. Its Mulgore points use the Classic map
             bounds (copied from RestedXP comments) and are converted.
  rxp        RestedXP's Forever guides and flight times (AddOns/RXPGuides): quest
             givers, turn-ins and objective areas in world coordinates, counts.
  fg         ForeverGuide's data-src/forever.json: Forever-only quests from an
             in-game scan (names, levels), recorded objectives and positions.
  questie    QuestieDB's Forever build (db/questie/): the Classic quest graph,
             levels, XP, objectives, spawns, drops. Its map coordinates already
             use Forever's bounds.
  client     Forever client tables from wago.tools: which quest IDs exist, map
             bounds and names, flight nodes and routes, quest lines.

Every position in the output is a map coordinate (0-100) on a Forever uiMapID.

    python3 db/tools/build_horde.py
"""

import csv
import glob
import json
import math
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.abspath(os.path.join(HERE, ".."))
ADDONS = os.path.abspath(os.path.join(DB, "..", "..", "AddOns"))
SOURCES = os.path.join(DB, "sources")
OUT = os.path.join(DB, "horde")

MAX_LEVEL = 20          # quests a character can pick up by this level
HORDE_RACES = 2 | 16 | 32 | 128 | 512
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024
RACES = {1: "Human", 2: "Orc", 4: "Dwarf", 8: "NightElf", 16: "Undead", 32: "Tauren", 64: "Gnome",
         128: "Troll", 256: "Goblin", 512: "BloodElf", 1024: "Draenei"}
CLASSES = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 32: "DeathKnight",
           64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}
CLASS_BY_NAME = {v.lower(): k for k, v in CLASSES.items()}
RACE_BY_NAME = {v.lower(): k for k, v in RACES.items()}
RACE_BY_NAME.update({"scourge": 16, "nightelf": 8, "bloodelf": 512})

# Maps where only one faction has quest hubs; used to place Forever quests that
# no source gives a faction for.
HORDE_MAPS = {1411, 1412, 1413, 1420, 1421, 1442, 1454, 1456, 1458, 2524}
ALLIANCE_MAPS = {1426, 1429, 1438, 1439, 1453, 1455, 1457, 1433, 1436, 1437, 1432}
# Where a Horde character levels to 20: the Horde zones and cities, the contested zones next
# to them, Forever's new zones, and the dungeons they lead to. Class and profession quests
# are kept wherever their trainer stands.
SCOPE_MAPS = HORDE_MAPS | {1424, 1440, 1441, 2521, 2665, 2548}
SCOPE_DUNGEONS = {"Ragefire Chasm", "Wailing Caverns", "Shadowfang Keep", "Blackfathom Deeps", "Razorfen Kraul"}
MAX_QUEST_LEVEL = 30    # a level-20 minimum on a level-35 quest (Gnomeregan) is not something to do at 20
JUNK = re.compile(r"\btest\b|zzOLD|UNUSED|Temp Disabled|^None$|\[DNT\]|DEPRECATED", re.I)
SERVICE_ROLES = {"vendor", "trainer", "flightMaster", "innkeeper", "repair", "stablemaster", "banker",
                 "spiritHealer", "auctioneer"}
# QuestSorts that are world events. Not "Special": Forever files ordinary quests there (79095, a level 20 book).
EVENT_SORTS = ("Seasonal", "Darkmoon", "Lunar", "Brewfest", "Children", "Hallow", "Midsummer", "Winter Veil",
               "Love is in the Air", "Noblegarden", "Pilgrim", "Harvest", "Event", "Holiday",
               "Battleground", "Alterac", "Warsong", "Arathi")


# --- IO --------------------------------------------------------------------------

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write(name, data):
    """One entry per line, sorted by numeric key, so diffs between builds stay readable."""
    path = os.path.join(OUT, name)
    def key(kv):
        k = str(kv[0])
        return (0, int(k), "") if k.lstrip("-").isdigit() else (1, 0, k)
    items = sorted(data.items(), key=key)
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n")
        for i, (k, v) in enumerate(items):
            f.write("%s: %s%s\n" % (json.dumps(str(k)), json.dumps(v, ensure_ascii=False, separators=(",", ":")),
                                     "," if i < len(items) - 1 else ""))
        f.write("}\n")
    print("wrote %-18s %6d entries  %5.1f MB" % (name, len(data), os.path.getsize(path) / 1e6))


# --- Maps and coordinates -----------------------------------------------------------

class Maps:
    def __init__(self):
        forever = os.path.join(SOURCES, "wago", "forever")
        era = os.path.join(SOURCES, "wago", "era")
        self.assign = load_csv(os.path.join(forever, "UiMapAssignment.csv"))
        self.bounds = self._bounds(self.assign)
        self.era_bounds = self._bounds(load_csv(os.path.join(era, "UiMapAssignment.csv")))
        self.info = {int(r["ID"]): {"name": r["Name_lang"], "parent": int(r["ParentUiMapID"]), "type": int(r["Type"])}
                     for r in load_csv(os.path.join(forever, "UiMap.csv"))}
        # Area ID -> uiMapID, from the map assignments, else through the area's parents (a subzone names its zone).
        self.area_parent = {int(r["ID"]): int(r["ParentAreaID"]) for r in load_csv(os.path.join(forever, "AreaTable.csv"))}
        self.area_map = {}
        for r in self.assign:
            if int(r["AreaID"]) and int(r["AreaID"]) not in self.area_map:
                self.area_map[int(r["AreaID"])] = int(r["UiMapID"])
        # Maps whose bounds Forever changed; points taken from Classic-era percentages need converting.
        self.changed = {m for m, b in self.bounds.items() if m in self.era_bounds
                        and any(abs(x - y) > 0.5 for x, y in zip(b, self.era_bounds[m]))}

    @staticmethod
    def _bounds(rows):
        out = {}
        for r in rows:
            if r["OrderIndex"] == "0" and r["WMOGroupID"] == "0":
                out[int(r["UiMapID"])] = (float(r["Region_0"]), float(r["Region_1"]),
                                          float(r["Region_3"]), float(r["Region_4"]), int(r["MapID"]))
        return out

    def from_world(self, ui_map, wx, wy):
        """World (x north, y west) to map percent on ui_map, or None when unknown."""
        b = self.bounds.get(ui_map)
        if not b:
            return None
        x0, y0, x1, y1, _ = b
        return (y1 - wy) / (y1 - y0) * 100, (x1 - wx) / (x1 - x0) * 100

    def era_to_forever(self, ui_map, x, y):
        if ui_map not in self.changed:
            return x, y
        x0, y0, x1, y1, _ = self.era_bounds[ui_map]
        wx, wy = x1 - y / 100 * (x1 - x0), y1 - x / 100 * (y1 - y0)
        return self.from_world(ui_map, wx, wy)

    def locate(self, continent, wx, wy):
        """The zone map (Type 3) or city containing a world point on a continent."""
        best = None
        for r in self.assign:
            if int(r["MapID"]) != continent or r["WMOGroupID"] != "0":
                continue
            ui_map = int(r["UiMapID"])
            if self.info.get(ui_map, {}).get("type") not in (3, 5):
                continue
            x0, y0, x1, y1 = (float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"]))
            if x0 <= wx <= x1 and y0 <= wy <= y1:
                area = (x1 - x0) * (y1 - y0)
                if not best or area < best[0]:
                    best = (area, ui_map)
        return best and best[1]

    def map_of_area(self, area):
        seen = set()
        while area and area not in seen:
            if area in self.area_map:
                return self.area_map[area]
            seen.add(area)
            area = self.area_parent.get(area)
        return None

    def name(self, ui_map):
        return self.info.get(ui_map, {}).get("name", str(ui_map))


def point(ui_map, x, y):
    return {"map": int(ui_map), "x": round(x, 2), "y": round(y, 2)}


def add_points(target, points, tol=0.5):
    """Append points not already within tol of one on the same map; returns how many were new."""
    added = 0
    for p in points:
        if p is None or not (0 <= p["x"] <= 100 and 0 <= p["y"] <= 100):
            continue
        if any(q["map"] == p["map"] and abs(q["x"] - p["x"]) <= tol and abs(q["y"] - p["y"]) <= tol for q in target):
            continue
        target.append(p)
        added += 1
    return added


def nearest(points, others):
    """Smallest distance between a point in points and one on the same map in others."""
    best = None
    for p in points:
        for q in others:
            if p["map"] == q["map"]:
                d = math.hypot(p["x"] - q["x"], p["y"] - q["y"])
                best = d if best is None else min(best, d)
    return best


# --- Questie --------------------------------------------------------------------------

def questie_blacklist():
    """Quest IDs Questie hides on Forever (Expansions.Current is Era there)."""
    path = os.path.join(ADDONS, "Questie", "Database", "Corrections", "QuestieQuestBlacklist.lua")
    if not os.path.isfile(path):
        return set()
    order = {"Era": 1, "Tbc": 2, "Wotlk": 3, "Cata": 4, "MoP": 5}
    out = set()
    for qid, expr in re.findall(r"^\s*\[(\d+)\]\s*=\s*(.+?),\s*(?:--.*)?$", open(path, encoding="utf-8").read(), re.M):
        py = expr.replace("~=", "!=").replace("Expansions.Current", "1")
        py = re.sub(r"Expansions\.(\w+)", lambda m: str(order.get(m.group(1), 99)), py)
        py = py.replace("HIDE_ON_MAP", "False").replace("Questie.IsTitanReforged", "False").replace("Questie.IsChinaRegion", "False")
        if "ContentPhases" in py:
            continue
        try:
            if eval(py, {"__builtins__": {}}, {"true": True, "false": False, "True": True, "False": False}):
                out.add(int(qid))
        except Exception:
            pass
    return out


class Questie:
    def __init__(self, maps):
        base = os.path.join(DB, "questie")
        self.quests = load_json(os.path.join(base, "quests.json"))
        self.npcs = load_json(os.path.join(base, "npcs.json"))
        self.objects = load_json(os.path.join(base, "objects.json"))
        self.items = load_json(os.path.join(base, "items.json"))
        self.drops = load_json(os.path.join(base, "drops.json"))
        self.dungeons = load_json(os.path.join(base, "dungeons.json"))
        zones = load_json(os.path.join(base, "zones.json"))
        self.area_to_map = {int(k): v for k, v in zones["areaIdToUiMapId"].items() if v}
        self.maps = maps
        self.reward_items = defaultdict(list)
        for iid, item in self.items.items():
            for qid in item.get("questRewards") or []:
                self.reward_items[str(qid)].append(int(iid))

    def ui_map(self, area):
        return self.area_to_map.get(int(area))

    def spawns(self, record):
        out = []
        for s in record.get("spawns") or []:
            m = self.ui_map(s["zone"])
            if m:
                out.append(point(m, s["x"], s["y"]))
        return out


# --- ForeverGuide ------------------------------------------------------------------------

class ForeverGuide:
    def __init__(self, maps):
        root = os.path.join(SOURCES, "ForeverGuide")
        data = load_json(os.path.join(root, "data-src", "forever.json"))
        self.quests, self.npcs, self.objects = data["quests"], data["npcs"], data["objects"]
        self.maps = maps

    def positions(self, record):
        out = []
        for m, pts in (record.get("spm") or {}).items():
            out += [point(m, p[-2], p[-1]) for p in pts]
        for m, pts in (record.get("spw") or {}).items():
            for p in pts:
                xy = self.maps.from_world(int(m), p[1], p[2])
                if xy:
                    out.append(point(m, *xy))
        return out


# --- In game (NuuExperiments) -------------------------------------------------------------

# Objective types as the client names them, as this database names them.
INGAME_TYPES = {"monster": "kill", "item": "item", "object": "object", "event": "event", "log": "other"}


class InGame:
    def __init__(self):
        base = os.path.join(DB, "ingame")
        def load(name):
            path = os.path.join(base, name)
            return load_json(path) if os.path.exists(path) else {}
        self.quests, self.npcs, self.objects = load("quests.json"), load("npcs.json"), load("objects.json")
        self.source = load("source.json")

    def quest(self, qid):
        return self.quests.get(str(qid)) or {}

    def refs(self, qid, side):
        return self.quest(qid).get(side) or []

    def missing(self, qid):
        return self.quest(qid).get("exists") is False


# --- RestedXP ------------------------------------------------------------------------------

NUM = r"(-?\d+(?:\.\d+)?)"
GOTO_WORLD = re.compile(r"\.goto\s+(\d+)/\d+\s*,\s*" + NUM + r"\s*,\s*" + NUM)
GOTO_MAP = re.compile(r"\.goto\s+(\d+)\s*,\s*" + NUM + r"\s*,\s*" + NUM)


def rxp_gate(text):
    """The '<< ...' condition on a step or line, as a set of lowercase tokens."""
    m = re.search(r"<<\s*([^\n]*?)\s*$", text)
    if not m:
        return set()
    return {t.strip().lower() for t in re.split(r"[/\s]+", m.group(1)) if t.strip()}


def gate_faction(tokens, default):
    if "horde" in tokens or any(RACE_BY_NAME.get(t, 0) & HORDE_RACES for t in tokens):
        return "Horde"
    if "alliance" in tokens or any(RACE_BY_NAME.get(t, 0) & ALLIANCE_RACES for t in tokens):
        return "Alliance"
    return default


class RestedXP:
    """Quest facts read from RestedXP's Forever guides, keyed by quest ID."""

    def __init__(self, maps):
        self.maps = maps
        self.quests = defaultdict(lambda: {"names": set(), "starts": [], "ends": [], "startTargets": set(),
                                           "endTargets": set(), "parts": defaultdict(lambda: {"positions": [], "mobs": set(), "count": None, "text": None}),
                                           "factions": set(), "classes": set(), "races": set(), "guides": set()})
        guides = os.path.join(ADDONS, "RXPGuides", "Guides", "Forever")
        for path in sorted(glob.glob(os.path.join(guides, "*.lua"))):
            base = os.path.basename(path)
            default = "Horde" if base.startswith("Horde") else "Alliance" if base.startswith("Alliance") else "both"
            self._read(path, base[:-4], default)
        self.flight_times = self._flight_times()

    def _goto(self, line):
        m = GOTO_WORLD.search(line)
        if m:
            xy = self.maps.from_world(int(m.group(1)), float(m.group(3)), float(m.group(2)))
            return point(int(m.group(1)), *xy) if xy else None
        m = GOTO_MAP.search(line)
        if m:
            return point(int(m.group(1)), float(m.group(2)), float(m.group(3)))
        return None

    def _read(self, path, guide, default):
        text = open(path, encoding="utf-8", errors="replace").read()
        for block in re.split(r"\n\s*step\b", text)[1:]:
            lines = block.split("\n")
            step_gate = rxp_gate(lines[0])
            gotos, targets, mobs, actions = [], set(), set(), []
            for line in lines[1:]:
                code = line.split("--")[0] if ".goto" not in line else line
                stripped = code.strip()
                if stripped.startswith(".goto"):
                    p = self._goto(stripped)
                    if p:
                        gotos.append(p)
                elif stripped.startswith(".target"):
                    targets.update(t.strip().lstrip("+") for t in re.sub(r"<<.*$", "", stripped[7:]).split(",") if t.strip())
                elif stripped.startswith(".mob"):
                    mobs.update(t.strip().lstrip("+") for t in re.sub(r"<<.*$", "", stripped[4:]).split(",") if t.strip())
                m = re.match(r"\s*\.(accept|turnin|complete)\s+(\d+)(?:\s*,\s*(\d+))?(.*)$", line)
                if m:
                    actions.append((m.group(1), int(m.group(2)), m.group(3), m.group(4), step_gate | rxp_gate(line)))
            for kind, qid, part, rest, gate in actions:
                q = self.quests[qid]
                q["guides"].add(guide)
                q["factions"].add(gate_faction(gate, default))
                q["classes"].update(t for t in gate if t in CLASS_BY_NAME)
                q["races"].update(t for t in gate if t in RACE_BY_NAME)
                name = re.search(r">>\s*(?:Accept|Turn in)\s+(.+?)\s*(?:<<|$)", rest)
                if name:
                    q["names"].add(name.group(1).strip())
                if kind == "accept":
                    add_points(q["starts"], gotos)
                    q["startTargets"].update(targets)
                elif kind == "turnin":
                    add_points(q["ends"], gotos)
                    q["endTargets"].update(targets)
                elif part:
                    p = q["parts"][int(part)]
                    add_points(p["positions"], gotos)
                    p["mobs"].update(mobs)
                    comment = rest.split("--", 1)[1].strip() if "--" in rest else ""
                    count = re.search(r"\((\d+)\)\s*$", comment)
                    if count:
                        p["count"] = int(count.group(1))
                    if comment:
                        p["text"] = re.sub(r"\s*\(\d+\)\s*$", "", comment)

    def _flight_times(self):
        path = os.path.join(ADDONS, "RXPGuides", "DB", "forever", "flightData.lua")
        text = open(path, encoding="utf-8").read()
        horde = text[text.index('["Horde"]'):]
        horde = horde[:horde.index('["Alliance"]')] if '["Alliance"]' in horde else horde
        times = {}
        for node, body in re.findall(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", horde):
            times[int(node)] = {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", body)}
        return times


# --- Our guides' database -------------------------------------------------------------------

class Ours:
    def __init__(self, maps, questie):
        self.quests = load_json(os.path.join(DB, "quests.json"))
        self.npcs = load_json(os.path.join(DB, "npcs.json"))
        self.maps = maps
        self.questie = questie
        self.converted = set()
        self.kept = set()

    def fix(self, points, reference=()):
        """Convert Classic-bound points on changed maps, unless they already match a Forever reference."""
        out = []
        for p in points:
            x, y = p["x"], p["y"]
            if p["map"] in self.maps.changed:
                cx, cy = self.maps.era_to_forever(p["map"], x, y)
                ref = [q for q in reference if q["map"] == p["map"]]
                if ref and nearest([point(p["map"], x, y)], ref) < nearest([point(p["map"], cx, cy)], ref):
                    self.kept.add((p["map"], x, y))
                else:
                    x, y = cx, cy
                    self.converted.add((p["map"], p["x"], p["y"]))
            out.append(point(p["map"], x, y))
        return out

    def only_faction(self, quest):
        text = " ".join(quest.get("only") or [])
        if re.search(r"(?<!not )\bHorde\b", text) and "Alliance" not in text:
            return "Horde"
        if re.search(r"(?<!not )\bAlliance\b", text) and "Horde" not in text:
            return "Alliance"
        return None


# --- Merge ------------------------------------------------------------------------------------

def bits(mask, table):
    return [name for bit, name in sorted(table.items()) if mask & bit]


def mask_faction(mask):
    if not mask:
        return "both"
    h, a = mask & HORDE_RACES, mask & ALLIANCE_RACES
    return "Horde" if h and not a else "Alliance" if a and not h else "both"


def clean_text(text):
    """ForeverGuide objective text: '|8/8 Prickly Pear Fruit' -> ('Prickly Pear Fruit', 8)."""
    if not text:
        return text, None
    text = text.lstrip("|+ ").strip()
    m = re.match(r"^(\d+)/(\d+)\s+(.*)$", text)
    if m:
        return m.group(3), int(m.group(2))
    return text, None


def singular(name):
    name = name.lower()
    for a, b in (("ies", "y"), ("ves", "f"), ("es", "e"), ("s", "")):
        if name.endswith(a):
            return name[: -len(a)] + b
    return name


def count_in_text(text, name):
    """'Bring 8 Windfury Talons' -> 8 for 'Windfury Talon'."""
    if not text or not name:
        return None
    target = singular(name)
    for m in re.finditer(r"(\d+)\s+([A-Z][\w' -]+?)(?=[,.]| and | to | from | for | in |$)", text):
        words = m.group(2).strip()
        if singular(words).startswith(target[: max(4, len(target) - 2)]) or target.startswith(singular(words)[:6]):
            return int(m.group(1))
    return None


class Builder:
    def __init__(self):
        self.maps = Maps()
        self.questie = Questie(self.maps)
        self.fg = ForeverGuide(self.maps)
        self.rxp = RestedXP(self.maps)
        self.ours = Ours(self.maps, self.questie)
        self.ig = InGame()
        # Chains: the quests the server offers straight after each one, turned round; and Questie's breadcrumbs
        # by the quest they lead to (a breadcrumb names its target; the target does not always name it back).
        self.server_into = defaultdict(list)
        for k, q in self.ig.quests.items():
            if q.get("next"):
                self.server_into[q["next"]].append(int(k))
        self.breadcrumbs_to = defaultdict(list)
        for k, q in self.questie.quests.items():
            if q.get("breadcrumbForQuestId"):
                self.breadcrumbs_to[q["breadcrumbForQuestId"]].append(int(k))
        forever = os.path.join(SOURCES, "wago", "forever")
        self.client_quests = {int(r["ID"]) for r in load_csv(os.path.join(forever, "QuestV2.csv"))}
        self.sorts = {int(r["ID"]): r["SortName_lang"] for r in load_csv(os.path.join(forever, "QuestSort.csv"))}
        self.quest_lines = self._quest_lines(forever)
        self.blacklist = questie_blacklist()
        self.npc_names = self._npc_names()
        self.quests, self.npcs, self.objects, self.items = {}, {}, {}, {}
        self.rxp_seen = defaultdict(list)   # NPC -> where RestedXP found it, when Classic has it elsewhere
        self.report = defaultdict(list)

    def _quest_lines(self, folder):
        names = {int(r["ID"]): r["Name_lang"] for r in load_csv(os.path.join(folder, "QuestLine.csv"))}
        out = {}
        for r in load_csv(os.path.join(folder, "QuestLineXQuest.csv")):
            out[int(r["QuestID"])] = {"id": int(r["QuestLineID"]), "name": names.get(int(r["QuestLineID"])),
                                      "order": int(r["OrderIndex"])}
        return out

    def _npc_names(self):
        by_name = defaultdict(set)
        for src in (self.questie.npcs, self.fg.npcs, self.ours.npcs, self.ig.npcs):
            for nid, n in src.items():
                name = n.get("name") or n.get("n")
                if name:
                    by_name[name.lower()].add(int(nid))
        return by_name

    # ---- NPC positions from every source

    def npc_positions(self, nid):
        """(positions, sources, conflict) for an NPC, Forever-observed points first."""
        key = str(nid)
        classic = self.questie.spawns(self.questie.npcs.get(key, {}))
        observed, srcs = [], []
        if add_points(observed, self.ig.npcs.get(key, {}).get("positions", [])):
            srcs.append("ingame")
        if key in self.ours.npcs:
            if add_points(observed, self.ours.fix(self.ours.npcs[key]["positions"], classic)) or self.ours.npcs[key]["positions"]:
                srcs.append("ours")
        if key in self.fg.npcs and add_points(observed, self.fg.positions(self.fg.npcs[key])):
            srcs.append("fg")
        if add_points(observed, self.rxp_seen.get(int(nid), [])):
            srcs.append("rxp")
        conflict = None
        if not observed:
            return classic, (["questie"] if classic else []), None
        if not classic:
            return observed, srcs, None
        maps_seen = {p["map"] for p in observed}
        per_map = defaultdict(int)
        for p in classic:
            per_map[p["map"]] += 1
        out = list(observed)
        for m, n in per_map.items():
            pts = [p for p in classic if p["map"] == m]
            if m not in maps_seen or n >= 3:
                add_points(out, pts, tol=1.0)       # other maps, or a mob with many spawns: keep all
            else:
                d = nearest([p for p in observed if p["map"] == m], pts)
                if d is not None and d > 3:
                    conflict = round(d, 1)
        return out, srcs + ["questie"], conflict

    def resolve_npc(self, name, near=()):
        ids = self.npc_names.get(name.lower())
        if not ids:
            return None
        if len(ids) == 1 or not near:
            return min(ids)
        return min(ids, key=lambda i: nearest(near, self.npc_positions(i)[0]) or 1e9)

    # ---- Selection

    def horde_friendly(self, nid):
        f = self.questie.npcs.get(str(nid), {}).get("friendlyToFaction")
        return f is None or "H" in str(f)

    def select(self):
        chosen = {}
        # Classic quests from Questie.
        for qid, q in self.questie.quests.items():
            iq = int(qid)
            if q.get("faction") == "Alliance":
                continue
            level = q.get("requiredLevel") or (q.get("questLevel") if (q.get("questLevel") or 0) > 0 else 1)
            if level > MAX_LEVEL or (q.get("questLevel") or 0) > MAX_QUEST_LEVEL:
                continue
            if iq in self.blacklist:
                self.report["blacklisted"].append(iq)
                continue
            if self.ig.missing(iq):
                self.report["serverMissing"].append((iq, q["name"]))
                continue
            if iq not in self.client_quests:
                self.report["notInClient"].append((iq, q["name"]))
                continue
            starts = q.get("starts", {})
            npcs = starts.get("npcs", [])
            if npcs and not any(self.horde_friendly(n) for n in npcs) and not starts.get("objects") and not starts.get("items"):
                continue
            if not starts:
                self.report["noStarter"].append((iq, q["name"]))
            chosen[iq] = "questie"
        # Forever quests Questie does not know.
        for qid, q in self.fg.quests.items():
            iq = int(qid)
            if iq in chosen or qid in self.questie.quests:
                continue
            if JUNK.search(q.get("n") or "None"):
                self.report["junk"].append((iq, q.get("n")))
                continue
            faction, level, where = self.custom_faction(iq, q)
            if faction == "Alliance":
                continue
            if level is None or level > MAX_LEVEL + 2:
                if level is None:
                    self.report["customNoLevel"].append((iq, q.get("n")))
                continue
            if faction is None:
                self.report["customNoFaction"].append((iq, q.get("n"), level, where))
                continue
            chosen[iq] = "fg"
        # Anything our guides or RestedXP's Horde routes use that is still missing.
        # And quests a Horde character was offered in game.
        recorded = [int(k) for k, q in self.ig.quests.items() if q.get("starts") or q.get("startItem")]
        for iq in [int(k) for k in self.ours.quests] + list(self.rxp.quests) + recorded:
            if iq in chosen or self.ig.missing(iq):
                continue
            faction, level, where = self.custom_faction(iq, self.fg.quests.get(str(iq), {}))
            if faction in ("Horde", "both"):
                chosen[iq] = "guides"
        # A quest chained to one we placed shares its faction: follow ForeverGuide's prerequisites
        # both ways until nothing changes.
        links = defaultdict(set)
        for qid, q in self.fg.quests.items():
            for p in q.get("pre") or []:
                links[int(qid)].add(int(p))
                links[int(p)].add(int(qid))
        pending = {e[0]: e for e in self.report["customNoFaction"]}
        changed = True
        while changed:
            changed = False
            for qid in list(pending):
                if any(n in chosen for n in links[qid]):
                    chosen[qid] = "chain"
                    del pending[qid]
                    changed = True
        self.report["customNoFaction"] = list(pending.values())
        return chosen

    def in_scope(self, rec):
        """Whether a built quest belongs in a Horde 1-20 route, and why not when it does not."""
        if rec["category"] in ("event", "pvp"):
            return False, rec["category"]
        if (rec.get("level") or 0) > MAX_QUEST_LEVEL:
            return False, "level"
        if rec["category"] in ("class", "profession") or rec.get("classes"):
            return True, None
        zone = rec.get("zone") or {}
        if rec["category"] == "dungeon":
            return zone.get("name") in SCOPE_DUNGEONS, "dungeon"
        if zone.get("map") is None:
            return True, None        # unplaced Forever quest: keep it, the report lists it
        return zone["map"] in SCOPE_MAPS, "zone"

    def custom_faction(self, qid, fgq):
        """(faction, level, map) for a quest Questie does not have."""
        faction = None
        ours = self.ours.quests.get(str(qid))
        if ours:
            # Our guides are played as Horde; the Skyborne one serves both factions.
            faction = self.ours.only_faction(ours) or (
                "Horde" if any(g.startswith("Horde") for g in ours.get("guides", [])) else "both")
        rx = self.rxp.quests.get(qid)
        if rx and not faction:
            # A step without a faction gate means both can take it.
            fs = rx["factions"]
            faction = "both" if "both" in fs or len(fs) > 1 else (next(iter(fs)) if fs else None)
        where = None
        spots = self.fg.positions(fgq.get("start", {})) + (rx["starts"] if rx else [])
        for n in fgq.get("snpc") or []:
            spots += self.npc_positions(n)[0]
        for r in self.ig.refs(qid, "starts"):
            if "npc" in r:
                spots += self.npc_positions(r["npc"])[0]
        if ours:
            for s in ours["starts"]:
                if "npc" in s:
                    spots += self.npc_positions(s["npc"])[0]
                spots += s.get("positions", [])
        if spots:
            where = spots[0]["map"]
            if not faction:
                if where in HORDE_MAPS:
                    faction = "Horde"
                elif where in ALLIANCE_MAPS:
                    faction = "Alliance"
        if fgq.get("classes") and not faction:
            faction = "both"
        return faction, fgq.get("lvl") or self.ig.quest(qid).get("level"), where

    # ---- Quest records

    def ender_or_starter(self, q_ids, fg_rec, rx_points, rx_targets, ours_list, questie_ref, ig_refs=()):
        out = []
        seen = set()
        near = list(rx_points)
        for s in ours_list or []:
            near += s.get("positions", [])
        # Who the client showed offering or taking in the quest comes first.
        npc_ids = [r["npc"] for r in ig_refs if "npc" in r]
        npc_ids += questie_ref.get("npcs", [])
        npc_ids += fg_rec.get("snpc" if q_ids == "start" else "enpc", []) if isinstance(fg_rec, dict) else []
        for s in ours_list or []:
            if "npc" in s:
                npc_ids.append(s["npc"])
        targets = list(rx_targets)
        if len(targets) > 1:
            # A step that names several NPCs serves several quests; keep the one standing at the
            # step, and only when no other source names this quest's NPC.
            if npc_ids or not rx_points:
                targets = []
            else:
                resolved = [(n, self.resolve_npc(n, rx_points)) for n in targets]
                resolved = [(n, i) for n, i in resolved if i]
                targets = [min(resolved, key=lambda r: nearest(rx_points, self.npc_positions(r[1])[0]) or 1e9)[0]] if resolved else []
        for name in targets:
            nid = self.resolve_npc(name, near)
            if nid:
                npc_ids.append(nid)
                # RestedXP stood next to this NPC on Forever; if nothing else puts it there, it moved.
                if len(targets) == 1 and rx_points:
                    known = self.npc_positions(nid)[0]
                    d = nearest(rx_points, known)
                    if d is None or d > 3:
                        add_points(self.rxp_seen[nid], rx_points)
        fg_side = fg_rec.get("start" if q_ids == "start" else "fin", {}) if isinstance(fg_rec, dict) else {}
        if fg_side.get("n") and not npc_ids:
            nid = self.resolve_npc(fg_side["n"].lstrip("+"), self.fg.positions(fg_side))
            if nid:
                npc_ids.append(nid)
        for nid in npc_ids:
            if nid in seen:
                continue
            seen.add(nid)
            self.want_npc(nid)
            out.append({"npc": int(nid)})
        for oid in [r["object"] for r in ig_refs if "object" in r] + list(questie_ref.get("objects", [])):
            if {"object": int(oid)} in out:
                continue
            self.want_object(oid)
            out.append({"object": int(oid)})
        for iid in questie_ref.get("items", []):
            self.want_item(iid)
            out.append({"item": int(iid)})
        for s in ours_list or []:
            if "object" in s:
                oid = self.resolve_object(s["object"], self.ours.fix(s.get("positions", [])))
                if oid and {"object": oid} not in out:
                    self.want_object(oid)
                    out.append({"object": oid})
                elif not oid:
                    out.append({"objectName": s["object"], "positions": self.ours.fix(s.get("positions", []))})
            if "item" in s and {"item": s["item"]} not in out:
                self.want_item(s["item"])
                out.append({"item": s["item"]})
        if not out:
            pts = []
            add_points(pts, self.fg.positions(fg_side))
            add_points(pts, rx_points)
            if pts:
                out.append({"name": (fg_side.get("n") or (sorted(rx_targets)[0] if rx_targets else "")).lstrip("+") or None,
                            "positions": pts})
        return out

    def resolve_object(self, name, near):
        best = None
        for oid, o in self.questie.objects.items():
            if (o.get("name") or "").lower() == name.lower():
                d = nearest(near, self.questie.spawns(o)) if near else 0
                if best is None or (d is not None and d < best[0]):
                    best = (d if d is not None else 1e9, int(oid))
        return best and best[1]

    def objectives(self, qid, qq, oq, fgq, rx, igq=None):
        """Merged objective list; each entry says what to do, how many, and where."""
        out = []
        text = " ".join(qq.get("text", []) if qq else [])
        ob = (qq or {}).get("objectives", {})
        for o in ob.get("kill", []):
            self.want_npc(o["npc"])
            out.append({"type": "kill", "npc": o["npc"], "text": o.get("text")})
        for o in ob.get("killCredit", []):
            for n in o.get("npcs") or []:
                self.want_npc(n)
            out.append({"type": "killCredit", "npcs": o.get("npcs"), "creditNpc": o.get("creditNpc"), "text": o.get("text")})
        for o in ob.get("object", []):
            self.want_object(o["object"])
            out.append({"type": "object", "object": o["object"], "text": o.get("text")})
        for o in ob.get("item", []):
            self.want_item(o["item"])
            out.append({"type": "item", "item": o["item"], "text": o.get("text")})
        for o in ob.get("spell", []):
            out.append({"type": "spell", "spell": o.get("spell"), "item": o.get("item"), "text": o.get("text")})
        if ob.get("reputation"):
            out.append({"type": "reputation", **ob["reputation"]})
        if qq and qq.get("explore"):
            out.append({"type": "explore", "text": qq["explore"].get("text"), "positions": qq["explore"]["positions"]})

        # Our guides: in-game objective index, count, positions.
        for part in (oq or {}).get("objectives", []):
            match = None
            for o in out:
                if o["type"] == "kill" and o.get("npc") in part.get("kill", []) and not part.get("collect"):
                    match = o
                if o["type"] == "item" and any(c["item"] == o.get("item") for c in part.get("collect", [])):
                    match = o
            if match is None:
                match = {"type": "item" if part.get("collect") else "kill" if part.get("kill") else "talk" if part.get("npc") else "other"}
                if part.get("collect"):
                    match["item"] = part["collect"][0]["item"]
                    match["name"] = part["collect"][0].get("name")
                    self.want_item(match["item"])
                elif part.get("kill"):
                    match["npc"] = part["kill"][0]
                if part.get("npc"):
                    match["npcs"] = part["npc"]
                    for n in part["npc"]:
                        self.want_npc(n)
                out.append(match)
            if part.get("kill") and match["type"] == "item":
                match["from"] = sorted(set(match.get("from", [])) | set(part["kill"]))
            for n in part.get("kill", []):
                self.want_npc(n)
            match["index"] = part.get("part")
            if part.get("count"):
                match["count"] = part["count"]
                match.setdefault("src", []).append("ours")
            add_points(match.setdefault("positions", []), self.ours.fix(part.get("positions", [])))

        # RestedXP: index, count and areas by objective number.
        if rx:
            for index, part in sorted(rx["parts"].items()):
                match = next((o for o in out if o.get("index") == index), None)
                if match is None:
                    match = next((o for o in out if "index" not in o and o["type"] in ("kill", "item", "object")
                                  and part["text"] and self._name_of(o) and self._name_of(o).lower() in part["text"].lower()), None)
                if match is None:
                    match = {"type": "other", "text": part["text"]}
                    out.append(match)
                match["index"] = index
                if part["count"] and not match.get("count"):
                    match["count"] = part["count"]
                    match.setdefault("src", []).append("rxp")
                add_points(match.setdefault("positions", []), part["positions"])
                mobs = [self.resolve_npc(m, part["positions"]) for m in part["mobs"]]
                for n in filter(None, mobs):
                    self.want_npc(n)
                    if match["type"] == "item":
                        match["from"] = sorted(set(match.get("from", [])) | {n})

        # ForeverGuide: recorded objective texts and areas.
        for i, o in enumerate((fgq or {}).get("obj", [])):
            match = None
            name = clean_text(o.get("name") or o.get("text") or "")[0]
            for m in out:
                n = self._name_of(m)
                if n and name and (n.lower() in name.lower() or name.lower() in n.lower()):
                    match = m
            if match is None and len(out) == len((fgq or {}).get("obj", [])):
                match = out[i]
            if match is None:
                match = {"type": {"kill": "kill", "item": "item", "object": "object", "event": "event"}.get(o.get("kind"), "other"),
                         "text": clean_text(o.get("text"))[0]}
                if o.get("id"):
                    match[{"kill": "npc", "item": "item", "object": "object"}.get(o.get("kind"), "id")] = o["id"]
                out.append(match)
            text, count = clean_text(o.get("text"))
            count = o.get("count") or count
            if count and not match.get("count"):
                match["count"] = count
                match.setdefault("src", []).append("fg")
            if not match.get("text"):
                match["text"] = text
            add_points(match.setdefault("positions", []), self.fg.positions(o))
            for n in o.get("near") or []:
                self.want_npc(n)

        # In game: the client's own objectives, by index; its counts win.
        ig_objectives = [o for o in (igq or {}).get("objectives", []) if o.get("type") or o.get("text") or o.get("count")]
        for o in ig_objectives:
            index = o["index"]
            match = next((m for m in out if m.get("index") == index), None)
            if match is None and o.get("text"):
                name = o["text"].lower()
                match = next((m for m in out if "index" not in m and self._name_of(m)
                              and self._name_of(m).lower() in name), None)
            if match is None and len(out) == len(ig_objectives) and "index" not in out[index - 1]:
                match = out[index - 1]
            if match is None:
                match = {"type": INGAME_TYPES.get(o.get("type"), "other")}
                if o.get("text"):
                    match["text"] = o["text"]
                out.append(match)
            match["index"] = index
            if o.get("count"):
                if match.get("count") and match["count"] != o["count"]:
                    self.report["countChanged"].append((qid, index, match["count"], o["count"]))
                match["count"] = o["count"]
                match.setdefault("src", []).append("ingame")
            if o.get("text"):
                match["text"] = o["text"]
            add_points(match.setdefault("positions", []), o.get("positions", []))
            votes = sorted(((v, int(n)) for n, v in (o.get("targets") or {}).items()), reverse=True)
            if votes:
                if match["type"] == "kill" and "npc" not in match:
                    match["npc"] = votes[0][1]
                    self.want_npc(votes[0][1])
                elif match["type"] == "item":
                    for _, n in votes:
                        self.want_npc(n)
                    match["from"] = sorted(set(match.get("from", [])) | {n for _, n in votes})

        # Counts still missing: read them from the quest text.
        for o in out:
            if o.get("text"):
                o["text"], shown = clean_text(o["text"])
                if shown and not o.get("count"):
                    o["count"] = shown
                    o.setdefault("src", []).append("text")
            elif "text" in o:
                del o["text"]
            if not o.get("count") and o["type"] in ("kill", "item", "object"):
                c = count_in_text(text, self._name_of(o))
                if c:
                    o["count"] = c
                    o.setdefault("src", []).append("text")
            # Where to go: the objective's own area, else its NPC or object spawns.
            if not o.get("positions"):
                pts = []
                if o["type"] == "kill" and "npc" in o:
                    pts = self.npc_positions(o["npc"])[0]
                elif o["type"] == "object" and "object" in o:
                    pts = self.questie.spawns(self.questie.objects.get(str(o["object"]), {}))
                elif o["type"] == "item" and "item" in o:
                    for n in self._item_sources(o["item"]) + o.get("from", []):
                        add_points(pts, self.npc_positions(n)[0], tol=1.0)
                    for oid in self.questie.items.get(str(o["item"]), {}).get("objectDrops") or []:
                        self.want_object(oid)
                        add_points(pts, self.questie.spawns(self.questie.objects.get(str(oid), {})), tol=1.0)
                if pts:
                    o["positions"] = pts
                    o["positionsFrom"] = "spawns"
            if not o.get("positions"):
                o.pop("positions", None)
        return out

    def _name_of(self, o):
        if o.get("name"):
            return o["name"]
        if o["type"] == "kill" and "npc" in o:
            return (self.questie.npcs.get(str(o["npc"])) or self.ours.npcs.get(str(o["npc"])) or {}).get("name")
        if o["type"] == "item" and "item" in o:
            return self.questie.items.get(str(o["item"]), {}).get("name")
        if o["type"] == "object" and "object" in o:
            return self.questie.objects.get(str(o["object"]), {}).get("name")
        return o.get("text")

    def _item_sources(self, iid):
        item = self.questie.items.get(str(iid), {})
        rates = self.questie.drops.get(str(iid), {})
        npcs = [int(n) for n in item.get("npcDrops") or []] + [int(n) for n in rates]
        for n in npcs:
            self.want_npc(n)
        return sorted(set(npcs))

    def build_quest(self, qid, origin):
        key = str(qid)
        qq, oq, fgq = self.questie.quests.get(key), self.ours.quests.get(key), self.fg.quests.get(key, {})
        rx = self.rxp.quests.get(qid)
        igq = self.ig.quest(qid)
        rec = {}
        names = [n for n in (igq.get("name"), (fgq or {}).get("n"), (qq or {}).get("name"), (oq or {}).get("name")) if n]
        if rx:
            names += sorted(rx["names"])
        rec["name"] = names[0].rstrip(".") if names else None
        forever_level = igq.get("level") or fgq.get("lvl")
        if forever_level is not None:
            rec["level"] = forever_level
            if qq and qq.get("questLevel") not in (None, forever_level) and qq.get("questLevel", 0) > 0:
                self.report["levelChanged"].append((qid, rec["name"], qq["questLevel"], forever_level))
        elif qq and "questLevel" in qq:
            rec["level"] = qq["questLevel"]
        if igq.get("minLevel"):
            rec["minLevel"] = igq["minLevel"]
        elif qq and qq.get("requiredLevel"):
            rec["minLevel"] = qq["requiredLevel"]
        elif fgq.get("req"):
            rec["minLevel"] = fgq["req"]
        if qq and qq.get("requiredMaxLevel"):
            rec["maxLevel"] = qq["requiredMaxLevel"]

        if qq:
            rec["faction"] = qq["faction"]
            if qq.get("races"):
                rec["races"] = qq["races"]
            if qq.get("classes"):
                rec["classes"] = qq["classes"]
        else:
            rec["faction"] = self.custom_faction(qid, fgq)[0] or "both"
            classes = set(bits(fgq.get("classes", 0), CLASSES))
            if rx:
                classes |= {CLASSES[CLASS_BY_NAME[c]] for c in rx["classes"]}
            if oq:
                for g in oq.get("guides") or []:
                    classes.update(CLASSES[CLASS_BY_NAME[t.lower()]] for t in g.split() if t.lower() in CLASS_BY_NAME)
                for o in oq.get("only") or []:
                    for token in re.findall(r"[A-Za-z]+", o):
                        if token.lower() in CLASS_BY_NAME and "not " + token not in o:
                            classes.add(CLASSES[CLASS_BY_NAME[token.lower()]])
            if classes:
                rec["classes"] = sorted(classes)
        # What the server said (the quest cache) wins: races as Forever has them (Troll druids, the Skyborne), the
        # faction where the races limit it, and the class a class quest is filed under.
        if "flags" in igq:
            rec.pop("races", None)
            if igq.get("races"):
                rec["races"] = igq["races"]
            if igq.get("faction"):
                rec["faction"] = igq["faction"]
            sort_name = self.sorts.get(-igq.get("sort", 0), "") if igq.get("sort", 0) < 0 else ""
            if sort_name.lower() in CLASS_BY_NAME:
                rec["classes"] = sorted(set(rec.get("classes", [])) | {CLASSES[CLASS_BY_NAME[sort_name.lower()]]})
            if igq.get("type"):
                rec["type"] = igq["type"]

        rec["starts"] = self.ender_or_starter("start", fgq, rx["starts"] if rx else [], rx["startTargets"] if rx else [],
                                              (oq or {}).get("starts"), (qq or {}).get("starts", {}), igq.get("starts", []))
        rec["ends"] = self.ender_or_starter("end", fgq, rx["ends"] if rx else [], rx["endTargets"] if rx else [],
                                            (oq or {}).get("ends"), (qq or {}).get("ends", {}), igq.get("ends", []))
        if igq.get("startItem") and {"item": igq["startItem"]} not in rec["starts"]:
            self.want_item(igq["startItem"])
            rec["starts"].append({"item": igq["startItem"]})
        objectives = self.objectives(qid, qq, oq, fgq, rx, igq)
        if objectives:
            rec["objectives"] = objectives
        if qq and qq.get("text"):
            rec["text"] = qq["text"]

        prereqs = self.prereqs(qid, qq, fgq)
        if prereqs:
            rec["prereqs"] = prereqs
        following = igq.get("next") or (qq or {}).get("nextQuestInChain")
        if igq.get("next") and qq and qq.get("nextQuestInChain") and igq["next"] != qq["nextQuestInChain"]:
            self.report["nextChanged"].append((qid, rec["name"], qq["nextQuestInChain"], igq["next"]))
        if following and following != qid:
            rec["next"] = following
        for src, dst in (("exclusiveTo", "exclusiveWith"), ("breadcrumbForQuestId", "breadcrumbFor"),
                         ("parentQuest", "parent"),
                         ("childQuests", "children"), ("inGroupWith", "groupWith"),
                         ("availableUntilCompleted", "unavailableAfter"), ("availableStartingWith", "availableWith"),
                         ("disabledByQuest", "disabledBy"), ("requiredSkill", "requiresSkill"),
                         ("requiredMinRep", "requiresRep"), ("requiredMaxRep", "requiresRepBelow"),
                         ("requiredSpell", "requiresSpell"), ("sourceItemId", "providesItem"),
                         ("requiredSourceItems", "requiresItems"), ("reputationReward", "reputation"),
                         ("questFlags", "questFlags"), ("specialFlags", "specialFlags")):
            if qq and qq.get(src):
                rec[dst] = qq[src]
        if igq.get("providesItem"):
            rec["providesItem"] = igq["providesItem"]
            self.want_item(igq["providesItem"])
        if "flags" in igq:
            rec["questFlags"] = igq["flags"]
        if qid in self.quest_lines:
            rec["questLine"] = self.quest_lines[qid]
        # XP: ours is worked out the way the client does it from what the server sent (QuestExport.py), or is
        # what a turn-in paid, so it wins over Questie's, which predates Forever's changes.
        ig_xp, questie_xp = igq.get("xp"), (qq.get("xp") if qq else None)
        if ig_xp:
            rec["xp"] = ig_xp
            rec["xpFrom"] = {"server": "client formula", "turnin": "turn-in", "scan": "scan"}.get(igq.get("xpFrom"), "in game")
            if igq.get("xpScaledFrom"):
                rec["xpFrom"] += ", scaled up from level %d" % igq["xpScaledFrom"]
            if questie_xp and questie_xp != ig_xp:
                self.report["xpChanged"].append((qid, rec["name"], questie_xp, ig_xp, rec["xpFrom"], igq.get("xpMultiplier")))
        elif questie_xp:
            rec["xp"] = questie_xp
            if qq.get("xpLevel"):
                rec["xpLevel"] = qq["xpLevel"]
        rewards = self.questie.reward_items.get(key)
        if rewards:
            rec["rewardItems"] = sorted(rewards)
            for iid in rewards:
                self.want_item(iid)

        rec["zone"], rec["category"] = self.zone_of(qq, rec, igq)
        if not qq and rec.get("classes") and rec["category"] in ("zone", "other") and not (rec["zone"] or {}).get("map"):
            rec["category"] = "class"
        if oq:
            if oq.get("notes"):
                rec["notes"] = oq["notes"]
            if oq.get("guides"):
                rec["guides"] = oq["guides"]
            if oq.get("only"):
                rec["guideConditions"] = oq["only"]
        if rx:
            rec["rxpGuides"] = sorted(rx["guides"])
        rec["src"] = [s for s, have in (("questie", qq), ("fg", fgq), ("rxp", rx), ("ours", oq), ("ingame", igq)) if have]
        rec["missing"] = self.missing(rec)
        return rec

    def has_objectives(self, qid):
        """True or False from the scan; None when the scan never answered for it."""
        q = self.ig.quest(qid)
        if not q.get("exists"):
            return None
        return any(o.get("type") or o.get("text") or o.get("count") for o in q.get("objectives", []))

    def prereqs(self, qid, qq, fgq):
        """What must be turned in before this quest, and what only leads here.

        all          every one of these first
        anyOf        at least one of these first
        breadcrumbs  optional quests that send the player here; none is needed
        maybe        the server offers this quest straight after one of these, which has no objectives: either a
                     prerequisite or an optional breadcrumb, the data cannot say (about a quarter of such links
                     in Classic are breadcrumbs)
        src          where it came from: questie (Classic's chains), server (the quest cache's next-quest
                     links, which confirm or add), foreverguide (its "one of" lists, from RestedXP's routes)

        A link from a quest with objectives is a prerequisite: of the 137 Questie breadcrumbs on the server, one
        has objectives. Quests the server does not have are left out (the report lists them)."""
        out = {"all": [], "anyOf": [], "breadcrumbs": [], "maybe": []}
        src = []
        if qq:
            out["all"] = list(qq.get("preQuestGroup") or [])
            out["anyOf"] = list(qq.get("preQuestSingle") or [])
            out["breadcrumbs"] = sorted(set(qq.get("breadcrumbs") or []) | set(self.breadcrumbs_to.get(qid, [])))
            if any(out.values()):
                src.append("questie")
        known = set(out["all"]) | set(out["anyOf"]) | set(out["breadcrumbs"])
        into = [a for a in self.server_into.get(qid, []) if a != qid]
        if any(a in known for a in into):
            src.append("server")
        new = [a for a in into if a not in known]
        if new:
            if qq:
                # Questie has the quest and no such link: Forever may have added it; not sure what it is.
                out["maybe"] += new
                self.report["serverLinkNew"].append((qid, new))
            else:
                strong = [a for a in new if self.has_objectives(a)]
                out["maybe"] += [a for a in new if a not in strong]
                if len(strong) == 1 and not out["all"] and not out["anyOf"]:
                    out["all"] = strong
                else:
                    out["anyOf"] += strong
            if "server" not in src:
                src.append("server")
        if not out["all"] and not out["anyOf"] and fgq.get("pre"):
            out["anyOf"] = [p for p in fgq["pre"] if p not in known and p not in out["maybe"]]
            if out["anyOf"]:
                src.append("foreverguide")
        result = {}
        for k, ids in out.items():
            kept = []
            for p in ids:
                if p == qid or p in kept:
                    continue
                if self.ig.missing(p):
                    self.report["prereqGone"].append((qid, k, p))
                    continue
                kept.append(p)
            if kept:
                result[k] = sorted(kept)
        if result:
            result["src"] = src
        return result

    def zone_of(self, qq, rec, igq=None):
        sort = (igq or {}).get("sort") or (qq or {}).get("zoneOrSort")
        category = "zone"
        zone = None
        if sort and sort < 0:
            name = self.sorts.get(-sort, "")
            category = ("class" if name.lower() in CLASS_BY_NAME else
                        "event" if any(e.lower() in name.lower() for e in EVENT_SORTS) else "profession" if name in (
                            "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
                            "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring", "Camping") else "other")
            zone = {"sort": name}
        elif sort:
            ui_map = self.questie.ui_map(sort) or self.maps.map_of_area(sort)
            dungeon = str(sort) in self.questie.dungeons
            category = "dungeon" if dungeon else "zone"
            zone = {"map": ui_map, "name": self.questie.dungeons[str(sort)]["name"] if dungeon else self.maps.name(ui_map)} if ui_map or dungeon else None
        if not zone or category in ("class", "profession", "other"):
            pts = self.where(rec["starts"])
            if pts:
                m = pts[0]["map"]
                zone = dict(zone or {}, map=m, name=self.maps.name(m))
        if rec.get("name", "").startswith("Camping 101"):
            category = "profession"
        return zone, category

    def where(self, refs):
        pts = []
        for r in refs:
            if "npc" in r:
                pts += self.npc_positions(r["npc"])[0]
            elif "object" in r:
                pts += self.questie.spawns(self.questie.objects.get(str(r["object"]), {}))
            pts += r.get("positions", [])
        return pts

    def missing(self, rec):
        miss = []
        if rec.get("level") is None:
            miss.append("level")
        if "xp" not in rec:
            miss.append("xp")
        if not rec["starts"]:
            miss.append("starts")
        elif not self.where(rec["starts"]) and not any("item" in s for s in rec["starts"]):
            miss.append("startPosition")
        if not rec["ends"]:
            miss.append("ends")
        elif not self.where(rec["ends"]):
            miss.append("endPosition")
        objectives = rec.get("objectives", [])
        if not objectives and not rec.get("text"):
            miss.append("objectives?")
        for o in objectives:
            if o["type"] in ("kill", "item", "object") and not o.get("count"):
                miss.append("count")
                break
        for o in objectives:
            if o["type"] != "reputation" and not o.get("positions"):
                miss.append("objectivePosition")
                break
        return miss

    # ---- Referenced records

    def want_npc(self, nid):
        if nid is not None:
            self.npcs.setdefault(int(nid), None)

    def want_object(self, oid):
        if oid is not None:
            self.objects.setdefault(int(oid), None)

    def want_item(self, iid):
        if iid is not None:
            self.items.setdefault(int(iid), None)

    def build_npc(self, nid, quest_ids):
        key = str(nid)
        qn, on, fn = self.questie.npcs.get(key, {}), self.ours.npcs.get(key, {}), self.fg.npcs.get(key, {})
        ign = self.ig.npcs.get(key, {})
        rec = {"name": ign.get("name") or qn.get("name") or on.get("name") or fn.get("n")}
        for k in ("subName", "minLevel", "maxLevel", "rank", "roles", "friendlyToFaction", "factionID", "waypoints"):
            if qn.get(k):
                rec[k] = qn[k]
        if fn.get("lvl") and "minLevel" not in rec:
            rec["minLevel"] = rec["maxLevel"] = fn["lvl"]
        positions, srcs, conflict = self.npc_positions(nid)
        rec["positions"] = positions
        rec["positionSrc"] = srcs
        if conflict:
            rec["positionConflict"] = conflict
            self.report["npcMoved"].append((nid, rec["name"], conflict))
        starts = sorted(q for q in (qn.get("questStarts") or []) + (fn.get("starts") or []) if q in quest_ids)
        ends = sorted(q for q in (qn.get("questEnds") or []) + (fn.get("ends") or []) if q in quest_ids)
        if starts:
            rec["questStarts"] = starts
        if ends:
            rec["questEnds"] = ends
        return rec

    def build_object(self, oid):
        o = self.questie.objects.get(str(oid), {})
        rec = {"name": o.get("name"), "positions": self.questie.spawns(o)}
        igo = self.ig.objects.get(str(oid))
        if igo:
            rec["name"] = igo.get("name") or rec["name"]
            positions = list(igo.get("positions", []))
            add_points(positions, rec["positions"])
            rec["positions"] = positions
        fo = self.fg.objects.get(str(oid))
        if fo:
            rec["name"] = rec["name"] or fo.get("n")
            add_points(rec["positions"], self.fg.positions(fo))
        return rec

    def build_item(self, iid):
        i = self.questie.items.get(str(iid), {})
        rec = {"name": i.get("name")}
        for k in ("itemLevel", "requiredLevel", "class", "subClass", "startQuest", "vendors", "objectDrops", "itemDrops"):
            if i.get(k):
                rec[k] = i[k]
        rates = self.questie.drops.get(str(iid), {})
        drops = sorted(set(int(n) for n in (i.get("npcDrops") or [])) | {int(n) for n in rates})
        if drops:
            rec["dropsFrom"] = [{"npc": n, **({"chance": rates[str(n)]} if str(n) in rates else {})} for n in drops]
        for n in i.get("vendors") or []:
            self.want_npc(n)
        return rec

    def service_npcs(self):
        """Vendors, trainers, flight masters and the like, friendly to the Horde, on maps we cover."""
        maps = {q["zone"]["map"] for q in self.quests.values() if q.get("zone") and q["zone"].get("map")}
        for nid, n in self.questie.npcs.items():
            if not (set(n.get("roles", [])) & SERVICE_ROLES) or "H" not in str(n.get("friendlyToFaction", "")):
                continue
            if any(p["map"] in maps for p in self.questie.spawns(n)):
                self.want_npc(int(nid))

    def flight_paths(self):
        rows = load_csv(os.path.join(SOURCES, "wago", "forever", "TaxiNodes.csv"))
        nodes = {}
        for r in rows:
            flags = int(r["Flags"])
            if not flags & 2:          # Horde
                continue
            wx, wy, continent = float(r["Pos_0"]), float(r["Pos_1"]), int(r["ContinentID"])
            ui_map = self.maps.locate(continent, wx, wy)
            rec = {"name": r["Name_lang"], "continent": continent}
            if ui_map:
                rec["position"] = point(ui_map, *self.maps.from_world(ui_map, wx, wy))
            times = self.rxp.flight_times.get(int(r["ID"]))
            if times:
                rec["flightTimes"] = times
            nodes[int(r["ID"])] = rec
        for r in load_csv(os.path.join(SOURCES, "wago", "forever", "TaxiPath.csv")):
            a, b = int(r["FromTaxiNode"]), int(r["ToTaxiNode"])
            if a in nodes and b in nodes:
                nodes[a].setdefault("routes", []).append(b)
        # The flight master standing at each node.
        for nid, n in self.questie.npcs.items():
            if "flightMaster" in (n.get("roles") or []) and "H" in str(n.get("friendlyToFaction", "")):
                pts = self.questie.spawns(n)
                for node in nodes.values():
                    if node.get("position") and pts and nearest([node["position"]], pts) is not None \
                            and nearest([node["position"]], pts) < 3:
                        node["flightMaster"] = int(nid)
                        self.want_npc(int(nid))
        return nodes

    def dungeons(self):
        out = {}
        used = defaultdict(list)
        for qid, q in self.quests.items():
            if q["category"] == "dungeon":
                used[q["zone"]["name"]].append(qid)
        for area, d in self.questie.dungeons.items():
            if d["name"] not in used:
                continue
            rec = {"name": d["name"], "quests": sorted(used[d["name"]])}
            entrances = []
            for e in d.get("entrances") or []:
                m = self.questie.ui_map(e["zone"])
                if m:
                    entrances.append(point(m, e["x"], e["y"]))
            if entrances:
                rec["entrances"] = entrances
            levels = [self.quests[q].get("level") for q in rec["quests"] if (self.quests[q].get("level") or 0) > 0]
            if levels:
                rec["questLevels"] = [min(levels), max(levels)]
            out[int(area)] = rec
        return out

    # ---- Run

    def run(self):
        os.makedirs(OUT, exist_ok=True)
        chosen = self.select()
        # Build every candidate once to learn its zone, then again for only the ones in scope, so
        # the NPCs, objects and items that out-of-scope quests pulled in do not stay behind.
        kept = {}
        for qid, origin in chosen.items():
            rec = self.build_quest(qid, origin)
            ok, why = self.in_scope(rec)
            if ok:
                kept[qid] = origin
            else:
                self.report["outOfScope"].append((qid, rec["name"], why, (rec.get("zone") or {}).get("name")))
        self.npcs, self.objects, self.items = {}, {}, {}
        for qid, origin in kept.items():
            self.quests[qid] = self.build_quest(qid, origin)
        self.service_npcs()
        flights = self.flight_paths()
        quest_ids = set(self.quests)
        # Items can pull in vendors, so build items before NPCs.
        for iid in list(self.items):
            self.items[iid] = self.build_item(iid)
        for nid in list(self.npcs):
            self.npcs[nid] = self.build_npc(nid, quest_ids)
        for oid in list(self.objects):
            self.objects[oid] = self.build_object(oid)
        dungeons = self.dungeons()
        maps = {m: self.maps.info[m] for m in {p["map"] for n in self.npcs.values() for p in n["positions"]} | {
            q["zone"]["map"] for q in self.quests.values() if q.get("zone") and q["zone"].get("map")} if m in self.maps.info}

        write("quests.json", self.quests)
        write("npcs.json", self.npcs)
        write("objects.json", self.objects)
        write("items.json", self.items)
        write("flightpaths.json", flights)
        write("dungeons.json", dungeons)
        write("maps.json", maps)
        self.write_report(dungeons, flights)

    def write_report(self, dungeons, flights):
        from collections import Counter
        q = self.quests
        lines = ["# Horde 1-%d questing database: coverage report" % MAX_LEVEL, "",
                 "Generated by `db/tools/build_horde.py`. Every quest a Horde character can pick up by level %d, "
                 "from Questie (Classic), ForeverGuide (Forever scan and recordings), RestedXP's Forever guides, "
                 "our own guides and what we saw in game. Positions are Forever map coordinates." % MAX_LEVEL, "",
                 "## Sources", ""]
        with open(os.path.join(SOURCES, "wago", "forever", "BUILD")) as f:
            lines.append("- Forever client tables: build %s (wago.tools)" % f.read().strip())
        lines.append("- Questie extract: `db/questie/` (QuestieDB Forever build)")
        lines.append("- ForeverGuide: `db/sources/ForeverGuide` (`data-src/forever.json`)")
        lines.append("- RestedXP Forever guides and flight times: `AddOns/RXPGuides`")
        lines.append("- Ours: `db/quests.json`, `db/npcs.json`")
        if self.ig.quests:
            lines.append("- In game: `db/ingame/` (NuuExperiments quest-scan and quest-record), %d quests, %d NPCs" % (
                sum(1 for x in self.ig.quests.values() if x.get("exists") is not False), len(self.ig.npcs)))
            if self.ig.source.get("cacheWritten"):
                lines.append("- XP: the client's quest cache, build %s, written %s (%d quests); a server change since "
                             "shows only after the cache is cleared and the scan run again" % (
                                 self.ig.source["cacheBuild"], self.ig.source["cacheWritten"], self.ig.source["cacheQuests"]))
        lines += ["", "## Totals", ""]
        cats = Counter(x["category"] for x in q.values())
        lines.append("| Category | Quests |")
        lines.append("| --- | ---: |")
        for c, n in cats.most_common():
            lines.append("| %s | %d |" % (c, n))
        lines.append("| **all** | **%d** |" % len(q))
        lines += ["", "NPCs %d, objects %d, items %d, Horde flight points %d, dungeons %d." % (
            len(self.npcs), len(self.objects), len(self.items), len(flights), len(dungeons)), ""]

        lines += ["## Coverage by zone", "",
                  "Quests without events. A column counts quests that have the field.", "",
                  "| Zone | Quests | Level | XP | Giver placed | Turn-in placed | Objectives placed | Counts | Prereqs | Forever-only |",
                  "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
        by_zone = defaultdict(list)
        for qid, x in q.items():
            if x["category"] == "event":
                continue
            name = (x.get("zone") or {}).get("name") or (x.get("zone") or {}).get("sort") or "unknown"
            if x["category"] == "class":
                name = "Class: " + ((x.get("zone") or {}).get("sort") or "/".join(x.get("classes", [])))
            by_zone[name].append(x)
        for name, xs in sorted(by_zone.items(), key=lambda kv: -len(kv[1])):
            def has(field):
                return sum(1 for x in xs if field not in x["missing"])
            lines.append("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d |" % (
                name, len(xs), has("level"), has("xp"), sum(1 for x in xs if not {"starts", "startPosition"} & set(x["missing"])),
                sum(1 for x in xs if not {"ends", "endPosition"} & set(x["missing"])), has("objectivePosition"), has("count"),
                sum(1 for x in xs if x.get("prereqs")), sum(1 for x in xs if "questie" not in x["src"])))

        miss = Counter(m for x in q.values() if x["category"] != "event" for m in x["missing"])
        lines += ["", "## Gaps", "", "| Missing | Quests |", "| --- | ---: |"]
        for m, n in miss.most_common():
            lines.append("| %s | %d |" % (m, n))
        lines += ["", "Quests missing a giver, a turn-in or XP (events left out):", ""]
        for qid, x in sorted(q.items()):
            gaps = [m for m in x["missing"] if m in ("starts", "startPosition", "ends", "endPosition", "level")]
            if gaps and x["category"] != "event":
                lines.append("- %d %s (%s): %s" % (qid, x["name"], (x.get("zone") or {}).get("name", "?"), ", ".join(gaps)))
        custom_no_xp = [(qid, x["name"]) for qid, x in sorted(q.items()) if "questie" not in x["src"] and "xp" in x["missing"]]
        lines += ["", "No source has XP for Forever-only quests (%d quests); only the in-game turn-in shows it." % len(custom_no_xp)]

        lines += ["", "## Conflicts and corrections", ""]
        lines.append("- Mulgore's map bounds changed in Forever. %d of our Mulgore points used the Classic bounds "
                     "(copied from RestedXP's comments) and were converted; %d already matched Forever and were kept. "
                     "Our NuuRoad Mulgore guides carry the unconverted points." % (len(self.ours.converted), len(self.ours.kept)))
        level_changed = sorted(set(self.report["levelChanged"]))   # every quest is built twice
        if level_changed:
            lines += ["", "Quest levels that differ between Forever's scan and Classic (%d):" % len(level_changed), ""]
            for qid, name, classic, forever in level_changed:
                lines.append("- %d %s: Classic %s, Forever %s" % (qid, name, classic, forever))
        from collections import Counter as _C
        with_pre = [x for x in q.values() if x.get("prereqs")]
        lines += ["", "Prerequisites (`prereqs`): %d quests have some; by source: %s. %d have a `maybe` (needed or an "
                  "optional breadcrumb, unknown); %d Forever-only quests have none at all (a chain's first quest, or "
                  "not in the quest cache yet)." % (
                      len(with_pre), ", ".join("%s %d" % kv for kv in _C(s for x in with_pre for s in x["prereqs"]["src"]).most_common()),
                      sum(1 for x in with_pre if x["prereqs"].get("maybe")),
                      sum(1 for x in q.values() if "questie" not in x["src"] and not x.get("prereqs")))]
        gone = sorted(set(self.report["prereqGone"]))
        if gone:
            lines += ["", "Prerequisites left out because the server does not have them (%d):" % len(gone), ""]
            for qid, kind, p in gone:
                if qid in q:
                    lines.append("- %d %s: %s %d" % (qid, q[qid]["name"], kind, p))
        new_links = sorted({(qid, tuple(n)) for qid, n in self.report["serverLinkNew"]})
        if new_links:
            lines += ["", "Server chain links Questie does not have, kept as `maybe` (%d):" % len(new_links), ""]
            for qid, n in new_links:
                if qid in q:
                    lines.append("- %d %s, after %s" % (qid, q[qid]["name"], ", ".join(str(x) for x in n)))
        next_changed = sorted(set(self.report["nextChanged"]))
        if next_changed:
            lines += ["", "Next quest in the chain that differs from Questie's (%d); the server's is used:" % len(next_changed), ""]
            for qid, name, classic, forever in next_changed:
                lines.append("- %d %s: Questie %d, server %d" % (qid, name, classic, forever))

        xp_changed = sorted(set(self.report["xpChanged"]))
        if xp_changed:
            rounding = [x for x in xp_changed if abs(x[3] - x[2]) <= 25]
            real = [x for x in xp_changed if abs(x[3] - x[2]) > 25]
            lines += ["", "Quest XP that differs from Questie's (%d); ours is used. %d differ by the client's rounding only "
                      "(Questie keeps the table's 910 where the client pays 900); the rest:" % (len(xp_changed), len(rounding)), ""]
            for qid, name, classic, forever, source, multiplier in real:
                lines.append("- %d %s: Questie %d, ours %d (%s%s)" % (qid, name, classic, forever, source,
                                                                    ", multiplier %g" % multiplier if multiplier else ""))
        changed = sorted(set(self.report["countChanged"]))   # every quest is built twice
        if changed:
            lines += ["", "Objective counts the client gives differently from the other sources (%d); the client's is used:" %
                      len(changed), ""]
            for qid, index, other, client in changed:
                lines.append("- %d %s, objective %d: %s, client %s" % (qid, q.get(qid, {}).get("name", "?"), index, other, client))
        if self.report["npcMoved"]:
            lines += ["", "NPCs seen on Forever more than 3 map units from every Classic spawn (%d); the Forever position is used:" %
                      len(self.report["npcMoved"]), ""]
            for nid, name, d in sorted(self.report["npcMoved"]):
                lines.append("- %d %s: %s units" % (nid, name, d))

        lines += ["", "## Left out", ""]
        lines.append("- Blacklisted by Questie on Forever: %d" % len(self.report["blacklisted"]))
        lines.append("- Questie quests the Forever client does not have: %d" % len(self.report["notInClient"]))
        if self.ig.quests:
            lines.append("- Questie quests the Forever server says it does not have (quest-scan): %d" % len(self.report["serverMissing"]))
        lines.append("- Forever test or disabled quests: %d" % len(self.report["junk"]))
        why = Counter(w for _, _, w, _ in self.report["outOfScope"])
        lines.append("- Outside the Horde 1-%d zones and dungeons: %d (%s)" % (
            MAX_LEVEL, len(self.report["outOfScope"]), ", ".join("%s %d" % kv for kv in why.most_common())))
        if self.report["customNoFaction"]:
            lines += ["", "Forever-only quests up to level %d that no source places or gives a faction; check in game (%d):" % (
                MAX_LEVEL + 2, len(self.report["customNoFaction"])), ""]
            for qid, name, level, where in sorted(self.report["customNoFaction"]):
                lines.append("- %d %s (level %s%s)" % (qid, name, level, ", map %s" % self.maps.name(where) if where else ""))
        lines.append("")
        lines.append("Forever-only quests with no level at all (not selected): %d" % len(self.report["customNoLevel"]))
        with open(os.path.join(OUT, "REPORT.md"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("wrote REPORT.md")


if __name__ == "__main__":
    Builder().run()
