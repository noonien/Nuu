// Where a player can walk in a mesh, as Recast works it out: the walkable
// "compact heightfield" (columns of floor spans with their neighbours on
// every side, several per column where levels stack) and, for each span, its
// distance to the nearest edge. skeleton.py turns that into a graph.
//
//   navmesh <in.obj> <out.bin> [cell=0.5] [radius=0.5] [height=2.0] [climb=1.6] [slope=50]
//
// The OBJ is Recast's axes (y up), as extract.py writes it; sizes in yards.
// Output, little-endian: "ORNM", int32 version 2, int32 width, int32 depth,
// float bmin[3], float cell, float cellHeight, int32 spanCount; then per
// column (x + z * width) uint32 first span and uint8 span count; then per span
// uint16 y (in cellHeight steps above bmin), uint16 dist (Recast's distance
// field: about 2 per cell), int32 neighbour[4] (span index or -1; directions
// -x, +z, +x, -z as Recast numbers them), uint8 source (1 terrain, 2 model,
// 3 prop: what the floor is made of, from the OBJ's "g" groups).
#include <Recast.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

// Where a triangle comes from, from the OBJ's "g" lines; kept as the Recast
// area of the floor it makes (0 is Recast's "not walkable").
enum Source { TERRAIN = 1, MODEL = 2, PROP = 3 };

static bool loadObj(const char* path, std::vector<float>& verts, std::vector<int>& tris,
                    std::vector<unsigned char>& sources) {
    std::ifstream in(path);
    if (!in) return false;
    std::string line;
    unsigned char source = MODEL;
    while (std::getline(in, line)) {
        if (line.size() < 2) continue;
        std::istringstream s(line.substr(2));
        if (line[0] == 'g' && line[1] == ' ') {
            const std::string group = line.substr(2);
            source = group == "terrain" ? TERRAIN : group == "prop" ? PROP : MODEL;
        } else if (line[0] == 'v' && line[1] == ' ') {
            float x, y, z;
            s >> x >> y >> z;
            verts.push_back(x); verts.push_back(y); verts.push_back(z);
        } else if (line[0] == 'f' && line[1] == ' ') {
            int a, b, c;
            s >> a >> b >> c;
            tris.push_back(a - 1); tris.push_back(b - 1); tris.push_back(c - 1);
            sources.push_back(source);
        }
    }
    return true;
}

