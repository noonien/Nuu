#!/usr/bin/env python3
"""Serves the viewers and the game's files to them, on this machine only.

    python3 Tools/ClientMap/serve.py [port=8765]

then open http://localhost:8765/zones.html (the zone browser: every cave
of a zone on its minimap, to mark for place generation), or
http://localhost:8765/ (the map and 3D viewer of the places built, view.py).

  /file/<id>          a file of the client's store, by file ID
  /name/<path>        the same by its listfile path
  /id?name=<path>     the file ID of a path; /name?id=<id> the other way
  /zones.json         the zones the browser offers; /zone/<map>.json and
                      /zone/<map>.jpg one zone's models, holes and minimap
                      (zones.py, made the first time they are asked for)
  /marks.json         the marked caves (marks.json); POST it to save them
  /build/<region>     POST starts build.py for a region; GET says how it went
  /scene.html         the 3D explorer; /scene/... its baked tiles and models
                      (scene/bake.py); /scene/places-<continent>.json every
                      built place as lines in the scene's frame
  /bake/<map>         POST bakes a zone for the explorer; GET says how it went
  anything else       from .cache/viewer

Textures the Forever beta does not keep on disk are read from the other
products in the same store (Casc.read_picture); everything else only from
the beta.
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maps  # noqa: E402
import regions  # noqa: E402
import zones  # noqa: E402
from casc import CACHE, Storage  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
VIEWER = os.path.join(CACHE, "viewer")
builds = {}  # region or "zone-<map>" -> {"state": "running" | "done" | "failed", "log": [...]}
SCENE = os.path.join(CACHE, "scene")
storage = Storage()
lock = threading.Lock()  # CascLib is not known to be safe across threads


def read(file_id):
    with lock:
        name = storage.name(file_id) or ""
        if name.endswith(".blp"):
            return storage.read_picture(file_id)
        return storage.read(file_id)


def zone_file(map_id, ext):
    path = os.path.join(zones.OUT, "%d.%s" % (map_id, ext))
    if not os.path.exists(path):
        with lock:
            zones.build(map_id, storage)
    with open(path, "rb") as handle:
        return handle.read()


def start_build(name, command=None):
    """build.py for a region (or another command) in the background, its
    output kept for /build and /bake."""
    if builds.get(name, {}).get("state") == "running":
        return
    state = builds[name] = {"state": "running", "log": []}
    command = command or [sys.executable, os.path.join(HERE, "build.py"), name]

    def run():
        process = subprocess.Popen(command, cwd=HERE,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            state["log"] = (state["log"] + [line.rstrip()])[-40:]
        state["state"] = "done" if process.wait() == 0 else "failed"
    threading.Thread(target=run, daemon=True).start()


def scene_places(continent):
    """Every built place on a continent, as points and connections in the
    scene's frame (x = C - world Y, y = height, z = C - world X)."""
    import wowfiles
    center = wowfiles.MAP_CENTER
    out = []
    for name, region in regions.REGIONS.items():
        path = os.path.join(CACHE, name + ".graph.json")
        if not os.path.exists(path) or maps.CONTINENTS.get(maps.get(region["map"])["continent"]) != continent:
            continue
        graph = json.load(open(path))
        points = [[round(center - p["world"][1], 2), round(p["world"][2], 2), round(center - p["world"][0], 2)]
                  for p in graph["points"]]
        out.append({"region": name, "title": region.get("title") or maps.get(region["map"])["name"],
                    "points": points, "kinds": [p["kind"] for p in graph["points"]],
                    "connections": [c[:2] for c in graph["connections"]], "lifts": graph.get("lifts", [])})
    return out


