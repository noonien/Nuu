#!/usr/bin/env python3
"""Build the Nuu addons for release, each with its own copy of NuuKit and no development code.

    python3 Tools/Build.py [--out dist] [--version X] [--no-zip] [--no-lua] [--tag] [Addon ...]

With no addon named, builds every folder beside this one that has a TOC
named after it, except NuuKit. For each addon it writes <out>/<Addon>/, <out>/<Addon>-<version>.zip and
<out>/<Addon>-<version>-changelog.md. What goes in:

- the addon's TOC and every file it lists, in order, except the files between `#@debug@` and `#@end-debug@`;
  `NuuKit` leaves `## Dependencies`, and the kit's files come first;
- the kit, under Libs/NuuKit/: every file NuuKit.toc lists outside its `#@debug@` block (so never NuuKit.lua or
  Dev/), and all of Media/. A generated Libs/NuuKit/Embed.lua, loaded first, tells the kit where it sits;
- Bindings.xml when the addon has one, since the client loads it by name;
- every Art/ texture the shipped code names, and the icon `## IconTexture` names (Tools/Icons.py makes them).

In every shipped .lua file, the lines from `--@debug@` to `--@end-debug@` are left out. `ns.version` in Core.lua
and `## Version` in the TOC are set to the version: --version, else the TOC's.

A file the TOC lists or the code names that is missing stops the build, and so do non-ASCII text, a leftover
debug marker, and anything from Dev/, Tests/ or Tools/ in the output. A .lua file in API/, Data/, Domain/ or UI/
that the TOC does not list is reported, since the game never loads it. Unless --no-lua, every shipped .lua file
is compiled and Tools/BuildTests.lua loads the built addons on the kit's stand-in for the client, alone and
together; Lua comes from PATH or, failing that, nix-shell.

Each distribution is tagged <Addon>-v<version>. The changelog lists the commit subjects since that addon's tag
before it, newest first, keeping only commits that touch its shipped files or the kit's and dropping any subject
that names another guide addon. --tag tags HEAD first, and needs a clean tree and a version not yet tagged.
"""

import argparse
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = "NuuKit"
DEV_ADDONS = ("NuuExperiments",)  # development only, never built
KIT_DIR = "Libs/NuuKit/"
EMBED = KIT_DIR + "Embed.lua"
ALWAYS = ["Bindings.xml"]
RUNTIME_DIRS = ["API", "Data", "Domain", "UI"]
DEV_DIRS = ("Dev/", "Tests/", "Tools/", "docs/")
DEBUG_START, DEBUG_END = "#@debug@", "#@end-debug@"
LUA_START, LUA_END = "--@debug@", "--@end-debug@"
UNNAMED = re.compile(r"zygor|restedxp|rxp", re.I)
TEXT = (".lua", ".toc", ".xml", ".md")

EMBED_SOURCE = """local _, ns = ...

-- Written by Tools/Build.py. The kit is embedded under Libs/NuuKit/; its
-- textures are found through Kit.folder (NuuKit/UI/Theme/Themes.lua).
ns.Kit = ns.Kit or {}
ns.Kit.folder = "Libs\\\\NuuKit\\\\"
"""


def fail(message):
    sys.exit("build stopped: " + message)


def release_toc(toc_text):
    """The TOC without its #@debug@ blocks, and the files those blocks listed."""
    kept, dropped, in_debug = [], [], False
    for line in toc_text.splitlines(True):
        marker = line.strip()
        if marker in (DEBUG_START, DEBUG_END):
            if (marker == DEBUG_START) == in_debug:
                fail("unbalanced %s in a TOC" % marker)
            in_debug = marker == DEBUG_START
        elif in_debug:
            dropped.append(marker)
        else:
            kept.append(line)
    if in_debug:
        fail("a TOC's #@debug@ block never ends")
    return "".join(kept), [d for d in dropped if d and not d.startswith("#")]


def toc_files(toc_text):
    files = []
    for line in toc_text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def toc_field(toc_text, field):
    match = re.search(r"^## " + field + r":\s*(.+)$", toc_text, re.M)
    return match.group(1).strip() if match else None


def strip_lua(text, name):
    """The file without its --@debug@ blocks."""
    out, in_debug = [], False
    for line in text.splitlines(True):
        marker = line.strip()
        if marker in (LUA_START, LUA_END):
            if (marker == LUA_START) == in_debug:
                fail("unbalanced %s in %s" % (marker, name))
            in_debug = marker == LUA_START
        elif not in_debug:
            out.append(line)
    if in_debug:
        fail("%s: --@debug@ block never ends" % name)
    return "".join(out)


def git(*args, check=True):
    result = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.exit("git %s: %s" % (" ".join(args), result.stderr.strip()))
    return result.stdout.strip() if result.returncode == 0 else None


def tag_exists(tag):
    return git("rev-parse", "-q", "--verify", "refs/tags/" + tag, check=False) is not None


