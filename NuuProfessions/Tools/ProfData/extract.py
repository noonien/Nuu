#!/usr/bin/env python3
"""The crafting professions' recipe tables, out of the Forever client.

    python3 Tools/ProfData/extract.py [--content-level 20] [--margin 5]
                                      [--only Leatherworking] [--dry-run]
                                      [--out Data/Professions] [--table professionData]

Reads the beta client's DB2 tables offline (Tools/ClientMap/casc.py and
db2.py, product wow_classic_beta; ClientMap is NuuRoad's, see
README.md) and writes Data/Professions/<Name>.lua, one
file per crafting profession, holding only what a character can use by the
beta's level cap (`contentLevel`):

  SkillLineAbility    recipe spell -> profession, yellow and grey skills
                      (TrivialSkillLineRankLow / High), AcquireMethod 1 =
                      known when the profession is learned, and the
                      TradeSkillCategory it is filed under
  TradeSkillCategory  the "SEASON OF DISCOVERY" heading: those recipes cannot
                      be learned on Forever and are left out
  SpellReagents       reagents and counts
  SpellEffect         CREATE_ITEM (24): the product; EffectBasePointsF is the
                      middle of the number made and Variance its relative
                      spread (min = base * (1 - v/2), max = base * (1 + v/2);
                      checked against Classic Era's BasePoints + DieSides)
  ItemEffect,         which recipe item teaches which spell (the effect whose
  ItemXItemEffect     TriggerType is 6, "on learn")
  ItemSparse          prices, item level, quality, required level, binding,
                      and the recipe item's RequiredSkillRank (the learn skill)
  Item                the item class (weapon, armour: what disenchants)

The Classic Era client in the same store gives the `forever` mark: a recipe
spell Classic Era lacks is "new"; one whose bands, reagents or product differ
is "changed"; the rest are "unchanged".

The client does not know which materials a vendor sells, nor what skill a
trainer asks for a recipe. The first is the authored VENDOR list below
(provenance "authored", cross-checked by crosscheck.py); for the second,
skills[1] of a trainer recipe is its yellow skill (see README.md).

Also writes Tools/ProfData/.cache/extract.json: every client recipe, in scope
or not and why, for crosscheck.py.

The full-scope testing set, which lets the planner plan past the beta's cap,
is a second run into its own directory and table:

    python3 Tools/ProfData/extract.py --content-level 60 \
        --out Data/ProfessionsFull --table professionDataFull

It fills ns.professionDataFull.<Name>, and its cache is
.cache/extract.professionDataFull.json, so crosscheck.py keeps reading the
beta set's.
"""

import argparse
import datetime
import json
import math
import os
import pickle
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(os.path.join(HERE, "..", ".."))
# The CASC and DB2 readers are NuuRoad's (NuuRoad/Tools/ClientMap);
# CLIENTMAP names another copy.
CLIENTMAP = os.environ.get("CLIENTMAP") or os.path.normpath(
    os.path.join(ADDON, "..", "NuuRoad", "Tools", "ClientMap"))
sys.path.insert(0, CLIENTMAP)
import casc  # noqa: E402
import db2  # noqa: E402

CACHE = os.path.join(HERE, ".cache")
DEFAULT_OUT = os.path.join("Data", "Professions")
DEFAULT_TABLE = "professionData"
WOW_ROOT = casc.WOW_ROOT

# The crafting professions, in the order the planner work takes them.
PROFESSIONS = [
    ("Leatherworking", 165),
    ("Tailoring", 197),
    ("Blacksmithing", 164),
    ("Alchemy", 171),
    ("Enchanting", 333),
    ("Engineering", 202),
    ("Cooking", 185),
    ("FirstAid", 129),
    # Not planned itself (its skill comes from gathering), but its smelting
    # recipes make the bars other professions need: the planner uses them
    # for a character who has Mining.
    ("Mining", 186),
]

# Classic's trainer tiers: the character level each needs and the skill it
# allows. Unverified on Forever; Data/ProfessionTiers.lua is the addon's copy.
TIERS = [(1, 75), (10, 150), (20, 225), (35, 300)]

CREATE_ITEM = 24
ON_LEARN = 6
SOD_CATEGORY = "SEASON OF DISCOVERY"

