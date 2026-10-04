"""Print NuuExperiments results from the client's saved variables.

    python3 NuuExperiments/Tools/Results.py            every result, each account
    python3 NuuExperiments/Tools/Results.py client     one experiment's entry

The game writes the file on /reload or logout:
WTF/Account/<account>/SavedVariables/NuuExperiments.lua
"""
import sys
from pathlib import Path

CLIENT = Path(__file__).resolve().parents[4]


def entry(text, key):
    """The `["key"] = { ... },` block of a saved-variables file, by brace counting."""
    start = text.find('["%s"] = {' % key)
    if start < 0:
        return None
    depth, i, quoted = 0, text.index("{", start), False
    while i < len(text):
        c = text[i]
        if quoted:
            if c == "\\":
                i += 1
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return None


def main():
    files = sorted(CLIENT.glob("WTF/Account/*/SavedVariables/NuuExperiments.lua"))
    if not files:
        sys.exit("no NuuExperiments.lua under %s/WTF/Account/*/SavedVariables (log in, then /reload)" % CLIENT)
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        print("== %s" % path.relative_to(CLIENT))
        if len(sys.argv) < 2:
            print(text)
            continue
        for key in sys.argv[1:]:
            print(entry(text, key) or "no results for %s" % key)


if __name__ == "__main__":
    main()
