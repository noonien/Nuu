#!/usr/bin/env python3
"""Compare our extraction with wowforevertalents.com, spell by spell.

    python3 Tools/ProfData/extract.py          # writes .cache/extract.json
    python3 Tools/ProfData/crosscheck.py [--only leatherworking] [--refresh]
                                         [--scope] [--quiet]

Downloads each crafting profession's page, and its category pages (the ones
that carry reagents and the number made), into Tools/ProfData/.cache/ once
(--refresh fetches them again). Every recipe row carries its spell ID and
facts as attributes:

    <li class="pw-row" data-r="<spell>" data-status="new|changed|unchanged"
        data-src="trainer|item" data-learn="N" data-yellow data-green
        data-grey>

inside a <section data-group="<TradeSkillCategory>" data-kind="client|sod">.
Every disagreement with .cache/extract.json is printed, grouped by kind, then
a summary. --scope limits the list to recipes in our shipped scope.

The site states no licence: nothing here is shipped. It is a check only.
"""

import argparse
import html
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
SITE = "https://wowforevertalents.com"
SLUGS = {
    "alchemy": "Alchemy", "blacksmithing": "Blacksmithing", "enchanting": "Enchanting",
    "engineering": "Engineering", "leatherworking": "Leatherworking", "tailoring": "Tailoring",
    "cooking": "Cooking", "first-aid": "FirstAid",
}


def fetch(path, refresh=False):
    """A site page's text, from the cache when it is there."""
    os.makedirs(CACHE, exist_ok=True)
    name = path.strip("/").replace("/", "-") or "index"
    local = os.path.join(CACHE, name + ".html")
    if refresh or not os.path.exists(local):
        request = urllib.request.Request(SITE + path, headers={"User-Agent": "NuuProfessions crosscheck (build time)"})
        with urllib.request.urlopen(request) as response:
            data = response.read()
        with open(local, "wb") as out:
            out.write(data)
        time.sleep(0.5)
    with open(local, encoding="utf-8") as handle:
        return re.sub(r"\s+", " ", handle.read())


def attrs(tag):
    """A tag's attributes; a bare attribute (data-learn) is ""."""
    out = {}
    for match in re.finditer(r'([\w-]+)(?:="([^"]*)")?', tag[1:]):
        out[match.group(1)] = html.unescape(match.group(2)) if match.group(2) is not None else ""
    return out


def number(value):
    if value in (None, ""):
        return None
    return int(value) if value.isdigit() else value  # data-group="removed"


def parse_rows(text):
    """{spell: row facts} of one page, with the group each sits in."""
    rows = {}
    for section in re.split(r'(?=<section class="pw-group)', text)[1:]:
        head = attrs(re.match(r"<section[^>]*>", section).group(0))
        for chunk in re.split(r'(?=<li class="pw-row")', section)[1:]:
            tag = attrs(re.match(r"<li[^>]*>", chunk).group(0))
            spell = int(tag["data-r"])
            row = {
                "status": tag.get("data-status"), "src": tag.get("data-src"),
                "learn": number(tag.get("data-learn")), "yellow": number(tag.get("data-yellow")),
                "green": number(tag.get("data-green")), "grey": number(tag.get("data-grey")),
                "group": number(head.get("data-group")),
                "kind": head.get("data-kind"),
            }
            name = re.search(r'<span class="pw-row-name">(.*?)(?:<i |</span>)', chunk)
            row["name"] = html.unescape(name.group(1)).strip() if name else ""
            detail = re.search(r'<div class="rd" hidden>(.*?)<p class="rd-status">', chunk)
            if detail:
                block = detail.group(1)
                product = re.search(r'<h4 class="rd-name[^"]*"> <a href="[^"]*item=(\d+)"', block)
                row["makes"] = int(product.group(1)) if product else None
                made = re.search(r"<span>Makes (\d+)(?:\D+(\d+))?</span>", block)
                if made:
                    row["made"] = [int(made.group(1)), int(made.group(2) or made.group(1))]
                reagents = re.search(r'<div class="rd-reagents">(.*?)</div>', block)
                if reagents:
                    row["reagents"] = sorted(
                        [int(item), int(count)] for item, count in re.findall(
                            r'item=(\d+)"[^>]*>.*?<b class="rd-count">(\d+)</b>', reagents.group(1)))
                taught = re.search(r"<dt>Taught by</dt> <dd>(.*?)</dd>", block)
                row["taught"] = re.sub(r"<[^>]+>", " ", taught.group(1)).strip() if taught else ""
            rows[spell] = row
    return rows


