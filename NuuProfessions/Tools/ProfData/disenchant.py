#!/usr/bin/env python3
"""Ship what disenchanting gives on Forever: Data/Disenchant.lua.

Three things come from the Forever client's own tables:

- the bands (`ItemDisenchantLoot`): which weapons and armour disenchant, by
  quality and item level. Forever's differ from Classic Era's: it adds rare
  bands at item levels 5-15 and 16-20, and its rare 20-25 band starts at 21;
- the items that cannot be disenchanted at all (`ItemSparse` Flags[0] 0x8000,
  limited to uncommon to epic weapons and armour, the only ones a band could
  take): TSM's hand-kept NonDisenchantable list, read from the client instead;
- the items that disenchant into a loot table of their own (Flags[1]
  0x40000000), such as the Hexed Pendant: no band applies to them.

What a band yields is held by the server, so it is authored here (`YIELDS`):
the Classic rates (dust, essence and shard by quality and item level, the same
rates TSM ships for Classic), on Forever's bands. A band with no authored
yield, Forever's new rare bands among them, ships as not known; so does a
special item without an entry in `SPECIAL`, which holds only what was seen in
play.

    python3 Tools/ProfData/disenchant.py            write Data/Disenchant.lua
    python3 Tools/ProfData/disenchant.py --dry-run  report only

Uses extract.py's table cache and OpenRoad's CASC and DB2 readers (see
README.md).
"""

import argparse
import datetime
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extract  # noqa: E402

OUTPUT = os.path.join(extract.ADDON, "Data", "Disenchant.lua")
PRODUCT = "wow_classic_beta"
WEAPON, ARMOR = 2, 4
NO_DISENCHANT = 0x8000          # ItemSparse Flags[0]
OWN_LOOT = 0x40000000           # ItemSparse Flags[1]

# Materials, by name for the table below.
STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
LME, GME, LAE, GAE, LMYE, GMYE, LNE, GNE, LEE, GEE = (
    10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203)
SGLIM, LGLIM, SGLOW, LGLOW, SRAD, LRAD, SBRIL, LBRIL, NEXUS = (
    10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725)
LUMINOUS_RESIDUE = 247884


def uncommon(dust, essence, shard, shard_chance=0.05):
    """An uncommon band's yields for armour and for weapons: armour gives
    mostly dust, weapons mostly essence, and either a shard now and then.
    dust and essence are (itemID, min, max); shard an itemID or None."""
    rest = 1 - (shard_chance if shard else 0)

    def side(dust_chance):
        rows = [(dust[0], dust_chance, dust[1], dust[2]),
                (essence[0], round(rest - dust_chance, 3), essence[1], essence[2])]
        if shard:
            rows.append((shard, shard_chance, 1, 1))
        return rows
    return {ARMOR: side(0.75 if shard else 0.80), WEAPON: side(0.20)}


# (quality, min item level) -> { class: [(itemID, chance, min, max)] }, on
# Forever's bands. Classic's rates: an uncommon item's dust and essence share
# what its shard leaves, armour 3:1 for dust, weapons 1:3 (4:1 and 1:4 in the
# first band, which has no shard); 21-25 gives a 10% shard. TSM ships the same
# rates, with 25% essence on 46-50 armour, which this table keeps at 20 so
# the band adds up to 100%.
YIELDS = {}
for low, dust, essence, shard in (
        (5, (STRANGE, 1, 2), (LME, 1, 2), None),
        (16, (STRANGE, 2, 3), (GME, 1, 2), SGLIM),
        (26, (SOUL, 1, 2), (GAE, 1, 2), LGLIM),
        (31, (SOUL, 2, 5), (LMYE, 1, 2), SGLOW),
        (36, (VISION, 1, 2), (GMYE, 1, 2), LGLOW),
        (41, (VISION, 2, 5), (LNE, 1, 2), SRAD),
        (46, (DREAM, 1, 2), (GNE, 1, 2), LRAD),
        (51, (DREAM, 2, 5), (LEE, 1, 2), SBRIL),
        (56, (ILLUSION, 1, 2), (GEE, 1, 2), LBRIL),
        (61, (ILLUSION, 2, 5), (GEE, 2, 3), LBRIL)):
    YIELDS[(2, low)] = uncommon(dust, essence, shard)
YIELDS[(2, 21)] = {
    ARMOR: [(STRANGE, 0.75, 4, 6), (LAE, 0.15, 1, 2), (SGLIM, 0.10, 1, 1)],
    WEAPON: [(STRANGE, 0.15, 4, 6), (LAE, 0.75, 1, 2), (SGLIM, 0.10, 1, 1)],
}
# Rare: one shard, the same for both. Forever's 21-25 is Classic's 20-25.
for low, rows in (
        (21, [(SGLIM, 1, 1, 1)]), (26, [(LGLIM, 1, 1, 1)]), (31, [(SGLOW, 1, 1, 1)]),
        (36, [(LGLOW, 1, 1, 1)]), (41, [(SRAD, 1, 1, 1)]), (46, [(LRAD, 1, 1, 1)]),
        (51, [(SBRIL, 1, 1, 1)]), (56, [(LBRIL, 0.995, 1, 1), (NEXUS, 0.005, 1, 1)]),
        (61, [(LBRIL, 0.99, 1, 1), (NEXUS, 0.01, 1, 1)])):
    YIELDS[(3, low)] = {ARMOR: rows, WEAPON: rows}