def shipped_path(path, addon):
    """Whether a repository path is shipped with the addon: its own runtime files or the kit's."""
    for folder in (addon, KIT):
        prefix = folder + "/"
        if path.startswith(prefix):
            rest = path[len(prefix):]
            return not (rest.startswith(DEV_DIRS) or rest.endswith(".md") or rest == KIT + ".lua")
    return False


def changelog(addon, version, tag):
    """Markdown for the commits between the addon's previous tag and this distribution."""
    end = tag if tag_exists(tag) else "HEAD"
    previous = git("describe", "--tags", "--abbrev=0", "--match", addon + "-v*", end + "^", check=False)
    span = (previous + ".." + end) if previous else end
    log = git("log", "--no-merges", "--format=%x01%s", "--name-only", span)
    entries, dropped = [], []
    for record in log.split("\x01")[1:]:
        lines = [l for l in record.splitlines() if l.strip()]
        subject, paths = lines[0], lines[1:]
        if not any(shipped_path(p, addon) for p in paths):
            continue
        (dropped if UNNAMED.search(subject) else entries).append(subject)
    text = "# %s %s\n\n" % (addon, version)
    text += ("Changes since %s:\n\n" % previous) if previous else "First release.\n\n"
    text += "".join("- %s\n" % e for e in entries) or "- No changes to the addon itself.\n"
    return text, end, dropped


def kit_files():
    """The kit's shipped files, as paths inside NuuKit/: its TOC without the debug block, and Media/."""
    toc_text, _ = release_toc((ROOT / KIT / (KIT + ".toc")).read_text(encoding="ascii"))
    files = toc_files(toc_text)
    for f in files:
        if f.startswith("Dev/") or f == KIT + ".lua":
            fail("NuuKit.toc lists %s outside its #@debug@ block" % f)
    media = sorted(p.relative_to(ROOT / KIT).as_posix() for p in (ROOT / KIT / "Media").rglob("*") if p.is_file())
    return files, media


def release_addon_toc(toc_text, version, kit_lua):
    """The addon's TOC for release: its version, NuuKit dropped from its dependencies, the kit first."""
    lines, inserted = [], False
    for line in toc_text.splitlines():
        field = re.match(r"^## (\w+):\s*(.*)$", line)
        if field and field.group(1) == "Version":
            line = "## Version: " + version
        elif field and field.group(1) in ("Dependencies", "RequiredDeps"):
            deps = [d.strip() for d in field.group(2).split(",") if d.strip() and d.strip() != KIT]
            if not deps:
                continue
            line = "## %s: %s" % (field.group(1), ", ".join(deps))
        elif not inserted and line.strip() and not line.startswith("#"):
            lines += ["# NuuKit, embedded by Tools/Build.py", EMBED] + [KIT_DIR + f for f in kit_lua] + [""]
            inserted = True
        lines.append(line)
    if not inserted:
        fail("the TOC lists no files")
    return "\n".join(lines) + "\n"


def lua_command():
    if shutil.which("lua") and shutil.which("luac"):
        return lambda script: ["sh", "-c", script]
    if shutil.which("nix-shell"):
        return lambda script: ["nix-shell", "-p", "lua5_1", "--run", script]
    fail("no lua or nix-shell on PATH (pass --no-lua to skip the Lua checks)")


