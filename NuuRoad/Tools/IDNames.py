#!/usr/bin/env python3
"""Writes Data/IDNames.lua: the English names of the area, flight node, and
skill IDs the packaged guides use.

A guide names a place by AreaTable ID, a flight path by TaxiNodes ID, and a
profession or weapon skill by SkillLine ID. The client gives a name for an area
(C_Map.GetAreaInfo) but not for a flight node or a skill line asked by ID, and
the hearth, flight path and skill checks compare names. Steps:Expand uses
this table where the client cannot answer.

Areas and nodes come from db/sources/wago/forever, only the IDs some guide in
Data/Guides names. Skill lines are listed here: every one a step can name.

    python3 Tools/IDNames.py      (from NuuRoad/)
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
WAGO = os.path.join(os.path.dirname(ADDON), "db", "sources", "wago", "forever")
GUIDES = os.path.join(ADDON, "Data", "Guides")
OUT = os.path.join(ADDON, "Data", "IDNames.lua")

SKILLS = {
    43: "Swords", 44: "Axes", 45: "Bows", 46: "Guns", 54: "Maces", 55: "Two-Handed Swords",
    95: "Defense", 129: "First Aid", 136: "Staves", 160: "Two-Handed Maces", 162: "Unarmed",
    164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 172: "Two-Handed Axes",
    173: "Daggers", 176: "Thrown", 182: "Herbalism", 185: "Cooking", 186: "Mining",
    197: "Tailoring", 202: "Engineering", 226: "Crossbows", 228: "Wands", 229: "Polearms",
    333: "Enchanting", 356: "Fishing", 393: "Skinning", 473: "Fist Weapons", 633: "Lockpicking",
}


def used(pattern):
    ids = set()
    for name in sorted(os.listdir(GUIDES)):
        if name.endswith(".lua"):
            with open(os.path.join(GUIDES, name), encoding="ascii") as handle:
                ids.update(int(match) for match in re.findall(pattern, handle.read()))
    return ids


def names(file, key):
    with open(os.path.join(WAGO, file), encoding="utf-8") as handle:
        return {int(row["ID"]): row[key] for row in csv.DictReader(handle)}


def table(name, entries):
    lines = ["    %s = {" % name]
    for id in sorted(entries):
        text = entries[id]
        if not text.isascii():
            sys.exit("not ASCII: %s %d %r" % (name, id, text))
        lines.append('        [%d] = "%s",' % (id, text.replace("\\", "\\\\").replace('"', '\\"')))
    lines.append("    },")
    return lines


def main():
    areas, nodes = names("AreaTable.csv", "AreaName_lang"), names("TaxiNodes.csv", "Name_lang")
    missing = []
    wanted_areas, wanted_nodes = {}, {}
    for id in used(r"\barea = (\d+)"):
        if id in areas: wanted_areas[id] = areas[id]
        else: missing.append("area %d" % id)
    for id in used(r"\bnode = (\d+)"):
        if id in nodes: wanted_nodes[id] = nodes[id]
        else: missing.append("node %d" % id)
    for id in used(r"\bskill = (\d+)"):
        if id not in SKILLS: missing.append("skill %d" % id)
    if missing:
        sys.exit("no name for: " + ", ".join(missing))
    lines = [
        "local _, ns = ...",
        "",
        "-- Written by Tools/IDNames.py; run it again rather than editing this file.",
        "-- English names for the area, flight node, and skill line IDs the packaged",
        "-- guides use, where the client cannot name them by ID (Steps:Expand).",
        "ns.idNames = {",
    ]
    lines += table("areas", wanted_areas)
    lines += table("taxiNodes", wanted_nodes)
    lines += table("skills", SKILLS)
    lines.append("}")
    with open(OUT, "w", encoding="ascii", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("wrote %s: %d areas, %d nodes, %d skills" % (os.path.relpath(OUT), len(wanted_areas), len(wanted_nodes), len(SKILLS)))


if __name__ == "__main__":
    main()