static float arg(int argc, char** argv, const char* name, float fallback) {
    size_t n = std::strlen(name);
    for (int i = 3; i < argc; ++i)
        if (!std::strncmp(argv[i], name, n) && argv[i][n] == '=') return std::atof(argv[i] + n + 1);
    return fallback;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: navmesh <in.obj> <out.bin> [cell=0.5] [radius=0.5] [height=2.0] [climb=1.6] [slope=50]\n");
        return 1;
    }
    std::vector<float> verts;
    std::vector<int> tris;
    std::vector<unsigned char> sources;
    if (!loadObj(argv[1], verts, tris, sources)) { std::fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
    const int nverts = (int)verts.size() / 3, ntris = (int)tris.size() / 3;

    rcConfig cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.cs = arg(argc, argv, "cell", 0.5f);
    cfg.ch = cfg.cs * 0.4f;
    cfg.walkableSlopeAngle = arg(argc, argv, "slope", 50.0f);
    cfg.walkableHeight = (int)std::ceil(arg(argc, argv, "height", 2.0f) / cfg.ch);
    cfg.walkableClimb = (int)std::floor(arg(argc, argv, "climb", 1.6f) / cfg.ch);
    cfg.walkableRadius = (int)std::ceil(arg(argc, argv, "radius", 0.5f) / cfg.cs);
    rcCalcBounds(verts.data(), nverts, cfg.bmin, cfg.bmax);
    rcCalcGridSize(cfg.bmin, cfg.bmax, cfg.cs, &cfg.width, &cfg.height);
    std::fprintf(stderr, "%d vertices, %d triangles, grid %d x %d\n", nverts, ntris, cfg.width, cfg.height);

    rcContext ctx(false);
    rcHeightfield* hf = rcAllocHeightfield();
    if (!rcCreateHeightfield(&ctx, *hf, cfg.width, cfg.height, cfg.bmin, cfg.bmax, cfg.cs, cfg.ch)) return 2;
    std::vector<unsigned char> areas(ntris, 0);
    rcMarkWalkableTriangles(&ctx, cfg.walkableSlopeAngle, verts.data(), nverts, tris.data(), ntris, areas.data());
    for (int t = 0; t < ntris; ++t)
        if (areas[t]) areas[t] = sources[t];
    if (!rcRasterizeTriangles(&ctx, verts.data(), nverts, tris.data(), areas.data(), ntris, *hf, cfg.walkableClimb)) return 3;
    rcFilterLowHangingWalkableObstacles(&ctx, cfg.walkableClimb, *hf);
    rcFilterLedgeSpans(&ctx, cfg.walkableHeight, cfg.walkableClimb, *hf);
    rcFilterWalkableLowHeightSpans(&ctx, cfg.walkableHeight, *hf);

    rcCompactHeightfield* chf = rcAllocCompactHeightfield();
    if (!rcBuildCompactHeightfield(&ctx, cfg.walkableHeight, cfg.walkableClimb, *hf, *chf)) return 4;
    rcFreeHeightField(hf);
    if (!rcErodeWalkableArea(&ctx, cfg.walkableRadius, *chf)) return 5;
    if (!rcBuildDistanceField(&ctx, *chf)) return 6;

    // Spans eroded away keep their slot with no area; they are left out, and
    // the rest renumbered.
    std::vector<int> remap(chf->spanCount, -1);
    int kept = 0;
    for (int i = 0; i < chf->spanCount; ++i)
        if (chf->areas[i] != RC_NULL_AREA) remap[i] = kept++;

    FILE* out = std::fopen(argv[2], "wb");
    if (!out) { std::fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    const int version = 2;
    std::fwrite("ORNM", 1, 4, out);
    std::fwrite(&version, 4, 1, out);
    std::fwrite(&chf->width, 4, 1, out);
    std::fwrite(&chf->height, 4, 1, out);
    std::fwrite(chf->bmin, 4, 3, out);
    std::fwrite(&chf->cs, 4, 1, out);
    std::fwrite(&chf->ch, 4, 1, out);
    std::fwrite(&kept, 4, 1, out);
    const int columns = chf->width * chf->height;
    std::vector<unsigned int> first(columns);
    std::vector<unsigned char> count(columns);
    int next = 0;
    for (int c = 0; c < columns; ++c) {
        const rcCompactCell& cell = chf->cells[c];
        first[c] = next;
        int n = 0;
        for (unsigned int i = cell.index; i < cell.index + cell.count; ++i)
            if (remap[i] >= 0) ++n;
        count[c] = (unsigned char)n;
        next += n;
    }
    std::fwrite(first.data(), 4, columns, out);
    std::fwrite(count.data(), 1, columns, out);
    for (int z = 0; z < chf->height; ++z) {
        for (int x = 0; x < chf->width; ++x) {
            const rcCompactCell& cell = chf->cells[x + z * chf->width];
            for (unsigned int i = cell.index; i < cell.index + cell.count; ++i) {
                if (remap[i] < 0) continue;
                const rcCompactSpan& s = chf->spans[i];
                unsigned short y = s.y, dist = chf->dist[i];
                int neighbours[4];
                for (int dir = 0; dir < 4; ++dir) {
                    neighbours[dir] = -1;
                    if (rcGetCon(s, dir) == RC_NOT_CONNECTED) continue;
                    const int nx = x + rcGetDirOffsetX(dir), nz = z + rcGetDirOffsetY(dir);
                    const int ni = (int)chf->cells[nx + nz * chf->width].index + rcGetCon(s, dir);
                    neighbours[dir] = remap[ni];
                }
                std::fwrite(&y, 2, 1, out);
                std::fwrite(&dist, 2, 1, out);
                std::fwrite(neighbours, 4, 4, out);
                std::fwrite(&chf->areas[i], 1, 1, out);
            }
        }
    }
    std::fclose(out);
    std::fprintf(stderr, "%d walkable spans (cell %.2f yd) -> %s\n", kept, cfg.cs, argv[2]);
    return 0;
}
