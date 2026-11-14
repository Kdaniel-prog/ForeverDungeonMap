"""Import boss, loot and quest data from DungeonMaster (GPLv3, by MalkDev)
into ForeverDungeonMap/Data/Generated.lua.

Usage:
    python -I tools/import_dungeonmaster.py <luaparser-lib-dir> <DungeonMaster-dir> <out-file>

Reads Data.lua (ns.data quests, ns.dungeons) and Curated.lua (ns.curated:
hand-curated WoW Forever quests; ns.curatedDungeons: boss order and boss/loot
corrections per dungeon). Curated data takes priority over Data.lua.
"""
import sys

sys.path.insert(0, sys.argv[1])
from luaparser import ast, astnodes  # noqa: E402

DM_DIR, OUT = sys.argv[2], sys.argv[3]


def to_py(node):
    """Lua table-constructor AST -> Python value (dict / list / scalar)."""
    if isinstance(node, astnodes.Table):
        items, keyed = [], {}
        for f in node.fields:
            v = to_py(f.value)
            if f.key is None or (isinstance(f.key, astnodes.Number) and not f.between_brackets):
                items.append(v)
            else:
                k = f.key
                if isinstance(k, astnodes.Name):
                    keyed[k.id] = v
                else:
                    keyed[to_py(k)] = v
        if keyed and items:
            for i, v in enumerate(items, 1):
                keyed[i] = v
            return keyed
        return keyed if keyed else items
    if isinstance(node, astnodes.Number):
        return node.n
    if isinstance(node, astnodes.String):
        s = node.s
        return s.decode("utf-8") if isinstance(s, (bytes, bytearray)) else s
    if isinstance(node, astnodes.TrueExpr):
        return True
    if isinstance(node, astnodes.FalseExpr):
        return False
    if isinstance(node, astnodes.Nil):
        return None
    if isinstance(node, astnodes.UMinusOp):
        return -to_py(node.operand)
    raise TypeError(f"unsupported node {type(node).__name__}")


def read_tables(path, wanted):
    src = open(path, encoding="utf-8").read()
    tree = ast.parse(src)
    found = {}
    for stmt in tree.body.body:
        if not isinstance(stmt, astnodes.Assign):
            continue
        for target, value in zip(stmt.targets, stmt.values):
            if isinstance(target, astnodes.Index) and isinstance(target.idx, astnodes.Name):
                name = target.idx.id
                if name in wanted and isinstance(value, astnodes.Table):
                    found[name] = to_py(value)
    return found


data = read_tables(f"{DM_DIR}/Data.lua", {"data", "dungeons"})
_cur = read_tables(f"{DM_DIR}/Curated.lua", {"curated", "curatedDungeons"})
curated = _cur["curated"]                      # quests (by quest ID)
curated_dungeons = _cur.get("curatedDungeons", {})  # boss order / boss fixes (by instance ID)
quests_all, dungeons = data["data"], data["dungeons"]

# ---------------------------------------------------------------- bosses
BOSS_FIELDS = ("npcID", "display", "encounter", "rare", "loot")


def merged_bosses(inst):
    d = dungeons.get(inst, {})
    base = {b["name"]: dict(b) for b in d.get("bosses", []) if isinstance(b, dict)}
    fix = curated_dungeons.get(inst, {}) if isinstance(curated_dungeons.get(inst), dict) else {}
    fixb = fix.get("bosses", {}) or {}
    order = fix.get("order") or [b["name"] for b in d.get("bosses", []) if isinstance(b, dict)]
    names = list(order) + [n for n in fixb if n not in order]
    out = []
    for n in names:
        b = dict(base.get(n, {"name": n}))
        b.update(fixb.get(n, {}))
        b["name"] = n
        out.append(b)
    return out


# ---------------------------------------------------------------- quests
QUEST_FIELDS = ("name", "level", "faction", "classes", "prev", "chain", "npc", "npcID",
                "map", "x", "y", "objective", "rewards", "choices", "inside", "drop", "forever")


def quest(qid):
    q = dict(quests_all.get(qid, {}))
    c = curated.get(qid)
    if isinstance(c, dict) and "order" not in c and "bosses" not in c:
        q.update(c)
    return q


all_quest_ids = set(quests_all) | {k for k, v in curated.items()
                                   if isinstance(v, dict) and ("instance" in v or "name" in v)
                                   and k not in dungeons}


def pre_chain(q, depth=0):
    """Prerequisite quests, oldest first."""
    if q.get("chain"):
        return list(q["chain"])
    out, cur, seen = [], q, set()
    while cur.get("prev") and cur["prev"] not in seen and len(out) < 12:
        p = cur["prev"]
        seen.add(p)
        out.insert(0, p)
        cur = quest(p)
    return out


# ---------------------------------------------------------------- write Lua
def lua(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if isinstance(k, str) and k.isidentifier() else f"[{lua(k)}]"
            parts.append(f"{key} = {lua(x)}")
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(type(v))


lines = [
    "-- GENERATED by tools/import_dungeonmaster.py - do not edit by hand.",
    "-- Source: DungeonMaster by MalkDev (GPLv3), Data.lua + Curated.lua. See THIRD_PARTY.md.",
    "",
    "local _, ns = ...",
    "",
    "ns.BOSSES = {",
]
for inst in sorted(dungeons):
    bs = []
    for b in merged_bosses(inst):
        bs.append({k: b[k] for k in ("name",) + BOSS_FIELDS if k in b})
    lines.append(f"    [{inst}] = {{ -- {dungeons[inst].get('name')}")
    for b in bs:
        lines.append(f"        {lua(b)},")
    lines.append("    },")
lines += ["}", "", "ns.WINGS = {"]
for inst in sorted(dungeons):
    w = dungeons[inst].get("wings")
    if w:
        wings = [{"name": x.get("name"), "min": x.get("min"), "max": x.get("max"), "bosses": x.get("bosses", [])}
                 for x in w]
        lines.append(f"    [{inst}] = {lua(wings)},")
lines += ["}", "", "ns.ICONS = {"]
for inst in sorted(dungeons):
    if dungeons[inst].get("icon"):
        lines.append(f"    [{inst}] = {lua(dungeons[inst]['icon'])},")
lines += ["}", "", "ns.QUESTS = {"]

names_needed = set()
per_inst = {}
for qid in sorted(all_quest_ids):
    q = quest(qid)
    inst = q.get("instance")
    if not inst or q.get("hide"):
        continue
    rec = {"id": qid}
    rec.update({k: q[k] for k in QUEST_FIELDS if k in q and k != "chain" and k != "prev"})
    pre = pre_chain(q)
    if pre:
        rec["pre"] = pre
        names_needed.update(pre)
    per_inst.setdefault(inst, []).append(rec)

for inst in sorted(per_inst):
    qs = sorted(per_inst[inst], key=lambda r: (r.get("level") or 0, r["name"]))
    lines.append(f"    [{inst}] = {{")
    for r in qs:
        lines.append(f"        {lua(r)},")
    lines.append("    },")
lines += ["}", "", "-- names of prerequisite quests outside the dungeon lists", "ns.QUEST_NAMES = {"]
for qid in sorted(names_needed):
    n = quest(qid).get("name")
    if n:
        lines.append(f"    [{qid}] = {lua(n)},")
lines += ["}", ""]

open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
nb = sum(len(merged_bosses(i)) for i in dungeons)
nq = sum(len(v) for v in per_inst.values())
print(f"dungeons={len(dungeons)} bosses={nb} quests={nq} prereq-names={len(names_needed)} -> {OUT}")