# Materials a vendor sells. The client cannot say this (ItemSparse.BuyPrice is
# set on nearly every item), so it is authored from Classic's trade goods
# vendors. Provenance "authored"; crosscheck.py compares it with the site.
VENDOR = {
    159: "Refreshing Spring Water",
    1179: "Ice Cold Milk",
    2320: "Coarse Thread",
    2321: "Fine Thread",
    2324: "Bleach",
    2325: "Black Dye",
    2604: "Red Dye",
    2605: "Green Dye",
    2678: "Mild Spices",
    2692: "Hot Spices",
    2880: "Weak Flux",
    2894: "Rhapsody Malt",
    3371: "Empty Vial",
    3372: "Leaded Vial",
    3466: "Strong Flux",
    3713: "Soothing Spices",
    4289: "Salt",
    4291: "Silken Thread",
    4340: "Gray Dye",
    4341: "Yellow Dye",
    4342: "Purple Dye",
    4399: "Wooden Stock",
    4400: "Heavy Stock",
    4470: "Simple Wood",
    6217: "Copper Rod",
    6260: "Blue Dye",
    6261: "Orange Dye",
    8343: "Heavy Silken Thread",
    8925: "Crystal Vial",
    10290: "Pink Dye",
    10647: "Engineer's Ink",
    10648: "Blank Parchment",
    14341: "Rune Thread",
    18256: "Imbued Vial",
    247786: "Mote of Magic",  # the client's own item text: "Available from enchanting vendors."
}


def build_version(product):
    """The installed build of a product, from the launcher's .build.info."""
    path = os.path.join(WOW_ROOT, ".build.info")
    with open(path, encoding="utf-8") as handle:
        head = handle.readline().rstrip("\n").split("|")
        names = [column.split("!")[0] for column in head]
        for line in handle:
            row = dict(zip(names, line.rstrip("\n").split("|")))
            if row.get("Product") == product:
                return row.get("Version")
    return None


def tables(product, names):
    """The named tables of a product, cached per build (ItemSparse is slow)."""
    os.makedirs(CACHE, exist_ok=True)
    build = build_version(product) or "unknown"
    path = os.path.join(CACHE, "tables-%s-%s.pickle" % (product, build))
    have = {}
    if os.path.exists(path):
        with open(path, "rb") as handle:
            have = pickle.load(handle)
    missing = [name for name in names if name not in have]
    if missing:
        storage = casc.Storage(product)
        for name in missing:
            try:
                have[name] = db2.read(storage, name)
            except (OSError, ValueError, IndexError) as error:
                print("  %s %s: %s" % (product, name, error), file=sys.stderr)
                have[name] = []
        with open(path, "wb") as handle:
            pickle.dump(have, handle)
    return build, have


def made_range(effect):
    """(min, max) made by a CREATE_ITEM effect."""
    if "EffectBasePointsF" in effect:  # the Forever client
        base = effect["EffectBasePointsF"]
        spread = effect.get("Variance") or 0.0
        if base <= 0:
            return 1, 1
        low = int(math.floor(base * (1 - spread / 2) + 0.5))
        high = int(math.floor(base * (1 + spread / 2) + 0.5))
        return max(1, low), max(1, high)
    base, sides = effect.get("EffectBasePoints", 0), effect.get("EffectDieSides", 0)
    if sides > 0:
        return max(1, base + 1), max(1, base + sides)
    return max(1, base), max(1, base)


def bind_of(bonding):
    """ItemSparse.Bonding as the planner needs it: can it change hands?"""
    if bonding in (1, 4):  # on pickup, quest item
        return "bop"
    if bonding in (2, 3):  # on equip, on use
        return "boe"
    return None