# Epic.
for low, rows in (
        (40, [(SRAD, 1, 2, 4)]), (46, [(LRAD, 1, 2, 4)]), (51, [(SBRIL, 1, 2, 4)]),
        (56, [(NEXUS, 1, 1, 1)]), (61, [(NEXUS, 1, 1, 2)])):
    YIELDS[(4, low)] = {ARMOR: rows, WEAPON: rows}

# Items with a loot table of their own (ItemSparse Flags[1] 0x40000000: the
# Hexed Pendant and Crude Wax Effigy, whose text sends them to Disenchanting,
# and gear such as the Spiritcaller pieces), as seen in play: the Hexed Pendant
# (a Durotar quest's) gives one Luminous Residue (OpenRoad's session log,
# 2026-09-28; RestedXP's Forever guide says the same).
SPECIAL = {
    275724: [(LUMINOUS_RESIDUE, 1, 1, 1)],
}


def lua_rows(rows):
    return "{ " + ", ".join("{ %d, %s, %d, %d }" % (item, ("%g" % chance), low, high)
                            for item, chance, low, high in rows) + " }"


def id_lines(ids, indent, per_line=12):
    ids = sorted(ids)
    return ["%s%s," % (indent, ", ".join("[%d] = true" % i for i in ids[at:at + per_line]))
            for at in range(0, len(ids), per_line)]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="report only")
    args = parser.parse_args()

    build, have = extract.tables(PRODUCT, ["ItemDisenchantLoot", "ItemSparse", "Item"])
    bands = have["ItemDisenchantLoot"]
    if not bands:
        sys.exit("no ItemDisenchantLoot rows in %s %s" % (PRODUCT, build))
    classes = {row["ID"]: row["ClassID"] for row in have["Item"]}
    sparse = {row["ID"]: row for row in have["ItemSparse"]}

    rows, unknown = [], []
    for band in sorted(bands, key=lambda b: (b["Quality"], b["MinLevel"], b["Class"])):
        cls, quality, low, high = band["Class"], band["Quality"], band["MinLevel"], band["MaxLevel"]
        yields = YIELDS.get((quality, low), {}).get(cls)
        if not yields:
            unknown.append("%s quality %d, item level %d-%d" % ("weapon" if cls == WEAPON else "armour",
                                                                quality, low, high))
        rows.append((cls, quality, low, high, yields))
    used = {(quality, low) for _, quality, low, _, _ in rows}
    stale = sorted(set(YIELDS) - used)
    if stale:
        sys.exit("authored yields for bands the client does not have: %s" % stale)

    candidates = [i for i, row in sparse.items()
                  if row["OverallQualityID"] in (2, 3, 4) and classes.get(i) in (WEAPON, ARMOR)]
    blocked = [i for i in candidates if sparse[i]["Flags"][0] & NO_DISENCHANT]
    # The flag is on books and a bag too; an item counts when it is a weapon or
    # armour, its text names the Disenchanting skill, or it was seen.
    own = sorted(i for i, row in sparse.items()
                 if row["Flags"][1] & OWN_LOOT and not row["Flags"][0] & NO_DISENCHANT
                 and row["OverallQualityID"] >= 2
                 and (i in SPECIAL or classes.get(i) in (WEAPON, ARMOR)
                      or "Disenchant" in (row.get("Description_lang") or "")))

    print("build %s: %d bands (%d not known), %d of %d weapons and armour cannot be disenchanted,"
          " %d with their own loot (%d known)" % (build, len(rows), len(unknown), len(blocked),
                                                  len(candidates), len(own), len(set(own) & set(SPECIAL))))
    for line in unknown:
        print("  not known: " + line)
    for item in own:
        print("  own loot: %d %s%s" % (item, sparse[item]["Display_lang"], "" if item in SPECIAL else " (not known)"))
    if args.dry_run:
        return

    today = datetime.date.today().isoformat()
    out = [
        "-- Data/Disenchant.lua",
        "-- Generated by Tools/ProfData/disenchant.py from the Forever client's tables. Do not edit.",
        "-- build %s, generated %s" % (build, today),
        "-- bands: ItemDisenchantLoot, { class (2 weapon, 4 armour), quality, min item level, max item level,",
        "--   yields = { { itemID, chance, min, max }, ... } }; no yields = not known on Forever (the server",
        "--   holds them; the authored ones are Classic's rates). noDisenchant: ItemSparse's cannot-disenchant",
        "--   flag on uncommon to epic weapons and armour. ownLoot: items with a loot table of their own; a",
        "--   table of yields when seen in play, else false.",
        "local _, ns = ...",
        "ns.disenchantData = {",
        "    bands = {",
    ]
    for cls, quality, low, high, yields in rows:
        tail = (", yields = " + lua_rows(yields)) if yields else ""
        out.append("        { %d, %d, %d, %d%s }," % (cls, quality, low, high, tail))
    out.append("    },")
    out.append("    ownLoot = {")
    for item in own:
        value = lua_rows(SPECIAL[item]) if item in SPECIAL else "false"
        out.append("        [%d] = %s, -- %s" % (item, value, extract_ascii(sparse[item]["Display_lang"])))
    out.append("    },")
    out.append("    noDisenchant = {")
    out.extend(id_lines(blocked, "        "))
    out.append("    },")
    out.append("}")
    with open(OUTPUT, "w", encoding="ascii", newline="\n") as handle:
        handle.write("\n".join(out) + "\n")
    print("wrote " + os.path.relpath(OUTPUT, extract.ADDON))


def extract_ascii(text):
    return "".join(ch if 32 <= ord(ch) < 127 else "?" for ch in str(text))


if __name__ == "__main__":
    main()