def build(addon, args, kit_lua, kit_media):
    source = ROOT / addon
    toc_name = addon + ".toc"
    toc_text, debug_files = release_toc((source / toc_name).read_text(encoding="ascii"))
    version = args.version or toc_field(toc_text, "Version") or "dev"
    tag = "%s-v%s" % (addon, version)
    if args.tag:
        if tag_exists(tag):
            fail("%s is already tagged: bump ## Version in %s" % (tag, toc_name))
        git("tag", "-a", tag, "-m", "%s %s" % (addon, version))
        print("tagged HEAD as %s" % tag)

    listed = toc_files(toc_text)
    for f in listed:
        if f.startswith(DEV_DIRS):
            fail("%s lists %s outside a #@debug@ block" % (toc_name, f))
    own = listed + [f for f in ALWAYS if (source / f).is_file()]
    missing = [f for f in own if not (source / f).is_file()]
    if missing:
        fail("%s: missing files: %s" % (addon, ", ".join(missing)))

    art_ref = re.compile(r"AddOns[\\/]+" + addon + r"[\\/]+(Art[\\/]+[A-Za-z0-9_.\\/]+)")
    art = set()
    for f in own:
        if f.endswith((".lua", ".xml")):
            for ref in art_ref.findall((source / f).read_text(encoding="utf-8", errors="replace")):
                art.add(re.sub(r"[\\/]+", "/", ref))
    missing = sorted(a for a in art if not (source / a).is_file())
    if missing:
        fail("%s: textures named in code but missing: %s" % (addon, ", ".join(missing)))
    own += sorted(art)

    icon_ref = re.compile(r"Interface[\\/]+AddOns[\\/]+" + addon + r"[\\/]+(.+)$", re.I)
    icon = icon_ref.match(toc_field(toc_text, "IconTexture") or "")
    if icon:
        icon = re.sub(r"[\\/]+", "/", icon.group(1).strip())
        if not (source / icon).is_file():
            fail("%s: the icon its TOC names is missing: %s" % (addon, icon))
        own.append(icon)

    known = set(listed) | set(debug_files)
    for d in RUNTIME_DIRS:
        for path in sorted((source / d).rglob("*.lua")):
            rel = path.relative_to(source).as_posix()
            if rel not in known:
                print("  not in the TOC, left out: " + rel)

    # Every output file: its path in the addon folder, and its source (None for generated text).
    out = (ROOT / args.out).resolve()
    target = out / addon
    if target.exists():
        shutil.rmtree(target)
    contents = {toc_name: release_addon_toc(toc_text, version, kit_lua), EMBED: EMBED_SOURCE}
    sources = {}
    for f in kit_lua + kit_media:
        sources[KIT_DIR + f] = ROOT / KIT / f
    for f in own:
        if f != toc_name:
            sources[f] = source / f
    for rel, path in sources.items():
        if rel.endswith(".lua"):
            text = strip_lua(path.read_text(encoding="utf-8"), path.relative_to(ROOT).as_posix())
            if rel == "Core.lua":
                text, count = re.subn(r'^ns\.version = ".*"$', 'ns.version = "%s"' % version, text, flags=re.M)
                if count != 1:
                    fail("%s/Core.lua: expected one ns.version line, found %d" % (addon, count))
            contents[rel] = text

    files = sorted(set(contents) | set(sources), key=lambda f: (f != toc_name, f))
    for rel in files:
        if rel.startswith(DEV_DIRS) or re.search(r"(^|/)(Dev|Tests|Tools)/", rel) or rel.endswith("/" + KIT + ".lua"):
            fail("%s: development file in the output: %s" % (addon, rel))
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if rel in contents:
            dest.write_bytes(contents[rel].encode("utf-8"))
        else:
            shutil.copy2(sources[rel], dest)
        if rel.endswith(TEXT):
            data = dest.read_bytes()
            bad = next((i for i, b in enumerate(data) if b > 127), None)
            if bad is not None:
                line = data[:bad].count(b"\n") + 1
                fail("%s/%s:%d: non-ASCII text" % (addon, rel, line))
            if b"@debug@" in data or b"@end-debug@" in data:
                fail("%s/%s: a debug marker is left in the output" % (addon, rel))
    print("%s %s: %d files -> %s (%d dev files left out)" % (addon, version, len(files), target, len(debug_files)))

    notes, end, dropped = changelog(addon, version, tag)
    notes_path = out / ("%s-%s-changelog.md" % (addon, version))
    notes_path.write_text(notes, encoding="ascii", errors="replace")
    print("  changelog -> %s (up to %s)" % (notes_path.name, end))
    for subject in dropped:
        print("  left out, names another addon: " + subject)

    if not args.no_zip:
        zip_path = out / ("%s-%s.zip" % (addon, version))
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
            for f in files:
                z.write(target / f, addon + "/" + f)
        print("  zip -> %s" % zip_path.name)
    return target, [f for f in files if f.endswith(".lua")]


def main():
    sys.stdout.reconfigure(line_buffering=True)
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("addons", nargs="*", help="addons to build (default: all)")
    parser.add_argument("--out", default="dist", help="output folder, relative to the repository root")
    parser.add_argument("--version", help="the version to ship (default: each TOC's ## Version)")
    parser.add_argument("--no-zip", action="store_true", help="write the folders only")
    parser.add_argument("--no-lua", action="store_true", help="skip compiling and the smoke test")
    parser.add_argument("--tag", action="store_true", help="tag HEAD as <Addon>-v<version> before building")
    args = parser.parse_args()

    addons = args.addons or sorted(p.name for p in ROOT.iterdir()
                                   if p.is_dir() and p.name != KIT and p.name not in DEV_ADDONS and (p / (p.name + ".toc")).is_file())
    for addon in addons:
        if addon == KIT or addon in DEV_ADDONS or not (ROOT / addon / (addon + ".toc")).is_file():
            fail("%s is not an addon to build" % addon)
    dirty = git("status", "--porcelain")
    if args.tag and dirty:
        fail("--tag needs a clean tree: commit first, so the tag is what ships")

    kit_lua, kit_media = kit_files()
    built = [build(addon, args, kit_lua, kit_media) for addon in addons]
    if dirty:
        print("the tree has uncommitted changes: the build has them, the changelogs do not")

    if args.no_lua:
        print("Lua checks skipped")
        return
    run = lua_command()
    out = (ROOT / args.out).resolve()
    for target, lua in built:
        script = "cd '%s' && luac -p %s" % (target, " ".join("'%s'" % f for f in lua))
        if subprocess.run(run(script)).returncode != 0:
            fail("%s does not compile" % target.name)
    names = [target.name for target, _ in built]
    runs = [[n] for n in names] + ([names] if len(names) > 1 else [])
    script = " && ".join("lua Tools/BuildTests.lua '%s' %s" % (out, " ".join(r)) for r in runs)
    if subprocess.run(run("cd '%s' && %s" % (ROOT, script))).returncode != 0:
        fail("the built addons do not load")


if __name__ == "__main__":
    main()
