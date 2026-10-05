"""Turn the quest-scan and quest-record data into db/ingame/, the in-game source of db/tools/build_horde.py.

    python3 NuuExperiments/Tools/QuestExport.py [--out DIR] [saved-variables file ...]

Without arguments it reads every WTF/Account/*/SavedVariables/NuuExperiments.lua (the game writes them on /reload or
logout) and merges them. It writes, one entry per line, sorted by ID:

  db/ingame/quests.json   id -> name, level, exists (false: the server has no such quest), starts and ends
                          ([{"npc": id}] / [{"object": id}]), startItem, shared, offered (player levels),
                          objectives [{index, type, text, count, positions, targets}], xp (full rate) and
                          turnins [{xp, money, level}]; from the quest cache (read_cache): minLevel, sort (an area
                          ID, or a negative QuestSort: class, profession, event), type (dungeon, elite, ...), next
                          (the quest offered straight after this one), providesItem (given on accepting), flags,
                          faction (only when the race mask limits it) and races
  db/ingame/npcs.json     id -> name, level, positions
  db/ingame/objects.json  id -> name, positions

Positions are {map, x, y} on a uiMapID (0-100).

XP is worked out the way the client does it. The server sends each quest's level, XP difficulty and XP multiplier;
the client keeps them in its quest cache (Cache/WDB/<locale>/questcache.wdb) and shows

    XP = RoundXP(whole part of QuestXP[level][difficulty] * multiplier * share)

with QuestXP from the client's tables (db/sources/wago/forever/QuestXP.csv), RoundXP to 5 up to 100, 10 up to 500,
25 up to 1000 and 50 above, and `share` the character's: all of it up to five levels above the quest, 80% at six,
60% at seven, 50% from eight on. On 1.60.1 (70205) this gave the scan's XP for all 646 quests in the cache at
level 24. `xp` is the full amount (share 1), and `xpFrom` says where it came from:

  "server"   the formula on the quest cache: exact, as of when the client cached the quest. The cache keeps a
             quest (as far as we know, unchecked) until the build changes, so a server change (dungeon quest XP was cut) shows only after the
             cache is cleared: close the game, delete questcache.wdb, log in and run quest-scan again; the game
             writes the cache when it closes.
  "turnin"   what the server paid at a turn-in (quest-record), when that differs from the cache.
  "scan"     the scan's XP for a quest the cache lacks, scaled back to full: within a few XP.

Every export checks the formula against the scan and the turn-ins and prints what does not match.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CLIENT = HERE.parents[3]
OUT = ROOT / "db" / "ingame"
QUEST_XP = ROOT / "db" / "sources" / "wago" / "forever" / "QuestXP.csv"

# Share of a quest's XP a character gets this many levels above it (more: the last).
XP_SHARE = {6: 0.8, 7: 0.6, 8: 0.5}
FULL_XP_ABOVE = 5


def xp_share(gap):
    if gap <= FULL_XP_ABOVE:
        return 1.0
    return XP_SHARE.get(gap, XP_SHARE[max(XP_SHARE)])


def round_xp(v):
    """The client's rounding of a quest's XP, on the whole part."""
    v = int(v)
    if v <= 100:
        return 5 * ((v + 2) // 5)
    if v <= 500:
        return 10 * ((v + 5) // 10)
    if v <= 1000:
        return 25 * ((v + 12) // 25)
    return 50 * ((v + 25) // 50)


def read_quest_xp():
    """QuestXP: quest level -> XP per difficulty."""
    import csv
    with open(QUEST_XP, encoding="utf-8") as f:
        return {int(r["ID"]): [int(r["Difficulty_%d" % i]) for i in range(10)] for r in csv.DictReader(f)}


def quest_xp(table, server, player_level=None):
    """A quest's XP from what the server sent (level, difficulty, multiplier), at a character's level (None: full)."""
    level, difficulty, multiplier = server
    row = table.get(level)
    if not row or difficulty >= len(row):
        return None
    share = 1.0 if player_level is None else xp_share(player_level - level)
    return round_xp(row[difficulty] * multiplier * share)


# Races by bit (race ID - 1) as the server's race mask has them: Classic's, and Forever's Skyborne, who come in an
# Alliance and a Horde version. The mask has bits for later races too; Forever has none of them.
RACE_BITS = {0: "Human", 1: "Orc", 2: "Dwarf", 3: "NightElf", 4: "Undead", 5: "Tauren", 6: "Gnome", 7: "Troll",
             32: "SkyborneAlliance", 33: "SkyborneHorde"}
ALLIANCE = {"Human", "Dwarf", "NightElf", "Gnome", "SkyborneAlliance"}
HORDE = {"Orc", "Undead", "Tauren", "Troll", "SkyborneHorde"}
QUEST_TYPES = {1: "elite", 21: "life", 41: "pvp", 62: "raid", 81: "dungeon", 82: "event", 83: "legendary"}


def races_of(mask):
    """(faction, races) for a race mask: faction "Alliance" or "Horde" when only that faction's races may take it
    (None: the mask does not limit the faction; who gives the quest may), races only when it is not every race of
    the faction (or of both)."""
    if mask in (0, -1, 0xFFFFFFFFFFFFFFFF):
        return None, None
    races = {name for bit, name in RACE_BITS.items() if mask >> bit & 1}
    if not races or races >= ALLIANCE | HORDE:
        return None, None
    faction = "Alliance" if races <= ALLIANCE else "Horde" if races <= HORDE else None
    if races in (ALLIANCE, HORDE):
        return faction, None
    return faction, sorted(races)


def read_cache(path):
    """The client's quest cache: build and {questID: what the server said about the quest}.

    A header of 24 bytes ("TSQW", build, locale, ...), then records: quest ID, length, and the server's quest
    answer. Its fields, found by matching against Questie on 1.60.1 (70205) (agreement in brackets):
      int32 at 8    level
            at 16   minimum level (98%)
            at 24   zone (area ID), or a QuestSort as a negative number: a class, profession or event (100%)
            at 28   quest type: QuestInfo (81 Dungeon for all 28 dungeon quests, 1 Elite, ...)
            at 36   the quest offered straight after this one is turned in: a prerequisite of it (158 of 182)
                    or a breadcrumb for it (22)
            at 40   XP difficulty; float at 44 XP multiplier (the XP formula matches the client every time)
            at 96   the item the quest gives on accepting it (Questie's sourceItemId, 99%); at 100 its flags (96%)
      int64 at 440  allowed races, RACE_BITS (-1: any); where it differs from Questie, Forever changed it (Troll
                    druids)
    The server never sends classes (a class quest has its class as its QuestSort), prerequisites or breadcrumbs."""
    import struct
    data = path.read_bytes()
    if data[:4] != b"TSQW":
        raise ValueError("%s is not a quest cache" % path)
    build = struct.unpack_from("<I", data, 4)[0]
    out, pos = {}, 24
    while pos + 8 <= len(data):
        qid, length = struct.unpack_from("<II", data, pos)
        if qid == 0 or length < 448:
            break
        r = data[pos + 8:pos + 8 + length]
        if struct.unpack_from("<I", r, 0)[0] == qid:
            i = lambda off: struct.unpack_from("<i", r, off)[0]
            out[qid] = {"level": i(8), "minLevel": i(16), "sort": i(24), "info": i(28), "next": i(36),
                        "xpDifficulty": struct.unpack_from("<I", r, 40)[0], "xpMultiplier": struct.unpack_from("<f", r, 44)[0],
                        "providesItem": i(96), "flags": struct.unpack_from("<I", r, 100)[0],
                        "races": struct.unpack_from("<Q", r, 440)[0]}
        pos += 8 + length
    return build, out


def xp_inputs(record):
    return record["level"], record["xpDifficulty"], record["xpMultiplier"]


# --- Saved variables ----------------------------------------------------------------------------

TOKEN = re.compile(r"""
    \s+ | --[^\n]* |
    (?P<str>"(?:[^"\\]|\\.)*") |
    (?P<num>-?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|0x[0-9a-fA-F]+)) |
    (?P<name>[A-Za-z_]\w*) |
    (?P<sym>[{}\[\]=,;])
