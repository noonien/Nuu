"""Write Experiments/QuestScanIDs.lua: the quest IDs the quest-scan experiment asks the server about.

    python3 NuuExperiments/Tools/QuestIDs.py

They are every ID in the Forever client's quest table (db/sources/wago/forever/QuestV2.csv, fetched by
db/tools/fetch_sources.py), as ranges. Run it again after fetching a new client build's tables.
"""
import csv
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = ROOT / "db" / "sources" / "wago" / "forever"
OUT = HERE.parent / "Experiments" / "QuestScanIDs.lua"


def ranges(ids):
    out = []
    for i in sorted(ids):
        if out and i == out[-1][1] + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def main():
    with open(SOURCE / "QuestV2.csv", encoding="utf-8") as f:
        ids = {int(row["ID"]) for row in csv.DictReader(f)}
    build = (SOURCE / "BUILD").read_text().strip() if (SOURCE / "BUILD").exists() else "unknown"
    spans = ranges(ids)
    lines = [
        "local _, ns = ...",
        "",
        "-- Made by Tools/QuestIDs.py from the Forever client's quest table (build %s): %d quest IDs." % (build, len(ids)),
        "-- Do not edit; run the tool again for a new build.",
        "ns.QuestScanIDs = {",
    ]
    row = []
    for a, b in spans:
        row.append("{%d,%d}" % (a, b))
        if len(row) == 12:
            lines.append("    " + ",".join(row) + ",")
            row = []
    if row:
        lines.append("    " + ",".join(row) + ",")
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii")
    print("wrote %s: %d IDs in %d ranges" % (OUT.relative_to(ROOT), len(ids), len(spans)))


if __name__ == "__main__":
    main()
