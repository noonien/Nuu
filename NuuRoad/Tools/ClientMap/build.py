#!/usr/bin/env python3
"""Everything for one region, in order: its geometry (extract.py), where a
player can walk (navmesh), its place (skeleton.py), its rooms (rooms.py) and
its page in the viewer (view.py). Run from anywhere, inside shell.nix:

    python3 Tools/ClientMap/build.py <region> [<region> ...]
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")


def build(name):
    steps = [
        [sys.executable, "extract.py", name],
        [os.path.join(CACHE, "navmesh"), os.path.join(CACHE, name + ".obj"), os.path.join(CACHE, name + ".bin")],
        [sys.executable, "skeleton.py", name],
        [sys.executable, "rooms.py", name],
        [sys.executable, "view.py", name],
    ]
    with open(os.path.join(CACHE, name + ".place.lua"), "w") as place:
        for step in steps:
            print("== " + " ".join(os.path.basename(part) for part in step[:3]), flush=True)
            out = place if step[1] == "skeleton.py" else None
            result = subprocess.run(step, cwd=HERE, stdout=out)
            if result.returncode:
                raise SystemExit("%s failed (%d)" % (step[1], result.returncode))
    print("built " + name, flush=True)


if __name__ == "__main__":
    for region in sys.argv[1:]:
        build(region)