""", re.S | re.X)

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b"}


def unquote(s):
    out, i = [], 1
    while i < len(s) - 1:
        c = s[i]
        if c == "\\":
            n = s[i + 1]
            if n.isdigit():
                m = re.match(r"\d{1,3}", s[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(ESCAPES.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tokens(text):
    for m in TOKEN.finditer(text):
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)


class Parser:
    """The subset of Lua the game writes to saved variables: `Name = value` lines of tables, strings,
    numbers and booleans."""

    def __init__(self, text):
        self.toks = list(tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError("expected %r, got %r at token %d" % (value, tok[1], self.i))
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "str":
            return unquote(text)
        if kind == "num":
            v = float(int(text, 16)) if text.lower().startswith("0x") else float(text)
            return int(v) if v.is_integer() and "." not in text and "e" not in text.lower() else v
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[text]
        if text == "{":
            return self.table()
        raise ValueError("unexpected %r" % text)

    def table(self):
        out, n = {}, 0
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                v = self.value()
                if v is not None:
                    out[key] = v
            elif self.peek()[0] == "name" and self.toks[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                out[key] = self.value()
            else:
                # The game writes a hole in a list as `nil`: it takes its place and holds nothing.
                n += 1
                v = self.value()
                if v is not None:
                    out[n] = v
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return out

    def assignments(self):
        out = {}
        while self.peek()[0]:
            name = self.take()[1]
            self.take("=")
            out[name] = self.value()
        return out


def as_list(t):
    """A Lua list (a dict keyed 1..n) as a Python list."""
    if isinstance(t, list):
        return t
    if not isinstance(t, dict):
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


# --- Merging ------------------------------------------------------------------------------------

def point(p):
    p = as_list(p)
    return {"map": int(p[0]), "x": round(p[1], 2), "y": round(p[2], 2)}


def add_points(target, points, tol=0.5):
    for p in points:
        if not any(q["map"] == p["map"] and abs(q["x"] - p["x"]) <= tol and abs(q["y"] - p["y"]) <= tol for q in target):
            target.append(p)


def ref(key):
    kind, i = key.split(":")
    return {kind: int(i)}


def objective_text(text):
    """'0/8 Vile Familiar slain' or 'Vile Familiar slain: 0/8' -> 'Vile Familiar slain'."""
    if not text:
        return None
    text = re.sub(r"^\s*\d+\s*/\s*\d+\s+", "", text)
    text = re.sub(r":?\s*\d+\s*/\s*\d+\s*$", "", text)
    return text.strip() or None


class Export:
    def __init__(self):
        self.quests, self.npcs, self.objects = {}, {}, {}
        self.scan_xp = {}           # id -> (xp, player level)
        self.server = {}            # id -> (level, XP difficulty, XP multiplier), from the quest cache
        self.builds = set()

    def quest(self, qid):
        return self.quests.setdefault(int(qid), {})

    def objective(self, q, index):
        objectives = q.setdefault("objectives", [])
        for o in objectives:
            if o["index"] == index:
                return o
        o = {"index": index}
        objectives.append(o)
        return o

    def scan(self, data):
        self.builds.add(data.get("build"))
        level = data.get("playerLevel")
        for qid, s in (data.get("quests") or {}).items():
            q = self.quest(qid)
            q["name"] = s.get("title") or q.get("name")
            if s.get("level"):
                q["level"] = s["level"]
            q["exists"] = True
            for i, o in enumerate(as_list(s.get("objectives")), 1):
                self.fill_objective(self.objective(q, i), o)
            if s.get("xp") and level:
                self.scan_xp[int(qid)] = (s["xp"], level)
        for qid in data.get("missing") or {}:
            q = self.quest(qid)
            if not q.get("exists"):
                q["exists"] = False

    def fill_objective(self, o, src):
        if src.get("type"):
            o["type"] = src["type"]
        text = objective_text(src.get("text"))
        if text:
            o["text"] = text
        if src.get("required"):
            o["count"] = src["required"]

    def record(self, data):
        for qid, r in (data.get("quests") or {}).items():
            q = self.quest(qid)
            if r.get("title"):
                q["name"] = r["title"]
            if r.get("level"):
                q["level"] = r["level"]
            q["exists"] = True
            for field in ("starts", "ends"):
                refs = q.setdefault(field, [])
                for key in sorted(r.get(field) or {}):
                    if ref(key) not in refs:
                        refs.append(ref(key))
                if not refs:
                    del q[field]
            if r.get("startItem"):
                q["startItem"] = r["startItem"]
            if r.get("shared"):
                q["shared"] = True
            if r.get("offered"):
                lo, hi = as_list(r["offered"])
                old = q.get("offered", [lo, hi])
                q["offered"] = [min(lo, old[0]), max(hi, old[1])]
            for i, src in sorted((r.get("objectives") or {}).items()):
                o = self.objective(q, int(i))
                self.fill_objective(o, src)
                add_points(o.setdefault("positions", []), [point(p) for p in as_list(src.get("points"))])
                if not o["positions"]:
                    del o["positions"]
                targets = o.setdefault("targets", {})
                for npc, votes in (src.get("targets") or {}).items():
                    targets[str(npc)] = targets.get(str(npc), 0) + votes
                if not targets:
                    del o["targets"]
            for t in as_list(r.get("turnins")):
                q.setdefault("turnins", []).append({k: t[k] for k in ("xp", "money", "level") if k in t})
        for store, out in (("npcs", self.npcs), ("objects", self.objects)):
            for nid, n in (data.get(store) or {}).items():
                e = out.setdefault(int(nid), {})
                for k in ("name", "level"):
                    if n.get(k):
                        e[k] = n[k]
                add_points(e.setdefault("positions", []), [point(p) for p in as_list(n.get("points"))])

    def facts(self):
        """What the server said about each quest in the cache, beside what the scan read."""
        for qid, r in self.server.items():
            q = self.quest(qid)
            q["exists"] = True
            q["level"] = r["level"]
            if r["minLevel"] > 0:
                q["minLevel"] = r["minLevel"]
            if r["sort"]:
                q["sort"] = r["sort"]
            if r["info"]:
                q["type"] = QUEST_TYPES.get(r["info"], r["info"])
            if r["next"] > 0 and r["next"] != qid:
                q["next"] = r["next"]
            if r["providesItem"] > 0:
                q["providesItem"] = r["providesItem"]
            q["flags"] = r["flags"]
            faction, races = races_of(r["races"])
            if faction:
                q["faction"] = faction
            if races:
                q["races"] = races

    def xp(self):
        """Full XP: the formula on the quest cache, a turn-in where the server paid otherwise, the scan scaled up
        where the cache has nothing. Returns lines saying what matched."""
        lines = []
        table = read_quest_xp() if self.server else {}
        for qid, server in self.server.items():
            full = quest_xp(table, xp_inputs(server))
            if full is None:
                continue
            q = self.quest(qid)
            q["xp"], q["xpFrom"] = full, "server"
            q["xpDifficulty"] = server["xpDifficulty"]
            if abs(server["xpMultiplier"] - 1) > 1e-6:
                q["xpMultiplier"] = round(server["xpMultiplier"], 4)

        # The formula against what the client showed in the scan, at the scanning character's level.
        same = compared = 0
        wrong = []
        for qid, (xp, level) in self.scan_xp.items():
            if qid in self.server:
                predicted = quest_xp(table, xp_inputs(self.server[qid]), level)
                compared += 1
                same += predicted == xp
                if predicted != xp:
                    wrong.append("%d (formula %s, scan %d)" % (qid, predicted, xp))
        if compared:
            lines.append("formula on the cache: %d of %d scanned quests match%s" % (
                same, compared, ": " + ", ".join(wrong[:10]) if wrong else ""))

        # The scan, scaled back to full, for quests the cache lacks.
        scaled = 0
        for qid, (xp, level) in self.scan_xp.items():
            q = self.quests[qid]
            if "xp" in q or not q.get("level"):
                continue
            gap = level - q["level"]
            q["xp"], q["xpFrom"] = int(round(xp / xp_share(gap))), "scan"
            if gap > FULL_XP_ABOVE:
                q["xpScaledFrom"] = level
                scaled += 1
        lines.append("XP: %d quests from the cache, %d from the scan (%d scaled up)" % (
            sum(1 for q in self.quests.values() if q.get("xpFrom") == "server"),
            sum(1 for q in self.quests.values() if q.get("xpFrom") == "scan"), scaled))

        # Turn-ins: what the server paid. Where it differs from the cache, the cache is out of date.
        for qid, q in self.quests.items():
            for t in q.get("turnins", []):
                if not (t.get("xp") and t.get("level")):
                    continue
                if qid in self.server:
                    predicted = quest_xp(table, xp_inputs(self.server[qid]), t["level"])
                    if predicted == t["xp"]:
                        continue
                    lines.append("turn-in of %d at level %d paid %d, the cache says %s: clear the cache" % (
                        qid, t["level"], t["xp"], predicted))
                if q.get("level"):
                    gap = t["level"] - q["level"]
                    q["xp"], q["xpFrom"] = int(round(t["xp"] / xp_share(gap))), "turnin"
                    q.pop("xpScaledFrom", None)
                    if gap > FULL_XP_ABOVE:
                        q["xpScaledFrom"] = t["level"]
        return "\n".join(lines)


def write(out, name, data):
    out.mkdir(parents=True, exist_ok=True)
    path = out / name
    items = sorted(data.items())
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n")
        for i, (k, v) in enumerate(items):
            f.write("%s: %s%s\n" % (json.dumps(str(k)), json.dumps(v, ensure_ascii=True, separators=(",", ":")),
                                     "," if i < len(items) - 1 else ""))
        f.write("}\n")
    print("wrote %s: %d entries" % (path, len(data)))


def main():
    args, out, cache = sys.argv[1:], OUT, None
    while args[:1] in (["--out"], ["--cache"]):
        if args[0] == "--out":
            out = Path(args[1])
        else:
            cache = Path(args[1])
        args = args[2:]
    files = [Path(a) for a in args] or sorted(CLIENT.glob("WTF/Account/*/SavedVariables/NuuExperiments.lua"))
    if not files:
        sys.exit("no NuuExperiments.lua under %s/WTF/Account/*/SavedVariables (log in, then /reload)" % CLIENT)
    export = Export()
    for path in files:
        db = Parser(path.read_text(encoding="utf-8", errors="replace")).assignments().get("NuuExperimentsDB") or {}
        data = db.get("data") or {}
        print("%s: scan %s, record %s" % (path, "yes" if "quest-scan" in data else "no",
                                          "yes" if "quest-record" in data else "no"))
        if "quest-scan" in data:
            export.scan(data["quest-scan"])
        if "quest-record" in data:
            export.record(data["quest-record"])
    caches = [cache] if cache else sorted(CLIENT.glob("Cache/WDB/*/questcache.wdb"))
    source = {}
    for path in caches:
        build, server = read_cache(path)
        export.server.update(server)
        export.facts()
        import datetime
        written = datetime.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        source = {"cacheBuild": build, "cacheWritten": written, "cacheQuests": len(server)}
        print("%s: build %d, written %s, %d quests" % (path, build, written, len(server)))
    print(export.xp())
    for q in export.quests.values():
        for o in q.get("objectives", []):
            if not o.get("text"):
                o.pop("text", None)
    write(out, "quests.json", export.quests)
    write(out, "npcs.json", export.npcs)
    write(out, "objects.json", export.objects)
    source["scanBuilds"] = sorted(b for b in export.builds if b)
    (out / "source.json").write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
    builds = sorted(b for b in export.builds if b)
    if builds:
        print("scanned on", ", ".join(builds))


if __name__ == "__main__":
    main()