def marks_json():
    marks = regions.load_marks()
    for mark in marks:
        name = mark["region"]
        mark["built"] = os.path.exists(os.path.join(VIEWER, "data", name + ".js"))
        mark["build"] = builds.get(name, {}).get("state")
    return marks


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=VIEWER, **kwargs)

    def log_message(self, *args):
        pass

    def send_bytes(self, data, kind="application/octet-stream", cache=False):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        # Game files and zone pictures do not change while serving; marks,
        # builds and places do.
        self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        try:
            if url.path.startswith("/file/"):
                data = read(int(url.path[6:]))
                return self.send_bytes(data, cache=True) if data is not None else self.send_error(404)
            if url.path.startswith("/name/"):
                with lock:
                    file_id = storage.file_id(urllib.parse.unquote(url.path[6:]))
                data = read(file_id) if file_id else None
                return self.send_bytes(data, cache=True) if data is not None else self.send_error(404)
            if url.path == "/id":
                with lock:
                    file_id = storage.file_id(query.get("name", [""])[0])
                return self.send_bytes(str(file_id).encode(), "text/plain") if file_id else self.send_error(404)
            if url.path == "/name":
                with lock:
                    name = storage.name(int(query.get("id", ["0"])[0]))
                return self.send_bytes(name.encode(), "text/plain") if name else self.send_error(404)
            if url.path == "/scene.html":
                with open(os.path.join(HERE, "scene.html"), "rb") as handle:
                    return self.send_bytes(handle.read(), "text/html; charset=utf-8")
            if url.path.startswith("/scene/places-") and url.path.endswith(".json"):
                continent = url.path[len("/scene/places-"):-5]
                return self.send_bytes(json.dumps(scene_places(continent)).encode(), "application/json")
            if url.path.startswith("/scene/"):
                path = os.path.normpath(os.path.join(SCENE, urllib.parse.unquote(url.path[7:])))
                if not path.startswith(SCENE) or not os.path.isfile(path):
                    return self.send_error(404)
                ext = path.rsplit(".", 1)[-1]
                kind = {"glb": "model/gltf-binary", "jpg": "image/jpeg", "png": "image/png"}.get(ext, "application/json")
                with open(path, "rb") as handle:
                    return self.send_bytes(handle.read(), kind, cache=ext != "json")
            if url.path.startswith("/bake/"):
                state = builds.get("zone-" + url.path[6:], {"state": None, "log": []})
                return self.send_bytes(json.dumps(state).encode(), "application/json")
            if url.path == "/zones.html":
                with open(os.path.join(HERE, "zones.html"), "rb") as handle:
                    return self.send_bytes(handle.read(), "text/html; charset=utf-8")
            if url.path == "/zones.json":
                return self.send_bytes(json.dumps(zones.zones()).encode(), "application/json")
            if url.path.startswith("/zone/") and url.path.endswith((".json", ".jpg")):
                map_id, ext = url.path[6:].rsplit(".", 1)
                if ext == "jpg":
                    return self.send_bytes(zone_file(int(map_id), ext), "image/jpeg", cache=True)
                # With the map's frame, so the page can turn map % into the 3D scene's frame.
                zone = json.loads(zone_file(int(map_id), ext))
                zone["frame"] = {k: maps.get(int(map_id))[k] for k in ("left", "right", "top", "bottom")}
                return self.send_bytes(json.dumps(zone).encode(), "application/json")
            if url.path == "/marks.json":
                return self.send_bytes(json.dumps(marks_json()).encode(), "application/json")
            if url.path.startswith("/build/"):
                state = builds.get(url.path[7:], {"state": None, "log": []})
                return self.send_bytes(json.dumps(state).encode(), "application/json")
        except (ValueError, OSError) as error:
            return self.send_error(500, str(error))
        return super().do_GET()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if url.path == "/marks.json":
            marks = json.loads(body or b"[]")
            keep = ("region", "title", "map", "model", "unique", "name", "box", "at")
            regions.save_marks([{k: m[k] for k in keep if k in m} for m in marks])
            for mark in regions.load_marks():
                regions.REGIONS[mark["region"]] = regions.mark_region(mark)
            return self.send_bytes(json.dumps(marks_json()).encode(), "application/json")
        if url.path.startswith("/bake/"):
            map_id = int(url.path[6:])
            start_build("zone-%d" % map_id, [sys.executable, os.path.join(HERE, "scene", "bake.py"), str(map_id)])
            return self.send_bytes(b"{}", "application/json")
        if url.path.startswith("/build/"):
            name = url.path[7:]
            if name not in regions.REGIONS:
                return self.send_error(404)
            start_build(name)
            return self.send_bytes(b"{}", "application/json")
        return self.send_error(404)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    with lock:
        storage.name(0)  # read the listfile before the first request
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("zone browser: http://localhost:%d/zones.html   places: http://localhost:%d/" % (port, port))
    server.serve_forever()


if __name__ == "__main__":
    main()