class Client:
    """One client's recipe facts, by spell."""

    def __init__(self, product, full):
        names = ["SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse", "Item"]
        if full:
            names += ["ItemEffect", "ItemXItemEffect", "TradeSkillCategory", "SpellName", "SkillLine"]
        self.build, t = tables(product, names)
        self.abilities = t["SkillLineAbility"]
        self.reagents = {}
        for row in t["SpellReagents"]:
            pairs = [(item, count) for item, count in zip(row["Reagent"], row["ReagentCount"]) if item > 0]
            self.reagents[row["SpellID"]] = pairs
        self.creates, self.effects = {}, {}
        for row in t["SpellEffect"]:
            if row.get("DifficultyID", 0) != 0:
                continue
            self.effects.setdefault(row["SpellID"], set()).add(row["Effect"])
            if row["Effect"] == CREATE_ITEM and row["EffectItemType"] > 0:
                known = self.creates.get(row["SpellID"])
                if known is None or row["EffectIndex"] < known[0]:
                    self.creates[row["SpellID"]] = (row["EffectIndex"], row["EffectItemType"], made_range(row))
        self.items = {row["ID"]: row for row in t["ItemSparse"]}
        self.classes = {row["ID"]: row["ClassID"] for row in t["Item"]}
        self.teachers = {}
        if full:
            effects = {row["ID"]: row for row in t["ItemEffect"]}
            links = [(row["ItemID"], row["ItemEffectID"]) for row in t["ItemXItemEffect"]]
            # Older layouts keep the item on the effect itself.
            links += [(row["ParentItemID"], row["ID"]) for row in t["ItemEffect"] if row.get("ParentItemID")]
            for item, effect_id in links:
                effect = effects.get(effect_id)
                if effect and effect["TriggerType"] == ON_LEARN and effect["SpellID"] > 0:
                    self.teachers.setdefault(effect["SpellID"], set()).add(item)
            self.categories = {row["ID"]: row for row in t["TradeSkillCategory"]}
            self.spell_names = {row["ID"]: row["Name_lang"] for row in t["SpellName"]}
            self.skill_names = {row["ID"]: row["DisplayName_lang"] for row in t["SkillLine"]}

    def recipe_facts(self, spell):
        """What decides the `forever` mark: bands, reagents, product."""
        return {
            "reagents": sorted(self.reagents.get(spell, [])),
            "makes": self.creates.get(spell, (0, None, None))[1],
            "made": self.creates.get(spell, (0, None, None))[2],
        }

    def item_name(self, item):
        row = self.items.get(item)
        return row["Display_lang"] if row else "?"


def forever_status(spell, row, beta, era, era_rows):
    """new | changed | unchanged against Classic Era's same profession, or
    None without Classic Era."""
    if era is None:
        return None
    old = era_rows.get((row["SkillLine"], spell))
    if old is None:
        return "new"
    same_bands = (old["TrivialSkillLineRankLow"], old["TrivialSkillLineRankHigh"]) == \
        (row["TrivialSkillLineRankLow"], row["TrivialSkillLineRankHigh"])
    facts = beta.recipe_facts(spell)
    same = same_bands and facts == era.recipe_facts(spell)
    return "unchanged" if same else "changed"


def teacher_of(spell, beta):
    """The recipe item that teaches a spell, and every item that does. One the
    Forever client has an ItemSparse row for comes first, then a tradeable
    one, then the lowest ID."""
    items = sorted(beta.teachers.get(spell, ()))
    if not items:
        return None, []

    def key(item):
        row = beta.items.get(item)
        return (row is None, bind_of((row or {}).get("Bonding", 0)) == "bop", item)
    return sorted(items, key=key)[0], items


def pattern_bind(item, beta, era):
    """A recipe item's binding: "bop" when only its finder can use it, "boe"
    when it can change hands (no binding counts as that), None unknown."""
    row = item_row(item, beta, era)[0] if item else None
    if row is None:
        return None
    return bind_of(row["Bonding"]) or "boe"


def item_row(item, beta, era):
    """(ItemSparse row, where from). The Forever client's ItemSparse lacks
    some items the Item table has (the game fetches those from the server);
    Classic Era's row stands in for such an item when it has one."""
    if item in beta.items:
        return beta.items[item], "client"
    if era and item in era.items:
        return era.items[item], "era"
    return None, None


