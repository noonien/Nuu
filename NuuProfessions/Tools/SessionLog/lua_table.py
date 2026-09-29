"""Parser for the SavedVariables subset the WoW client writes.

The client writes a fixed, small shape: `NAME = value` at the top level, tables
with `["key"] =` or `[1] =` entries, strings in double quotes with backslash
escapes, numbers, booleans and nil. Nothing else appears, so this is a
tokenizer and a recursive descent parser rather than a Lua interpreter: the
tools must never execute a file the game wrote.
"""

import re

_TOKEN = re.compile(
    r"""
    (?P<space>\s+)
  | (?P<comment>--\[\[.*?\]\]|--[^\n]*)
  | (?P<string>"(?:[^"\\]|\\.)*")
  | (?P<number>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[\{\}\[\]=,;])
    """,
    re.VERBOSE | re.DOTALL,
)

_ESCAPES = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class LuaParseError(ValueError):
    pass


def _tokenize(text):
    pos, end, out = 0, len(text), []
    while pos < end:
        match = _TOKEN.match(text, pos)
        if not match:
            line = text.count("\n", 0, pos) + 1
            raise LuaParseError("unexpected input at line %d: %r" % (line, text[pos:pos + 40]))
        pos = match.end()
        kind = match.lastgroup
        if kind not in ("space", "comment"):
            out.append((kind, match.group()))
    return out


def _unescape(raw):
    body, out, i = raw[1:-1], [], 0
    while i < len(body):
        char = body[i]
        if char != "\\":
            out.append(char)
            i += 1
            continue
        i += 1
        if i >= len(body):
            break
        nxt = body[i]
        if nxt.isdigit():
            digits = ""
            while i < len(body) and body[i].isdigit() and len(digits) < 3:
                digits += body[i]
                i += 1
            out.append(chr(int(digits) % 256))
            continue
        out.append(_ESCAPES.get(nxt, nxt))
        i += 1
    return "".join(out)


def _number(raw):
    if raw[:2].lower() in ("0x", "-0"):
        try:
            return int(raw, 16) if "x" in raw.lower() else int(raw)
        except ValueError:
            pass
    try:
        return int(raw)
    except ValueError:
        return float(raw)


class _Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        kind, text = self.peek()
        if kind is None:
            raise LuaParseError("unexpected end of file")
        if value is not None and text != value:
            raise LuaParseError("expected %r, found %r" % (value, text))
        self.i += 1
        return kind, text

    def value(self):
        kind, text = self.peek()
        if text == "{":
            return self.table()
        self.take()
        if kind == "string":
            return _unescape(text)
        if kind == "number":
            return _number(text)
        if text == "true":
            return True
        if text == "false":
            return False
        if text == "nil":
            return None
        if kind == "name":
            # An unquoted name reaching here is something we have not seen the
            # client write; keep it as text rather than guessing.
            return {"__lua": text}
        raise LuaParseError("not a value: %r" % (text,))

    def table(self):
        self.take("{")
        out, index = {}, 1
        while True:
            kind, text = self.peek()
            if text == "}":
                self.take()
                break
            if text == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                out[key] = self.value()
            elif kind == "name" and self.tokens[self.i + 1:self.i + 2] == [("punct", "=")]:
                self.take()
                self.take("=")
                out[text] = self.value()
            else:
                out[index] = self.value()
                index += 1
            kind, text = self.peek()
            if text in (",", ";"):
                self.take()
        return out


def parse_saved_variables(text):
    """Return {global name: value} for every assignment in a SavedVariables file."""
    parser = _Parser(_tokenize(text))
    out = {}
    while parser.peek()[0] is not None:
        kind, name = parser.take()
        if kind != "name":
            raise LuaParseError("expected a global name, found %r" % (name,))
        parser.take("=")
        out[name] = parser.value()
        if parser.peek()[1] in (",", ";"):
            parser.take()
    return out


def to_json_safe(value):
    """JSON keeps no integer keys, so a table becomes a list when it is a clean
    1..n sequence and an object with stringified keys otherwise."""
    if isinstance(value, dict):
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_json_safe(value[k]) for k in sorted(keys)]
        return {str(k): to_json_safe(v) for k, v in value.items()}
    return value
