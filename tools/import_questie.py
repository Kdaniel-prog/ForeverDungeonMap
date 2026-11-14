"""Import quest start / turn-in locations and level requirements from QuestieDB
(GPLv3, https://github.com/Questie/QuestieDB) into
ForeverDungeonMap/Data/QuestInfo.lua.

Usage:
    python -I tools/import_questie.py <luaparser-lib-dir> <questie_src-dir> \
        ForeverDungeonMap/Data/Generated.lua ForeverDungeonMap/Data/QuestInfo.lua

<questie_src-dir> is a flat directory containing these files downloaded from
QuestieDB master (https://raw.githubusercontent.com/Questie/QuestieDB/master/):
    data/Forever/{foreverQuestDB,foreverNpcDB,foreverObjectDB,foreverItemDB}.lua
    support/Forever/Zones/{areaIdToUiMapId,dungeons,subZoneToParentZone}.lua

The quest IDs covered are every `id = N` and every ID inside `pre = { ... }` in
ns.QUESTS of Generated.lua. The source files are treated as data only: the
long-string table literals are read by a small purpose-built tokenizer (they are
never executed). luaparser is only used to check that the output parses.
"""
import os
import re
import sys

LUAPARSER_DIR, SRC, GENERATED, OUT = sys.argv[1:5]


# --------------------------------------------------------------------------
# Minimal Lua table-literal reader (data only: tables, strings, numbers,
# nil/true/false, comments). Arrays become dicts keyed 1..n like Lua.
# --------------------------------------------------------------------------
TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?))
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f",
           "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unescape(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = body[i + 1]
        if n.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1:])
            out.append(chr(int(m.group(0))))
            i += 1 + len(m.group(0))
        else:
            out.append(ESCAPES.get(n, n))
            i += 2
    return "".join(out)


def tokenize(text):
    pos, toks = 0, []
    for m in TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError("unexpected input at %d: %r" % (pos, text[pos:pos + 40]))
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "eq"):
            continue
        val = m.group(kind)
        if kind == "num":
            val = int(val, 0) if re.fullmatch(r"-?(0[xX][0-9a-fA-F]+|\d+)", val) else float(val)
        elif kind == "str":
            val = unescape(val[1:-1])
        toks.append((kind, val))
    if pos != len(text):
        raise ValueError("unexpected input at %d: %r" % (pos, text[pos:pos + 40]))
    return toks


class Reader:
    def __init__(self, text):
        self.toks = tokenize(text)
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, val=None):
        tok = self.toks[self.i]
        if val is not None and tok[1] != val:
            raise ValueError("expected %r got %r at token %d" % (val, tok, self.i))
        self.i += 1
        return tok

    def value(self):
        kind, val = self.take()
        if kind in ("num", "str"):
            return val
        if kind == "name":
            if val in ("nil", "true", "false"):
                return {"nil": None, "true": True, "false": False}[val]
            raise ValueError("unsupported expression %r" % val)
        if val == "{":
            return self.table()
        raise ValueError("unexpected token %r" % (val,))

    def table(self):
        t, n = {}, 0
        while self.peek()[1] != "}":
            kind, val = self.peek()
            if val == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
                t[key] = self.value()
            elif kind == "name" and self.toks[self.i + 1][1] == "=":
                self.take()
                self.take("=")
                t[val] = self.value()
            else:
                n += 1
                v = self.value()
                if v is not None:
                    t[n] = v
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return t


def long_strings(path):
    """All `name = [[return {...}]]` long-string payloads of a file, by name."""
    text = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"([\w.]+)\s*=\s*\[(=*)\[", text):
        end = text.index("]" + m.group(2) + "]", m.end())
        out[m.group(1)] = text[m.end():end]
    return out


def parse_return_table(payload):
    payload = payload.strip()
    if not payload.startswith("return"):
        raise ValueError("payload does not start with return")
    r = Reader(payload[len("return"):])
    r.take("{")
    return r.table()


def load_db(fname, var):
    path = os.path.join(SRC, fname)
    return parse_return_table(long_strings(path)[var])


def arr(t):
    """Lua array-ish dict -> Python list (ignoring holes)."""
    if not t:
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------
def quest_ids_from_generated(path):
    text = open(path, encoding="utf-8").read()
    # Blank out string literals so text inside names/objectives can't match.
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    start = text.index("ns.QUESTS = {")
    end = re.compile(r"^}", re.M).search(text, start).start()
    block = text[start:end]
    ids = set(int(x) for x in re.findall(r"\bid\s*=\s*(\d+)", block))
    shown = set(ids)
    for m in re.finditer(r"\bpre\s*=\s*\{([^}]*)\}", block):
        ids.update(int(x) for x in re.findall(r"\d+", m.group(1)))
    return ids, shown


QK = {"name": 1, "startedBy": 2, "finishedBy": 3, "requiredLevel": 4, "questLevel": 5,
      "zoneOrSort": 17}