def site_profession(slug, refresh):
    """Every row of a profession: the main page, then its category pages for
    the detail (reagents, product, number made) the main page leaves out."""
    main = fetch("/professions/%s/" % slug, refresh)
    rows = parse_rows(main)
    pages = sorted(set(re.findall(r'href="(/professions/%s/[\w-]+/)(?:#[\w-]*)?"' % re.escape(slug), main)))
    for page in pages:
        for spell, detail in parse_rows(fetch(page, refresh)).items():
            if spell in rows:
                for key in ("makes", "made", "reagents", "taught"):
                    if key in detail:
                        rows[spell][key] = detail[key]
            else:
                rows[spell] = detail
    return rows, pages


GREEN = {True: 0, False: 0}


def compare(name, ours, site, scope_only):
    """[(kind, spell, message)] for one profession."""
    out = []
    mine = {v["spell"]: v for v in ours.values() if v["profession"] == name}
    for spell in sorted(set(mine) | set(site)):
        a, b = mine.get(spell), site.get(spell)
        if scope_only and (a is None or a["drop"] is not None):
            continue
        label = "%d %s" % (spell, (b or {}).get("name") or (a or {}).get("name", ""))
        if a is not None and a["drop"] is not None:
            label += " [out: %s]" % a["drop"]
        if b is None:
            if a["drop"] != "no skill-up":
                out.append(("only in the client", spell, label))
            continue
        if a is None:
            if b["kind"] != "removed":  # the site's "Not in Forever": Classic Era only, as for us
                out.append(("only on the site", spell, label))
            continue
        if b["kind"] == "removed":
            out.append(("removed", spell, "%s: site says not in Forever" % label))
            continue
        if (b["kind"] == "sod") != (a["drop"] == "sod"):
            out.append(("sod", spell, "%s: site kind %s, client category %s %s" % (
                label, b["kind"], a["category"], a["categoryName"])))
        if b["group"] != a["category"]:
            out.append(("category", spell, "%s: site group %s, client %s" % (label, b["group"], a["category"])))
        yellow, green, grey = a["skills"][1:]
        if (b["yellow"], b["grey"]) != (yellow, grey):
            out.append(("yellow/grey", spell, "%s: site %s/%s, client %s/%s" % (
                label, b["yellow"], b["grey"], yellow, grey)))
        elif b["green"] is not None:
            GREEN[b["green"] == green] += 1
        if b["green"] is not None and (b["yellow"], b["grey"]) == (yellow, grey) and b["green"] != green:
            out.append(("green", spell, "%s: site %s, ceil((y+g)/2) = %s (y %s, g %s)" % (
                label, b["green"], green, yellow, grey)))
        src = "trainer" if a["learn"] in ("start", "trainer") else "item"
        if b["src"] != src:
            out.append(("source", spell, "%s: site %s, client %s (teachers %s)" % (
                label, b["src"], a["learn"], a["teachers"])))
        if a["learn"] == "item" and b["learn"] != a["skills"][0] and \
                not (a["learnFrom"] == "yellow" and b["learn"] is None):  # neither knows the item
            out.append(("learn skill", spell, "%s: site %s, client item %s asks %s (from %s)" % (
                label, b["learn"], a["teach"], a["skills"][0], a["learnFrom"])))
        if a["learn"] == "start" and b["learn"] != 1:
            out.append(("learn skill", spell, "%s: site %s, client known from the start" % (label, b["learn"])))
        if a["learn"] == "trainer" and b["learn"] != (a["skills"][0] if a["learnFrom"] == "era" else None):
            out.append(("learn skill", spell, "%s: site %s, client trainer recipe %s (from %s)" % (
                label, b["learn"], a["skills"][0], a["learnFrom"])))
        if a["forever"] and b["status"] != a["forever"]:
            out.append(("forever", spell, "%s: site %s, ours %s" % (label, b["status"], a["forever"])))
        if "reagents" in b and b["reagents"] != sorted(a["reagents"]):
            out.append(("reagents", spell, "%s: site %s, client %s" % (label, b["reagents"], sorted(a["reagents"]))))
        if b.get("makes") and b["makes"] != a["makes"]:
            out.append(("product", spell, "%s: site item %s, client %s" % (label, b["makes"], a["makes"])))
        if "made" in b and a["made"] and b["made"] != a["made"]:
            out.append(("made", spell, "%s: site %s, client %s" % (label, b["made"], a["made"])))
    return out