def extract(args):
    beta = Client("wow_classic_beta", True)
    try:
        era = Client("wow_classic_era", False)
    except OSError as error:
        print("Classic Era is not readable (%s): `forever` stays nil" % error, file=sys.stderr)
        era = None
    ceiling = max(cap for level, cap in TIERS if level <= args.content_level)
    ilvl_limit = args.content_level + args.margin
    sod = {cid for cid, row in beta.categories.items() if row["Name_lang"].strip().upper() == SOD_CATEGORY}
    era_rows = {}
    if era:
        for row in era.abilities:
            era_rows.setdefault((row["SkillLine"], row["Spell"]), row)

    # Every recipe of the professions, before any scope rule.
    recipes = {}
    for name, line in PROFESSIONS:
        seen = set()
        for row in beta.abilities:
            if row["SkillLine"] != line or row["Spell"] in seen:
                continue
            spell = row["Spell"]
            seen.add(spell)
            low, high = row["TrivialSkillLineRankLow"], row["TrivialSkillLineRankHigh"]
            teach, teachers = teacher_of(spell, beta)
            learn_from = "client"
            if row["AcquireMethod"] == 1:
                learn, learn_skill = "start", 1
            elif teach:
                # The recipe item's own requirement: from Classic Era's row
                # when Forever's ItemSparse lacks the item, else the yellow skill.
                learn = "item"
                pattern, learn_from = item_row(teach, beta, era)
                learn_skill = (pattern or {}).get("RequiredSkillRank", 0)
                if not learn_skill:
                    learn_skill, learn_from = low, "yellow"
            else:
                # Forever's SkillLineAbility sets MinSkillLineRank to 1 on
                # every recipe, and a trainer's requirement is the server's.
                # Classic Era's client still has it: when the recipe's bands
                # are Classic Era's, its learn skill is taken from there;
                # otherwise the yellow skill stands in for it.
                learn, learn_skill, learn_from = "trainer", low, "yellow"
                old = era_rows.get((line, spell))
                if old and old["MinSkillLineRank"] > 1 and \
                        (old["TrivialSkillLineRankLow"], old["TrivialSkillLineRankHigh"]) == (low, high) and \
                        old["MinSkillLineRank"] <= low:
                    learn_skill = old["MinSkillLineRank"]
                    learn_from = "era"
            create = beta.creates.get(spell)
            recipes["%s:%d" % (name, spell)] = {
                "profession": name, "skillLine": line, "spell": spell,
                "name": beta.spell_names.get(spell, ""),
                "category": row["TradeSkillCategoryID"],
                "categoryName": beta.categories.get(row["TradeSkillCategoryID"], {}).get("Name_lang", ""),
                "makes": create[1] if create else None,
                "made": list(create[2]) if create else None,
                "skills": [learn_skill, low, int(math.ceil((low + high) / 2.0)), high],
                "reagents": [list(pair) for pair in beta.reagents.get(spell, [])],
                "learn": learn, "learnFrom": learn_from, "teach": teach, "teachers": teachers,
                "bind": pattern_bind(teach, beta, era),
                "forever": forever_status(spell, row, beta, era, era_rows),
                "acquire": row["AcquireMethod"],
                "effects": sorted(beta.effects.get(spell, ())),
            }

    # Scope: the rules that do not depend on other recipes.
    for recipe in recipes.values():
        low, high = recipe["skills"][1], recipe["skills"][3]
        if recipe["category"] in sod:
            recipe["drop"] = "sod"
        elif recipe["acquire"] == 3:
            # AcquireMethod 3: Classic Era recipes Forever took out (most have
            # lost their spell name and product too).
            recipe["drop"] = "removed"
        elif recipe["category"] == 0 or high == 0:
            # Tier training spells, and "Adaptive" upgrades that have no
            # colour bands and so give no skill.
            recipe["drop"] = "no skill-up"
        elif recipe["skills"][0] > ceiling:
            recipe["drop"] = "skill"
        else:
            recipe["drop"] = None

    # Materials, to a fixpoint: start from nothing and add every recipe whose
    # reagents are all vendor-sold, low enough, or made by a recipe already in.
    def plain(item):
        row = item_row(item, beta, era)[0]
        return item in VENDOR or (row is not None and row["ItemLevel"] <= ilvl_limit)

    candidates = [r for r in recipes.values() if r["drop"] is None]
    included, made = set(), set()
    changed = True
    while changed:
        changed = False
        for recipe in candidates:
            if id(recipe) in included:
                continue
            if all(plain(item) or item in made for item, _ in recipe["reagents"]):
                included.add(id(recipe))
                if recipe["makes"]:
                    made.add(recipe["makes"])
                changed = True
    for recipe in candidates:
        if id(recipe) not in included:
            recipe["drop"] = "materials"
            recipe["missing"] = [item for item, _ in recipe["reagents"] if not plain(item) and item not in made]
    return beta, era, recipes, ceiling, ilvl_limit, sod