NK = {"name": 1, "spawns": 7, "zoneID": 9}
OK = {"name": 1, "spawns": 4, "zoneID": 5}
IK = {"name": 1, "npcDrops": 2, "objectDrops": 3, "itemDrops": 4}


def check_keys(fname, var, expected):
    text = open(os.path.join(SRC, fname), encoding="utf-8").read()
    m = re.search(var + r"\s*=\s*\{(.*?)\n\}", text, re.S)
    found = dict((k, int(v)) for k, v in re.findall(r"\['(\w+)'\]\s*=\s*(\d+)", m.group(1)))
    for k, v in expected.items():
        if found.get(k) != v:
            raise SystemExit("%s: key %s is %r, expected %d - update the script" % (fname, k, found.get(k), v))


def main():
    sys.path.insert(0, LUAPARSER_DIR)

    check_keys("foreverQuestDB.lua", "QuestieDB.questKeys", QK)
    check_keys("foreverNpcDB.lua", "QuestieDB.npcKeys", NK)
    check_keys("foreverObjectDB.lua", "QuestieDB.objectKeys", OK)
    check_keys("foreverItemDB.lua", "QuestieDB.itemKeys", IK)

    quests = load_db("foreverQuestDB.lua", "QuestieDB.questData")
    npcs = load_db("foreverNpcDB.lua", "QuestieDB.npcData")
    objects = load_db("foreverObjectDB.lua", "QuestieDB.objectData")
    items = load_db("foreverItemDB.lua", "QuestieDB.itemData")

    # Zones: areaID -> uiMapID (main table only: the override table maps dungeon
    # areas to dungeon floor maps / continents, which we do not want).
    zl = long_strings(os.path.join(SRC, "areaIdToUiMapId.lua"))
    area_to_map = parse_return_table(zl["ZoneDB.private.areaIdToUiMapId"])
    area_name = {}
    for m in re.finditer(r"^\s*\[(\d+)\]\s*=\s*\d+,\s*--\s*(.+?)\s*$",
                         zl["ZoneDB.private.areaIdToUiMapId"], re.M):
        names = m.group(2).split(" -> ")
        area_name[int(m.group(1))] = names[0]
    sl = long_strings(os.path.join(SRC, "subZoneToParentZone.lua"))
    parent = parse_return_table(sl["ZoneDB.private.subZoneToParentZone"])
    parent.update(parse_return_table(sl["ZoneDB.private.subZoneToParentZoneOverride"]))

    dungeon_name = {}
    dtext = open(os.path.join(SRC, "dungeons.lua"), encoding="utf-8").read()
    for m in re.finditer(r'^\s*\[(\d+)\]\s*=\s*\{"((?:\\.|[^"\\])*)",(nil|\{[\d,\s]*\}),', dtext, re.M):
        name = unescape(m.group(2))
        dungeon_name[int(m.group(1))] = name
        if m.group(3) != "nil":
            for alt in re.findall(r"\d+", m.group(3)):
                dungeon_name.setdefault(int(alt), name)

    def dungeon_of(area):
        seen = set()
        while area is not None and area not in seen:
            if area in dungeon_name:
                return dungeon_name[area]
            seen.add(area)
            area = parent.get(area)
        return None

    def place_of(spawns, zone_hint):
        """spawns {[area]={{x,y},...}} -> dict with map/x/y or inside, or None."""
        if not spawns:
            return None
        zones = sorted(spawns, key=lambda z: (z != zone_hint, -len(arr(spawns[z])), z))
        # Prefer a zone with real coordinates; fall back to the first zone.
        for z in zones:
            pts = [p for p in arr(spawns[z]) if isinstance(p, dict) and 1 in p and 2 in p]
            dname = dungeon_of(z)
            if dname:
                return {"inside": dname}
            real = [p for p in pts if not (p[1] == -1 and p[2] == -1)]
            if not real:
                return {"inside": area_name.get(z, "an instance")}
            ui, a, seen = None, z, set()
            while a is not None and ui is None and a not in seen:
                seen.add(a)
                ui = area_to_map.get(a)
                a = parent.get(a)
            if ui:
                return {"map": ui, "x": real[0][1], "y": real[0][2]}
        return None

    def npc_place(nid):
        n = npcs.get(nid)
        if not n:
            return None, None
        return n.get(NK["name"]), place_of(n.get(NK["spawns"]), n.get(NK["zoneID"]))

    def obj_place(oid):
        o = objects.get(oid)
        if not o:
            return None, None
        return o.get(OK["name"]), place_of(o.get(OK["spawns"]), o.get(OK["zoneID"]))

    def pick(ids, fn, kind):
        best = None
        for i in ids:
            name, place = fn(i)
            if name is None:
                continue
            entry = {"kind": kind, "name": name}
            if place:
                entry.update(place)
                return entry
            best = best or entry
        return best

    def item_entry(iid):
        it = items.get(iid)
        if not it:
            return None
        entry = {"kind": "item", "name": it.get(IK["name"])}
        sources = [(n, p) for n, p in (npc_place(i) for i in arr(it.get(IK["npcDrops"]))) if n]
        sources += [(n, p) for n, p in (obj_place(i) for i in arr(it.get(IK["objectDrops"]))) if n]
        if not sources:
            return entry
        insides = set(p["inside"] for n, p in sources if p and "inside" in p)
        names = sorted(set(n for n, p in sources))
        if len(insides) == 1 and all(p and "inside" in p for n, p in sources):
            entry["inside"] = insides.pop()
        elif len(names) == 1:
            p = next((p for n, p in sources if p), None)
            if p:
                entry.update(p)
        if len(names) == 1 and names[0] != entry["name"]:
            entry["dropBy"] = names[0]
        return entry

    def side(by, with_items):
        if not by:
            return None
        e = pick(arr(by.get(1)), npc_place, "npc")
        if e is None:
            e = pick(arr(by.get(2)), obj_place, "object")
        if e is None and with_items:
            for iid in arr(by.get(3)):
                e = item_entry(iid)
                if e:
                    break
        return e

    wanted, shown = quest_ids_from_generated(GENERATED)
    info, missing, fallback = {}, [], []
    for qid in sorted(wanted):
        q = quests.get(qid)
        if not q:
            missing.append(qid)
            continue
        rec = {}
        if q.get(QK["requiredLevel"]):
            rec["req"] = q[QK["requiredLevel"]]
        if q.get(QK["questLevel"]) and q[QK["questLevel"]] > 0:
            rec["lvl"] = q[QK["questLevel"]]
        s = side(q.get(QK["startedBy"]), True)
        f = side(q.get(QK["finishedBy"]), False)
        # Starters/enders without spawn data (event / script spawns, e.g. bosses
        # summoned during an encounter): if the quest is sorted under a dungeon
        # area, assume they are inside it. Item starters only qualify when they
        # have a known drop source.
        zone = q.get(QK["zoneOrSort"])
        dname = dungeon_of(zone) if isinstance(zone, int) and zone > 0 else None
        for e in (s, f):
            if dname and e and "map" not in e and "inside" not in e and (
                    e["kind"] != "item" or "dropBy" in e):
                e["inside"] = dname
                fallback.append(qid)
        if s:
            rec["start"] = s
        if f:
            rec["finish"] = f
        info[qid] = rec

    write(info)
    verify(info)

    nostart = [q for q in info if "start" not in info[q]]
    nofinish = [q for q in info if "finish" not in info[q]]
    noloc = [q for q in info for k in ("start", "finish")
             if k in info[q] and not any(x in info[q][k] for x in ("map", "inside"))]
    print("quest IDs wanted: %d (shown %d, prerequisite-only %d)" % (len(wanted), len(shown), len(wanted - shown)))
    print("covered: %d, missing from QuestieDB: %d" % (len(info), len(missing)))
    print("missing:", " ".join(map(str, missing)))
    print("  of which shown in the addon:", " ".join(str(q) for q in missing if q in shown))
    print("covered without start:", " ".join(map(str, sorted(nostart))))
    print("covered without finish:", " ".join(map(str, sorted(nofinish))))
    print("location inferred from quest zoneOrSort (no spawn data):", " ".join(map(str, sorted(set(fallback)))))
    print("start/finish without location:", " ".join(map(str, sorted(set(noloc)))))