def vendor_check(extraction, sites):
    """The authored vendor list. The site names no vendors, so this checks
    what can be checked: every listed item is a reagent the site shows too,
    the client gives it a vendor price, and no reagent the materials rule
    stops on looks like a vendor good that the list misses."""
    items = extraction["items"]
    vendor = set(extraction["vendor"])
    on_site = set()
    for site in sites:
        for row in site.values():
            for item, _ in row.get("reagents", ()):
                on_site.add(item)
    used = {}
    for recipe in extraction["recipes"].values():
        if recipe["drop"] in (None, "materials"):
            for item, _ in recipe["reagents"]:
                used[item] = used.get(item, 0) + 1
    lines = []
    for item in sorted(vendor):
        facts = items.get(str(item), {})
        notes = []
        if item not in on_site:
            notes.append("not a reagent on the site")
        if not used.get(item):
            notes.append("no in-scope or materials-dropped recipe uses it")
        if not facts.get("buy"):
            notes.append("no BuyPrice in the client")
        if notes:
            lines.append("  listed %d %s: %s" % (item, facts.get("name", "?"), "; ".join(notes)))
    blocked = {}
    for recipe in extraction["recipes"].values():
        for item in recipe.get("missing", ()):
            blocked[item] = blocked.get(item, 0) + 1
    for item, count in sorted(blocked.items(), key=lambda kv: -kv[1]):
        facts = items.get(str(item), {})
        # Forever's own new white goods (SAF-T, EZ-Thro) and anything its
        # text says is sold: the likeliest vendor goods the list lacks.
        if "vendor" in facts.get("text", "").lower() or (item >= 200000 and facts.get("quality") == 1):
            lines.append("  unlisted %d %s (ilvl %s, white, buy %s) stops %d recipes: vendor good?" % (
                item, facts.get("name", "?"), facts.get("ilvl"), facts.get("buy"), count))
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", action="append", help="a site slug (repeatable)")
    parser.add_argument("--refresh", action="store_true", help="download the pages again")
    parser.add_argument("--scope", action="store_true", help="only recipes in our shipped scope")
    parser.add_argument("--quiet", action="store_true", help="the summary only")
    args = parser.parse_args()

    path = os.path.join(CACHE, "extract.json")
    if not os.path.exists(path):
        sys.exit("run Tools/ProfData/extract.py first (it writes %s)" % path)
    with open(path) as handle:
        extraction = json.load(handle)
    ours = extraction["recipes"]
    summary = []
    sites = []
    for slug, name in SLUGS.items():
        if args.only and slug not in args.only:
            continue
        site, pages = site_profession(slug, args.refresh)
        sites.append(site)
        found = compare(name, ours, site, args.scope)
        kinds = {}
        for kind, _, _ in found:
            kinds[kind] = kinds.get(kind, 0) + 1
        mine = [v for v in ours.values() if v["profession"] == name]
        kept = [v for v in mine if v["drop"] is None]
        in_scope = sum(1 for kind, spell, _ in found
                       if ours.get("%s:%d" % (name, spell), {}).get("drop", "x") is None)
        detailed = sum(1 for row in site.values() if "reagents" in row)
        summary.append("%-15s site %3d (%d sod, %d removed, %d with reagents from %d pages), client %3d, "
                       "in scope %3d: "
                       "%d disagreements (%d in scope)%s" % (
                           name, len(site), sum(1 for r in site.values() if r["kind"] == "sod"),
                           sum(1 for r in site.values() if r["kind"] == "removed"), detailed,
                           len(pages), len(mine), len(kept), len(found), in_scope,
                           "".join("\n                  %-20s %d" % kv for kv in sorted(kinds.items()))))
        if args.quiet:
            continue
        print("== %s ==" % name)
        for kind in sorted(kinds):
            print("  -- %s (%d)" % (kind, kinds[kind]))
            for this, _, message in found:
                if this == kind:
                    print("    " + message)
    print()
    print("Summary (build %s, contentLevel %s)" % (extraction["build"], extraction["contentLevel"]))
    for line in summary:
        print(line)
    print("Green = ceil((yellow + grey) / 2): %d recipes agree with the site, %d do not" % (
        GREEN[True], GREEN[False]))
    print()
    print("Authored vendor list (%d items):" % len(extraction["vendor"]))
    for line in vendor_check(extraction, sites) or ["  nothing to report"]:
        print(line)


if __name__ == "__main__":
    main()
