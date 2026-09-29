#!/usr/bin/env python3
"""Extract the QuestieDB Forever database into plain JSON.

Development tool only; nothing here ships. QuestieDB (GPL-3.0) bakes its
database into the TOC's metadata lines as base64 CBOR, one line per entity
field (`## X-Quest-<id>-S` for the scalar row, `## X-Quest-<id>-<field>` for
each table field). This decodes those lines with the field names from
QuestieDB's own src/meta/*Meta.lua, reads the Lua tables under
support/Forever, and writes db/questie/*.json.

    python3 db/tools/questie_extract.py [path/to/AddOns/QuestieDB]
"""

import base64
import json
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "questie")
DEFAULT_ADDON = os.path.join(HERE, "..", "..", "..", "AddOns", "QuestieDB")

FLAVOR = "Forever"

# --- CBOR ---------------------------------------------------------------------

class Cbor:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def byte(self):
        b = self.data[self.pos]
        self.pos += 1
        return b

    def take(self, n):
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def length(self, info):
        if info < 24:
            return info
        if info == 24:
            return self.byte()
        if info == 25:
            return struct.unpack(">H", self.take(2))[0]
        if info == 26:
            return struct.unpack(">I", self.take(4))[0]
        if info == 27:
            return struct.unpack(">Q", self.take(8))[0]
        if info == 31:
            return None
        raise ValueError("bad CBOR length %d" % info)

    def item(self):
        head = self.byte()
        major, info = head >> 5, head & 31
        if major == 0:
            return self.length(info)
        if major == 1:
            return -1 - self.length(info)
        if major in (2, 3):
            n = self.length(info)
            if n is None:
                parts = []
                while self.data[self.pos] != 0xFF:
                    parts.append(self.item().encode())
                self.pos += 1
                raw = b"".join(parts)
            else:
                raw = self.take(n)
            # Lua strings may arrive as byte strings; they are text either way.
            return raw.decode("utf-8", "replace")
        if major == 4:
            n = self.length(info)
            out = []
            if n is None:
                while self.data[self.pos] != 0xFF:
                    out.append(self.item())
                self.pos += 1
            else:
                for _ in range(n):
                    out.append(self.item())
            return out
        if major == 5:
            n = self.length(info)
            out = {}
            if n is None:
                while self.data[self.pos] != 0xFF:
                    k = self.item()
                    out[k] = self.item()
                self.pos += 1
            else:
                for _ in range(n):
                    k = self.item()
                    out[k] = self.item()
            return out
        if major == 6:
            self.length(info)
            return self.item()
        # major 7
        if info == 20:
            return False
        if info == 21:
            return True
        if info in (22, 23):
            return None
        if info == 25:
            return struct.unpack(">e", self.take(2))[0]
        if info == 26:
            return struct.unpack(">f", self.take(4))[0]
        if info == 27:
            return struct.unpack(">d", self.take(8))[0]
        raise ValueError("bad CBOR simple %d" % info)


def cbor(data):
    return Cbor(data).item()


def luaify(value):
    """Turn Lua-sequence maps ({1=a, 2=b}) into lists, recursively."""
    if isinstance(value, list):
        return [luaify(v) for v in value]
    if isinstance(value, dict):
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [luaify(value[k]) for k in sorted(keys)]
        return {k: luaify(v) for k, v in value.items()}
    return value


# --- TOC metadata store -------------------------------------------------------

def read_toc(path):
    store = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("## X-"):
                key, _, value = line[3:].rstrip("\r\n").partition(": ")
                store[key] = value
    return store


def stored(store, key):
    value = store.get(key)
    if value is None:
        return None
    m = re.match(r"^~(\d+)~$", value)
    if m:
        return "".join(store[key + "-" + str(i)] for i in range(1, int(m.group(1)) + 1))
    return value


def read_meta(path):
    text = open(path, encoding="utf-8").read()
    def table(name):
        m = re.search(r"\b" + name + r"\s*=\s*\{(.*?)\n\s*\}", text, re.S)
        return dict((int(k), v) for k, v in re.findall(r"\[(\d+)\]\s*=\s*'?([^',]+)'?", m.group(1))) if m else {}
    prefix = re.search(r"metaPrefix\s*=\s*'([^']+)'", text).group(1)
    return {
        "prefix": "X-" + prefix,
        "names": table("names"),
        "types": table("types"),
        "constants": table("constantValues"),
    }