def lua_str(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif ord(c) < 32 or ord(c) == 127:
            out.append("\\%03d" % ord(c))
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def fmt_side(e):
    parts = ['kind = "%s"' % e["kind"], "name = " + lua_str(e["name"] or "?")]
    if "map" in e:
        parts.append("map = %d, x = %.1f, y = %.1f" % (e["map"], e["x"], e["y"]))
    if "inside" in e:
        parts.append("inside = " + lua_str(e["inside"]))
    if "dropBy" in e:
        parts.append("dropBy = " + lua_str(e["dropBy"]))
    return "{ " + ", ".join(parts) + " }"


def write(info):
    lines = [
        "-- GENERATED by tools/import_questie.py from QuestieDB (GPLv3, https://github.com/Questie/QuestieDB). Do not edit.",
        "local _, ns = ...",
        "ns.QUEST_INFO = {",
    ]
    for qid in sorted(info):
        r = info[qid]
        parts = []
        for k in ("req", "lvl"):
            if k in r:
                parts.append("%s = %d" % (k, r[k]))
        for k in ("start", "finish"):
            if k in r:
                parts.append("%s = %s" % (k, fmt_side(r[k])))
        key = "[%d]" % qid
        lines.append("    %-7s = { %s }," % (key, ", ".join(parts)))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def verify(info):
    from luaparser import ast, astnodes
    tree = ast.parse(open(OUT, encoding="utf-8").read())
    tbl = tree.body.body[-1].values[0]
    assert isinstance(tbl, astnodes.Table) and len(tbl.fields) == len(info), "output parse check failed"
    print("output parses with luaparser: %d entries" % len(tbl.fields))


if __name__ == "__main__":
    main()
