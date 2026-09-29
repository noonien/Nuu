#!/usr/bin/env bash
# Builds what Tools/ClientMap needs into Tools/ClientMap/.cache (git-ignored):
# CascLib (reads the client's CASC data store), the community listfile (file
# IDs to paths), the navmesh tool, wow.export (to bake models) and three.js
# (to draw them). Run once, from the addon root:
#
#   nix-shell Tools/ClientMap/shell.nix --run "bash Tools/ClientMap/setup.sh"
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache="$here/.cache"
mkdir -p "$cache"

CASCLIB_COMMIT=2a280f5a231966dc5d1b534978dd9f9f04a374cd
if [ ! -f "$cache/libcasc.so" ]; then
    rm -rf "$cache/CascLib"
    git clone -q https://github.com/ladislav-zezula/CascLib.git "$cache/CascLib"
    git -C "$cache/CascLib" checkout -q "$CASCLIB_COMMIT"
    cmake -S "$cache/CascLib" -B "$cache/CascLib/build" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCASC_BUILD_SHARED_LIB=ON -DCASC_BUILD_STATIC_LIB=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$cache/CascLib/build" -j8 >/dev/null
    cp -L "$cache/CascLib/build/libcasc.so" "$cache/libcasc.so"
fi

if [ ! -f "$cache/listfile.csv" ]; then
    curl -sfL -o "$cache/listfile.csv" \
        https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv
fi

# wow.export (MIT), pinned: its exporters bake models for the 3D explorer
# (scene/models.js). Cloned here, not copied into the repository.
WOWEXPORT_COMMIT=c2fd7bde36a712be78a5da896c995b84fbfa2545
if [ ! -d "$cache/wow.export/.git" ] || [ "$(git -C "$cache/wow.export" rev-parse HEAD)" != "$WOWEXPORT_COMMIT" ]; then
    rm -rf "$cache/wow.export"
    git clone -q https://github.com/Kruithne/wow.export.git "$cache/wow.export"
    git -C "$cache/wow.export" checkout -q "$WOWEXPORT_COMMIT"
fi

# three.js (MIT) for the 3D explorer, beside the pages so they work offline.
mkdir -p "$cache/node" "$cache/viewer/vendor/three/build" "$cache/viewer/vendor/three/examples/jsm"
if [ ! -d "$cache/node/node_modules/three" ]; then
    (cd "$cache/node" && npm init -y >/dev/null && npm install --silent three@0.170)
fi
cp "$cache/node/node_modules/three/build/three.module.js" "$cache/viewer/vendor/three/build/"
cp -r "$cache/node/node_modules/three/examples/jsm/loaders" "$cache/node/node_modules/three/examples/jsm/utils" \
    "$cache/viewer/vendor/three/examples/jsm/"
cp "$cache/node/node_modules/three/LICENSE" "$cache/viewer/vendor/three/"

g++ -O2 -std=c++17 -o "$cache/navmesh" "$here/navmesh.cpp" \
    -I"$RECAST/include/recastnavigation" -L"$RECAST/lib" -lRecast
echo "ClientMap tools ready in $cache"
