"""Read and write plain Lua table literals (shared by the data generators in tools/).

parse_table reads a `{ ... }` literal (strings, numbers, booleans, nil, nested tables, `--` comments)
into Python dicts / lists without running anything; to_lua writes Python values back as Lua.
"""
import re

TOKEN = re.compile(r"""
    (?P<space>\s+|--[^\n]*)
  | (?P<string>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
  | (?P<number>-?\d+(?:\.\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<symbol>[{}\[\]=,;])
""", re.X | re.S)
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
KEYWORDS = {"true": True, "false": False, "nil": None}


def unquote(text):
    return re.sub(r"\\(.)", lambda match: ESCAPES.get(match.group(1), match.group(1)), text[1:-1])


def tokens(text, start):
    """(kind, value, end) of every token from `start` on."""
    position = start
    while position < len(text):
        match = TOKEN.match(text, position)
        if not match:
            raise ValueError("unexpected Lua at %d: %r" % (position, text[position:position + 40]))
        position = match.end()
        if match.lastgroup != "space":
            yield match.lastgroup, match.group(), position


class Reader:
    def __init__(self, text, start):
        self.stream = tokens(text, start)
        self.end = start
        self.ahead = None

    def peek(self):
        if self.ahead is None:
            self.ahead = next(self.stream)
        return self.ahead

    def take(self):
        token = self.peek()
        self.ahead = None
        self.end = token[2]
        return token

    def value(self):
        kind, text, _ = self.take()
        if kind == "string":
            return unquote(text)
        if kind == "number":
            return float(text) if "." in text else int(text)
        if kind == "name" and text in KEYWORDS:
            return KEYWORDS[text]
        if text == "{":
            return self.table()
        raise ValueError("unexpected Lua token %r" % text)

    def key(self):
        """Key of a `key = value` / `[key] = value` field, or None for a list item."""
        kind, text, _ = self.peek()
        if text == "[":
            self.take()
            key = self.value()
            self.take()
            self.take()
            return key
        if kind == "name" and text not in KEYWORDS:
            self.take()
            self.take()
            return text
        return None

    def table(self):
        fields, items = {}, []
        while self.peek()[1] != "}":
            key = self.key()
            value = self.value()
            if key is None:
                items.append(value)
            else:
                fields[key] = value
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take()
        if items and not fields:
            return items
        for index, item in enumerate(items, 1):
            fields[index] = item
        return fields


def parse_table(text, start):
    """(value, end) of the table literal whose `{` is at or after `start`."""
    reader = Reader(text, text.index("{", start))
    return reader.value(), reader.end


def table_after(text, marker):
    """The table literal right after the first `marker` in text (e.g. "local QUESTS=")."""
    return parse_table(text, text.index(marker) + len(marker))[0]


def to_lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(round(value, 1)) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, list):
        return "{ " + ", ".join(to_lua(item) for item in value) + " }"
    if isinstance(value, dict):
        return "{ " + ", ".join("%s = %s" % (lua_key(key), to_lua(item)) for key, item in value.items()) + " }"
    raise TypeError(value)


def lua_key(key):
    """`name`, or `["any text"]` / `[12]` when the key is no plain Lua name."""
    if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) and key not in KEYWORDS:
        return key
    return "[%s]" % to_lua(key)
