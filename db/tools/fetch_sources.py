#!/usr/bin/env python3
"""Fetch the external sources build_horde.py merges, into db/sources/.

Development tool only. Downloads:
  - ForeverGuide (github.com/prezus/ForeverGuide): Forever-only quests from its
    in-game scan, recorded facts and RestedXP import (data-src/forever.json).
  - Client DB2 tables for the installed Forever build, and the map bounds of the
    latest Classic era build, from wago.tools. Map bounds are what turn world
    coordinates into map coordinates; Forever changed some of them (Mulgore).

    python3 db/tools/fetch_sources.py
"""

import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = os.path.join(HERE, "..", "sources")
BUILD_INFO = os.path.join(HERE, "..", "..", "..", "..", "..", ".build.info")
FOREVER_GUIDE = "https://github.com/prezus/ForeverGuide.git"

FOREVER_TABLES = ["UiMapAssignment", "UiMap", "Map", "AreaTable", "TaxiNodes", "TaxiPath",
                  "QuestV2", "QuestSort", "QuestLine", "QuestLineXQuest", "QuestInfo"]
ERA_TABLES = ["UiMapAssignment"]


def forever_build():
    """The client's version from .build.info, e.g. 1.60.1.70009."""
    with open(BUILD_INFO, encoding="utf-8") as f:
        header = f.readline().strip().split("|")
        column = next(i for i, h in enumerate(header) if h.startswith("Version"))
        for line in f:
            fields = line.strip().split("|")
            if len(fields) > column and fields[column].startswith("1.60."):
                return fields[column]
    sys.exit("no 1.60.x build in " + BUILD_INFO)


def fetch(url):
    # wago.tools refuses Python's default user agent.
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "curl/8"}))


def era_build():
    import json
    with fetch("https://wago.tools/api/builds") as r:
        builds = json.load(r)
    return builds["wow_classic_era"][0]["version"]


def download(table, build, folder):
    os.makedirs(folder, exist_ok=True)
    url = "https://wago.tools/db2/%s/csv?build=%s" % (table, build)
    path = os.path.join(folder, table + ".csv")
    with fetch(url) as r, open(path, "wb") as f:
        f.write(r.read())
    print("  %s (%d bytes)" % (path, os.path.getsize(path)))


def main():
    os.makedirs(SOURCES, exist_ok=True)
    guide = os.path.join(SOURCES, "ForeverGuide")
    if os.path.isdir(os.path.join(guide, ".git")):
        subprocess.run(["git", "-C", guide, "pull", "--ff-only", "-q"], check=True)
    else:
        subprocess.run(["git", "clone", "--depth", "1", "-q", FOREVER_GUIDE, guide], check=True)
    rev = subprocess.run(["git", "-C", guide, "log", "-1", "--format=%h %ci"], capture_output=True, text=True).stdout
    print("ForeverGuide at", rev.strip())

    build = forever_build()
    print("Forever client tables, build", build)
    for table in FOREVER_TABLES:
        download(table, build, os.path.join(SOURCES, "wago", "forever"))
    with open(os.path.join(SOURCES, "wago", "forever", "BUILD"), "w") as f:
        f.write(build + "\n")

    build = era_build()
    print("Classic era map bounds, build", build)
    for table in ERA_TABLES:
        download(table, build, os.path.join(SOURCES, "wago", "era"))
    with open(os.path.join(SOURCES, "wago", "era", "BUILD"), "w") as f:
        f.write(build + "\n")


if __name__ == "__main__":
    main()