def decode_entities(store, meta):
    prefix = meta["prefix"]
    ids = luaify(cbor(zlib.decompress(base64.b64decode(stored(store, prefix + "IDS")))))
    entities = {}
    for eid in ids:
        raw = stored(store, "%s%d-S" % (prefix, eid))
        row = cbor(base64.b64decode(raw)) if raw else {}
        presence = row.get("p", 0) if isinstance(row, dict) else 0
        entity = {}
        for index, name in sorted(meta["names"].items()):
            if index in meta["constants"]:
                continue
            if meta["types"][index] == "table":
                if not (presence >> (index - 1)) & 1:
                    continue
                raw = stored(store, "%s%d-%d" % (prefix, eid, index))
                if raw is None:
                    continue
                entity[name] = luaify(cbor(base64.b64decode(raw)))
            else:
                value = row.get(index) if isinstance(row, dict) else None
                if value is not None:
                    entity[name] = value
        entities[eid] = entity
    return entities


# --- Lua table literals (support/ files) ---------------------------------------

TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*)
  | (?P<long>\[\[.*?\]\])
  | (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
  | (?P<num>-?0x[0-9a-fA-F]+|-?\d+\.?\d*(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_.]*)
  | (?P<sym>[{}\[\]=,;()])
""", re.S | re.X)


class LuaTable:
    def __init__(self, text, names=None):
        self.tokens = [(m.lastgroup, m.group()) for m in TOKEN.finditer(text) if m.lastgroup != "ws"]
        self.pos = 0
        self.names = names or {}

    def peek(self, offset=0):
        i = self.pos + offset
        return self.tokens[i] if i < len(self.tokens) else (None, None)

    def next(self):
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def skip_parens(self):
        depth = 1
        while depth:
            _, t = self.next()
            depth += (t == "(") - (t == ")")

    def value(self):
        kind, text = self.next()
        if kind == "sym" and text == "{":
            return self.table()
        if kind == "sym" and text == "(":
            # An expression such as (isHorde and {...}) or {...}; battlegrounds only.
            self.skip_parens()
            while self.peek()[0] == "name" and self.peek()[1] in ("and", "or"):
                self.pos += 1
                self.value()
            return None
        if kind == "num":
            return int(text, 16) if "x" in text.lower() else (float(text) if re.search(r"[.eE]", text) else int(text))
        if kind == "str":
            return bytes(text[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
        if kind == "name":
            if text in ("true", "false"):
                return text == "true"
            if text == "nil":
                return None
            if self.peek()[1] == "(":
                self.pos += 1
                self.skip_parens()
                return None
            # Named constant such as ZoneDB.zoneIDs.DUROTAR.
            return self.names.get(text.split(".")[-1], text)
        raise ValueError("unexpected %r" % text)

    def table(self):
        out, n = {}, 0
        while True:
            kind, text = self.peek()
            if text == "}":
                self.pos += 1
                return luaify(out)
            if text == "[":
                self.pos += 1
                key = self.value()
                self.next()  # ]
                self.next()  # =
                out[key] = self.value()
            elif kind == "name" and self.peek(1)[1] == "=":
                self.pos += 2
                out[text] = self.value()
            else:
                n += 1
                out[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.pos += 1


def lua_tables(path, anchors, names=None):
    """Parse the first table literal after each anchor regex, inside [[...]] or not."""
    text = open(path, encoding="utf-8").read()
    out = {}
    for key, anchor in anchors.items():
        m = re.search(anchor, text)
        out[key] = LuaTable(text[text.index("{", m.end()):], names).value() if m else None
    return out


# --- Shaping -------------------------------------------------------------------

RACES = {1: "Human", 2: "Orc", 4: "Dwarf", 8: "NightElf", 16: "Undead", 32: "Tauren", 64: "Gnome",
         128: "Troll", 256: "Goblin", 512: "BloodElf", 1024: "Draenei"}
CLASSES = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 32: "DeathKnight",
           64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}
NPC_FLAGS = {1: "gossip", 2: "questGiver", 4: "vendor", 8: "flightMaster", 16: "trainer", 32: "spiritHealer",
             64: "spiritGuide", 128: "innkeeper", 256: "banker", 512: "petitioner", 1024: "tabardDesigner",
             2048: "battlemaster", 4096: "auctioneer", 8192: "stablemaster", 16384: "repair"}
RANKS = {0: "normal", 1: "elite", 2: "rareElite", 3: "boss", 4: "rare"}
HORDE_RACES = 2 | 16 | 32 | 128 | 512
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024


def bits(mask, table):
    return [name for bit, name in sorted(table.items()) if mask & bit]


def faction_of(race_mask):
    horde, alliance = race_mask & HORDE_RACES, race_mask & ALLIANCE_RACES
    if horde and not alliance:
        return "Horde"
    if alliance and not horde:
        return "Alliance"
    return "both"


def spawns(value):
    """{zone: [[x, y, phase?], ...]} -> [{zone, x, y}]"""
    out = []
    if isinstance(value, list):
        value = {i + 1: v for i, v in enumerate(value)}
    for zone, points in (value or {}).items():
        for p in points or []:
            if isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[0] >= 0:
                out.append({"zone": int(zone), "x": round(p[0], 2), "y": round(p[1], 2)})
    return out


def pad(value, n):
    if isinstance(value, dict):
        value = [value.get(k) for k in range(1, n + 1)]
    value = list(value or [])
    return value + [None] * (n - len(value))


def entry(o, *keys):
    o = pad(o, len(keys))
    return {k: v for k, v in zip(keys, o) if v is not None}


def shape_quest(q):
    out = {"name": q.get("name")}
    for key in ("questLevel", "requiredLevel", "requiredMaxLevel", "zoneOrSort"):
        if key in q:
            out[key] = q[key]
    races, classes = q.get("requiredRaces", 0), q.get("requiredClasses", 0)
    out["faction"] = faction_of(races)
    if races:
        out["races"] = bits(races, RACES)
    if classes:
        out["classes"] = bits(classes, CLASSES)
    npcs, objects, items = pad(q.get("startedBy"), 3)
    out["starts"] = {k: v for k, v in (("npcs", npcs), ("objects", objects), ("items", items)) if v}
    npcs, objects = pad(q.get("finishedBy"), 2)[:2]
    out["ends"] = {k: v for k, v in (("npcs", npcs), ("objects", objects)) if v}
    kill, obj, item, rep, credit, spell = pad(q.get("objectives"), 6)
    objectives = {}
    if kill:
        objectives["kill"] = [entry(o, "npc", "text") for o in kill]
    if obj:
        objectives["object"] = [entry(o, "object", "text") for o in obj]
    if item:
        objectives["item"] = [entry(o, "item", "text") for o in item]
    if rep:
        objectives["reputation"] = entry(rep, "faction", "value")
    if credit:
        objectives["killCredit"] = [entry(o, "npcs", "creditNpc", "text") for o in credit]
    if spell:
        objectives["spell"] = [entry(o, "spell", "text", "item") for o in spell]
    if objectives:
        out["objectives"] = objectives
    if q.get("triggerEnd"):
        text, where = pad(q["triggerEnd"], 2)
        out["explore"] = {"text": text, "positions": spawns(where)}
    if q.get("objectivesText"):
        out["text"] = q["objectivesText"]
    for key in ("preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo",
                "nextQuestInChain", "parentQuest", "breadcrumbForQuestId", "breadcrumbs",
                "availableUntilCompleted", "availableStartingWith", "disabledByQuest",
                "sourceItemId", "requiredSourceItems", "requiredSkill", "requiredMinRep", "requiredMaxRep",
                "requiredSpell", "requiredRanks", "reputationReward", "questFlags", "specialFlags",
                "extraObjectives"):
        if q.get(key):
            out[key] = q[key]
    return out


def shape_npc(n):
    out = {"name": n.get("name")}
    if n.get("subName"):
        out["subName"] = n["subName"]
    for key in ("minLevel", "maxLevel", "zoneID", "factionID", "friendlyToFaction"):
        if key in n:
            out[key] = n[key]
    out["rank"] = RANKS.get(n.get("rank", 0), n.get("rank"))
    if n.get("npcFlags"):
        out["roles"] = bits(n["npcFlags"], NPC_FLAGS)
    out["spawns"] = spawns(n.get("spawns"))
    for key in ("waypoints", "questStarts", "questEnds"):
        if n.get(key):
            out[key] = n[key]
    return out


def shape_object(o):
    out = {"name": o.get("name"), "spawns": spawns(o.get("spawns"))}
    for key in ("zoneID", "factionID", "questStarts", "questEnds"):
        if o.get(key):
            out[key] = o[key]
    return out


def shape_item(i):
    return {k: v for k, v in i.items() if v not in (None, 0, [], {})}


# --- Main ----------------------------------------------------------------------

def sort_key(kv):
    k = str(kv[0])
    return (0, int(k), "") if k.lstrip("-").isdigit() else (1, 0, k)


def write(name, data):
    """One entry per line, so diffs between Questie versions stay readable."""
    path = os.path.join(OUT, name)
    items = sorted(data.items(), key=sort_key)
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n")
        for i, (k, v) in enumerate(items):
            f.write("%s: %s%s\n" % (json.dumps(str(k)), json.dumps(v, ensure_ascii=False, separators=(",", ":")),
                                     "," if i < len(items) - 1 else ""))
        f.write("}\n")
    print("wrote %s (%d entries, %.1f MB)" % (name, len(data), os.path.getsize(path) / 1e6))


def main():
    addon = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ADDON)
    os.makedirs(OUT, exist_ok=True)
    store = read_toc(os.path.join(addon, "QuestieDB_%s.toc" % FLAVOR))
    meta_dir = os.path.join(addon, "src", "meta")
    support = os.path.join(addon, "support", FLAVOR)
    # Questie keeps quest XP in its own generated table: quest -> {level recorded at, xp}.
    xp = lua_tables(os.path.join(support, "QuestXP", "xpDB-classic.lua"), {"t": r"QuestXP\.db\s*="})["t"]

    def shape_quest_xp(eid, q):
        out = shape_quest(q)
        level, value = pad(xp.get(eid), 2)
        if value:
            out["xp"] = value
            if level != out.get("questLevel"):
                out["xpLevel"] = level  # the level the XP was recorded at, e.g. for scaling quests
        return out

    shapers = {"quest": shape_quest_xp, "npc": lambda _, v: shape_npc(v), "object": lambda _, v: shape_object(v),
               "item": lambda _, v: shape_item(v)}
    for entity, shaper in shapers.items():
        meta = read_meta(os.path.join(meta_dir, entity + "Meta.lua"))
        data = decode_entities(store, meta)
        write(entity + "s.json", {k: shaper(k, v) for k, v in data.items()})

    zones_dir = os.path.join(addon, "support", FLAVOR, "Zones")
    zone_ids = lua_tables(os.path.join(zones_dir, "zoneIds.lua"), {"t": r"ZoneDB\.zoneIDs\s*="})["t"]

    def with_override(name):
        # Each file holds a base table and an override table; the override wins.
        t = lua_tables(os.path.join(zones_dir, name + ".lua"),
                       {"base": r"private\." + name + r"\s*=", "over": r"private\." + name + r"Override\s*="})
        merged = dict(t["base"] or {})
        merged.update(t["over"] or {})
        return merged

    write("zones.json", {
        "zoneIds": zone_ids,
        "areaIdToUiMapId": with_override("areaIdToUiMapId"),
        "uiMapIdToAreaId": with_override("uiMapIdToAreaId"),
        "subZoneToParentZone": with_override("subZoneToParentZone"),
        "instanceIdToAreaId": lua_tables(os.path.join(zones_dir, "instanceIdToAreaId.lua"),
                                         {"t": r"ZoneDB\.instanceIdToAreaId\s*="}, zone_ids)["t"],
    })
    dungeons = lua_tables(os.path.join(zones_dir, "dungeons.lua"), {"t": r"local dungeons\s*="}, zone_ids)["t"]
    write("dungeons.json", {
        k: {"name": v[0], "altZoneIds": v[1], "parentZone": v[2],
            "entrances": [{"zone": e[0], "x": e[1], "y": e[2]} for e in (v[3] or []) if isinstance(e, list)]}
        for k, v in dungeons.items() if isinstance(v, list)
    })
    # Drop rates are Questie's Wowhead-derived table: item -> {npc: percent}.
    drops = lua_tables(os.path.join(support, "DropTables", "classicItemDrops.lua"), {"t": r"wowheadData\s*="})["t"]
    write("drops.json", drops)


if __name__ == "__main__":
    main()