def reach(recipes, ceiling):
    """Walking up from skill 1, the first skill at which no in-scope recipe can
    be made and is still not grey, by colour: (orange, yellow, any)."""
    out = []
    for colour in (1, 2, 3):  # stop at yellow, green, grey
        skill = 1
        while skill < ceiling:
            if not any(r["skills"][0] <= skill < r["skills"][colour] for r in recipes):
                break
            skill += 1
        out.append(skill)
    return out


def lua_list(values):
    return "{ " + ", ".join(str(v) for v in values) + " }"


def write_lua(name, line, recipes, beta, era, build, args, today):
    items = {}
    for recipe in recipes:
        teach = recipe["teach"] if recipe["learn"] == "item" else None
        for item in [recipe["makes"], teach] + [pair[0] for pair in recipe["reagents"]]:
            if item:
                items[item] = item_row(item, beta, era)
    full = args.table != DEFAULT_TABLE
    out_rel = os.path.relpath(args.out_dir, ADDON).replace(os.sep, "/")
    out = []
    out.append("-- %s/%s.lua" % (out_rel, name))
    out.append("-- Generated by Tools/ProfData/extract.py from the Forever client's DB2 tables. Do not edit.")
    if full:
        # The testing set: every recipe to the content level asked for, past
        # what the beta lets a character reach. Not the beta's own data.
        out.append("-- FULL-SCOPE TESTING SET (ns.%s), contentLevel %d: plans past the beta's cap and" %
                   (args.table, args.content_level))
        out.append("-- can name materials this beta does not have yet. The beta's own set is Data/Professions.")
    out.append("-- build %s, contentLevel %d, margin %d, generated %s" %
               (build, args.content_level, args.margin, today))
    out.append("-- %d recipes, %d items. skills = { learn, yellow, green, grey }. A trainer's required skill" %
               (len(recipes), len(items)))
    out.append("-- is not in the Forever client: a trainer recipe's learn skill is Classic Era's when its bands")
    out.append("-- are unchanged, else its yellow skill. See Tools/ProfData/README.md.")
    out.append("local _, ns = ...")
    out.append("ns.%s = ns.%s or {}" % (args.table, args.table))
    out.append("ns.%s.%s = {" % (args.table, name))
    out.append("    skillLine = %d, contentLevel = %d," % (line, args.content_level))
    out.append("    recipes = {")
    for recipe in sorted(recipes, key=lambda r: (r["skills"][1], r["spell"])):
        fields = []
        if recipe["makes"]:
            fields.append("makes = %d, made = %s" % (recipe["makes"], lua_list(recipe["made"])))
        fields.append("skills = %s" % lua_list(recipe["skills"]))
        reagents = ", ".join("{ %d, %d }" % (item, count) for item, count in recipe["reagents"])
        fields.append("reagents = { %s }" % reagents if reagents else "reagents = {}")
        fields.append('learn = "%s"' % recipe["learn"])
        if recipe["learn"] == "item":  # (a recipe known from the start may still have an item)
            fields.append("teach = %d" % recipe["teach"])
            if recipe["bind"]:
                fields.append('bind = "%s"' % recipe["bind"])
        if recipe["forever"]:
            fields.append('forever = "%s"' % recipe["forever"])
        out.append("        [%d] = { %s }," % (recipe["spell"], ", ".join(fields)))
    out.append("    },")
    out.append("    items = {")
    for item in sorted(items):
        row, source = items[item]
        if row is None:
            # Neither client has an ItemSparse row: no price or level known.
            out.append("        [%d] = { unknown = true }," % item)
            continue
        fields = ["sell = %d" % row.get("SellPrice", 0), "buy = %d" % row.get("BuyPrice", 0),
                  "buyCount = %d" % max(1, row.get("VendorStackCount", 1)),
                  "ilvl = %d" % row.get("ItemLevel", 0), "reqLevel = %d" % row.get("RequiredLevel", 0),
                  "quality = %d" % row.get("OverallQualityID", 0)]
        # The item class (Item.ClassID), for what disenchants: 2 weapon, 4 armour.
        item_class = (beta.classes.get(item) if source == "client" else era.classes.get(item))
        if item_class is not None:
            fields.append("class = %d" % item_class)
        bind = bind_of(row.get("Bonding", 0))
        if bind:
            fields.append('bind = "%s"' % bind)
        if item in VENDOR:
            fields.append("vendor = true")
        note = "  -- Classic Era's row: not in Forever's ItemSparse" if source == "era" else ""
        out.append("        [%d] = { %s },%s" % (item, ", ".join(fields), note))
    out.append("    },")
    out.append("}")
    text = "\n".join(out) + "\n"
    text.encode("ascii")  # the addon's rule: ASCII only
    path = os.path.join(args.out_dir, "%s.lua" % name)
    os.makedirs(args.out_dir, exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as handle:
        handle.write(text)
    return path, len(items)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--content-level", type=int, default=20)
    parser.add_argument("--margin", type=int, default=5)
    parser.add_argument("--only", action="append", help="a profession (repeatable); default all")
    parser.add_argument("--dry-run", action="store_true", help="report only, write no Lua")
    parser.add_argument("--out", default=DEFAULT_OUT,
                        help="the directory to write, relative to the addon (default %s)" % DEFAULT_OUT)
    parser.add_argument("--table", default=DEFAULT_TABLE,
                        help="the ns table the files fill (default %s)" % DEFAULT_TABLE)
    args = parser.parse_args()
    if not args.table.isidentifier():
        parser.error("--table must be a Lua identifier")
    args.out_dir = args.out if os.path.isabs(args.out) else os.path.join(ADDON, args.out)

    beta, era, recipes, ceiling, ilvl_limit, sod = extract(args)
    today = datetime.date.today().isoformat()
    reagents = {}
    for recipe in recipes.values():
        for item, _ in recipe["reagents"]:
            row, source = item_row(item, beta, era)
            if row:
                reagents[item] = {"name": row["Display_lang"], "ilvl": row["ItemLevel"], "buy": row["BuyPrice"],
                                  "sell": row["SellPrice"], "quality": row["OverallQualityID"],
                                  "text": row["Description_lang"], "from": source}
    cache_name = "extract.json" if args.table == DEFAULT_TABLE else "extract.%s.json" % args.table
    with open(os.path.join(CACHE, cache_name), "w") as handle:
        json.dump({"build": beta.build, "contentLevel": args.content_level, "margin": args.margin,
                   "ceiling": ceiling, "ilvlLimit": ilvl_limit, "vendor": sorted(VENDOR),
                   "items": reagents, "recipes": recipes}, handle)

    print("build %s (Classic Era %s), contentLevel %d, margin %d: training ceiling %d, reagent ilvl <= %d" %
          (beta.build, era.build if era else "-", args.content_level, args.margin, ceiling, ilvl_limit))
    print("Season of Discovery categories: %s" % ", ".join(str(c) for c in sorted(sod)))
    wanted = {name.lower().replace(" ", "") for name in (args.only or [])}
    for name, line in PROFESSIONS:
        if wanted and name.lower() not in wanted:
            continue
        mine = [r for r in recipes.values() if r["profession"] == name]
        kept = [r for r in mine if r["drop"] is None]
        drops = {}
        for recipe in mine:
            if recipe["drop"]:
                drops[recipe["drop"]] = drops.get(recipe["drop"], 0) + 1
        sources = {}
        for recipe in kept:
            sources[recipe["learn"]] = sources.get(recipe["learn"], 0) + 1
        orange, yellow, grey = reach(kept, ceiling)
        print()
        print("%s (%d): %d in the client, %d in scope (%s); dropped: %s" % (
            name, line, len(mine), len(kept),
            ", ".join("%s %d" % (k, v) for k, v in sorted(sources.items())),
            ", ".join("%s %d" % (k, v) for k, v in sorted(drops.items())) or "none"))
        print("  reach: %d with orange recipes, %d with orange or yellow, %d before all are grey" %
              (orange, yellow, grey))
        missing = {}
        for recipe in mine:
            for item in recipe.get("missing", ()):
                missing[item] = missing.get(item, 0) + 1
        top = sorted(missing.items(), key=lambda kv: -kv[1])[:12]
        if top:
            print("  materials dropping most: " + ", ".join(
                "%s (%d, ilvl %d) x%d" % (beta.item_name(i), i, beta.items.get(i, {}).get("ItemLevel", 0), n)
                for i, n in top))
        if not args.dry_run:
            path, n_items = write_lua(name, line, kept, beta, era, beta.build, args, today)
            print("  wrote %s: %d recipes, %d items, %d bytes" % (
                os.path.relpath(path, ADDON), len(kept), n_items, os.path.getsize(path)))


if __name__ == "__main__":
    main()
