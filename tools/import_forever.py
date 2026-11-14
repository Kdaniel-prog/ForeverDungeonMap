"""Build ForeverDungeonMap/Data/Forever.lua: data for the new WoW Forever dungeons
(instance IDs, level ranges, zones, entrances, candidate map art, bosses, boss
portraits/levels and the Forever-only quests).

Sources, in order of trust:
  * Blizzard client data of WoW Forever 1.60.1.70938 (DB2 tables Map, MapDifficulty,
    ContentTuning, DungeonEncounter, AreaTable, UiMapAssignment, UiMapXMapArt,
    WorldMapOverlay), as published by wago.tools:
        GET https://wago.tools/db2/<Table>/csv?build=1.60.1.70938
    plus retail UiMapAssignment (GET https://wago.tools/db2/UiMapAssignment/csv) for the
    world bounds of the retail maps whose art the client ships, and the client file
    listing (GET https://wago.tools/api/files?search=interface/worldmap/&version=1.60.1.70938).
  * DungeonMaster by MalkDev (GPLv3): Data.lua (ns.dungeons) and Curated.lua
    (ns.curated quests, ns.curatedDungeons bosses/entrances).
  * Azeroth Pilot Reloaded (APR), OFF by default: its .toc says "All Rights Reserved" while
    it ships a GPLv3 LICENSE, so release builds do not use it. With --with-apr <APR-dir> it adds
    Routes/Forever/** quest pickup / turn-in spots and boss NPC IDs from
    APR-Core/data/Dungeons/DungeonsForever.lua (every such value is marked src = "APR").
  * Questie (GPLv3): Database/Zones/data/dungeons.lua dungeon entrances.
  * Plain game facts (creature display IDs, boss levels, recommended level ranges) read
    from the public fan sites foreverchanges.pro and wowf.io dungeon pages, only where the
    sources above have nothing. Every such value is listed in the output's source comment.

Usage:
    python -I tools/import_forever.py <pylib> <wago-dir> <retail-dir> <worldmap-listing.json>
        <DungeonMaster-dir> <questie-dungeons.lua> <web-dir> <Generated.lua> <out Forever.lua>
        [--with-apr <APR-dir>] [--maps <forever_maps.json>]

--maps takes the output of tools/make_forever_maps.py: map floors (client minimap tiles or retail
world map tiles, by FileDataID / path) and boss spots on them; its floors come first.
<web-dir> holds the saved pages fc_<slug>.html (https://foreverchanges.pro/dungeons/<slug>),
wowfio_<slug>.html (https://wowf.io/en/dungeons/<slug>) and wowfio_index.html
(https://wowf.io/en/dungeons). All inputs are read as data; nothing is executed.
"""
import csv
import json
import math
import os
import re
import sys

_argv = sys.argv[1:]
APR_DIR = None
if "--with-apr" in _argv:  # opt-in only: APR's licence is unclear (see docstring)
    i = _argv.index("--with-apr")
    APR_DIR = _argv[i + 1]
    del _argv[i:i + 2]
MAPS_FILE = None
if "--maps" in _argv:
    i = _argv.index("--maps")
    MAPS_FILE = _argv[i + 1]
    del _argv[i:i + 2]
(PYLIB, WAGO, RETAIL, LISTING, DM_DIR, QUESTIE_DUNGEONS, WEB, GENERATED, OUT) = _argv[:9]
sys.path.insert(0, PYLIB)
from luaparser import ast, astnodes  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")


def rows(folder, table):
    with open(os.path.join(folder, table + ".csv"), encoding="utf-8") as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------ Lua table reader
def to_py(node):
    if isinstance(node, astnodes.Table):
        items, keyed = [], {}
        for f in node.fields:
            v = to_py(f.value)
            if f.key is None or (isinstance(f.key, astnodes.Number) and not f.between_brackets):
                items.append(v)
            else:
                keyed[f.key.id if isinstance(f.key, astnodes.Name) else to_py(f.key)] = v
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
    raise TypeError(type(node).__name__)


def read_tables(path, wanted):
    tree = ast.parse(open(path, encoding="utf-8").read())
    found = {}
    for stmt in tree.body.body:
        if isinstance(stmt, astnodes.Assign):
            for target, value in zip(stmt.targets, stmt.values):
                if isinstance(target, astnodes.Index) and isinstance(target.idx, astnodes.Name):
                    if target.idx.id in wanted and isinstance(value, astnodes.Table):
                        found[target.idx.id] = to_py(value)
    return found


# ------------------------------------------------------------------ client DB2
maps = {int(r["ID"]): r for r in rows(WAGO, "Map")}
encounters = rows(WAGO, "DungeonEncounter")
tuning = {int(r["ID"]): r for r in rows(WAGO, "ContentTuning")}
areas = {int(r["ID"]): r for r in rows(WAGO, "AreaTable")}
assign = {}  # uiMapID -> (minX, minY, maxX, maxY) world bounds (zone maps)
area_to_uimap = {}
for r in rows(WAGO, "UiMapAssignment"):
    if r["OrderIndex"] == "0":
        assign[int(r["UiMapID"])] = tuple(float(r[f"Region_{i}"]) for i in (0, 1, 3, 4))
        if int(r["AreaID"]):
            area_to_uimap.setdefault(int(r["AreaID"]), int(r["UiMapID"]))
art_to_uimap = {r["UiMapArtID"]: int(r["UiMapID"]) for r in rows(WAGO, "UiMapXMapArt")}
overlays = rows(WAGO, "WorldMapOverlay")
loadscreen = {int(r["ID"]): int(r["MainImageFileDataID"] or 0) or int(r["NarrowScreenFileDataID"] or 0)
              for r in rows(WAGO, "LoadingScreens")}

bosses_by_map = {}
for r in encounters:
    bosses_by_map.setdefault(int(r["MapID"]), []).append(r)

# Forever dungeons = party instances added for Forever (Map ID >= 2959) that have boss encounters
FOREVER = sorted(m for m, r in maps.items()
                 if m >= 2959 and r["InstanceType"] == "1" and m in bosses_by_map)

diff = {}
for r in rows(WAGO, "MapDifficulty"):
    if int(r["MapID"]) in FOREVER and r["DifficultyID"] == "1":
        diff[int(r["MapID"])] = r


def zone_of_area(area_id):
    """uiMapID of the zone an AreaTable row lies in (walks the parent chain)."""
    seen = 0
    while area_id and seen < 10:
        if area_id in area_to_uimap:
            return area_to_uimap[area_id]
        area_id = int(areas[area_id]["ParentAreaID"]) if area_id in areas else 0
        seen += 1
    return None


# Outdoor AreaTable row at each dungeon (client data; looked up by name, see report):
EXTERIOR_AREA = {
    2959: 17707,  # Old Dalaran Ruins          (Alterac Mountains)
    2970: 17853,  # Sunken Hollow              (Stranglethorn Vale)
    2974: 1216,   # Blackmaw Hold              (Azshara)
    2994: 2079,   # Alcaz Island               (Dustwallow Marsh)
    2998: 17732,  # Excavation Site: Wetlands  (Wetlands)
    2999: 153,    # Ruins of Lordaeron         (Tirisfal Glades)
    3001: 16985,  # The Shaper's Terrace       (Un'Goro Crater)
    3039: 17780,  # Krol'dok Stronghold        (Riverglades)
    3065: None,   # under Ironforge: no outdoor area row; zone from the entrance
}
# WoW Forever zones that are new and missing from area_to_uimap
EXTRA_AREA_UIMAP = {16591: 2548}  # Riverglades


def world_to_map(ui_map, wx, wy):
    """APR world coordinate {x = worldY, y = worldX} -> percent on a zone map."""
    b = assign.get(ui_map)
    if not b:
        return None
    min_x, min_y, max_x, max_y = b
    x = (max_y - wx) / (max_y - min_y) * 100
    y = (max_x - wy) / (max_x - min_x) * 100
    if not (0 <= x <= 100 and 0 <= y <= 100):
        return None
    return round(x, 1), round(y, 1)


# ------------------------------------------------------------------ map art (candidates)
listing = json.load(open(LISTING, encoding="utf-8"))
listed = {v.lower() for v in listing.values()}
retail_assign = {}
for r in rows(RETAIL, "UiMapAssignment"):
    retail_assign.setdefault(int(r["UiMapID"]), r)


def tile_set(folder, prefix):
    names = [f"interface/worldmap/{folder.lower()}/{prefix.lower()}{n}.blp" for n in range(1, 13)]
    return all(n in listed for n in names)


# Retail maps whose 4x3 art ships in the Forever client and shows the same place.
# The client has no UiMap for any Forever dungeon, so alignment is unverified.
# (Old Ironforge, retail UiMap 1361, is not the Hall of Thanes: its minimap shows another layout.)
ART_CANDIDATES = {
    2999: [("RuinsOfLordaeronScenario", "RuinsOfLordaeronScenario", "Lordaeron (overview)", 908, "overview")],
}

# Floors and boss spots from tools/make_forever_maps.py (optional)
map_art = json.load(open(MAPS_FILE, encoding="utf-8"))["dungeons"] if MAPS_FILE else {}

# ------------------------------------------------------------------ DungeonMaster
dm = read_tables(os.path.join(DM_DIR, "Data.lua"), {"dungeons"})["dungeons"]
cur = read_tables(os.path.join(DM_DIR, "Curated.lua"), {"curated", "curatedDungeons"})
dm_quests, dm_dungeons = cur["curated"], cur.get("curatedDungeons", {})

# ------------------------------------------------------------------ APR
apr_npc = {}  # instanceID -> ({npcID: name}, {encounterID: npcID})
apr_steps = []
if APR_DIR:
    src = open(os.path.join(APR_DIR, "APR-Core", "data", "Dungeons", "DungeonsForever.lua"), encoding="utf-8").read()
    for m in re.finditer(r"instanceID = (\d+),(.*?)(?=\n    [A-Z_0-9]+ = \{|\n\}\s*$)", src, re.S):
        inst, body = int(m.group(1)), m.group(2)
        enc = {int(a): int(b) for a, b in re.findall(r"\[(\d+)\] = (\d+),", body.split("encounterNames")[0])}
        names_block = body.split("npcNames", 1)[1] if "npcNames" in body else ""
        npcs = {int(a): b for a, b in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"', names_block)}
        apr_npc[inst] = (npcs, enc)

    STEP_RE = re.compile(r"\{([^{}]*(?:\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}[^{}]*)*)\}")
    for root, _, files in os.walk(os.path.join(APR_DIR, "Routes", "Forever")):
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            text = open(os.path.join(root, fn), encoding="utf-8").read()
            for m in STEP_RE.finditer(text):
                body = m.group(1)
                if "_index" not in body:
                    continue
                for kind in ("PickUp", "Done"):
                    km = re.search(kind + r"\s*=\s*\{([^}]*)\}", body)
                    if not km:
                        continue
                    c = re.search(r"ConvertMapCoordinate\((\d+),\s*([\d.]+),\s*([\d.]+)\)", body)
                    w = re.search(r"Coord\s*=\s*\{\s*x\s*=\s*(-?[\d.]+),\s*y\s*=\s*(-?[\d.]+)", body)
                    z = re.search(r"\bZone\s*=\s*(\d+)", body)
                    pos = None
                    if c:
                        pos = (int(c.group(1)), round(float(c.group(2)), 1), round(float(c.group(3)), 1))
                    elif w and z:
                        xy = world_to_map(int(z.group(1)), float(w.group(1)), float(w.group(2)))
                        if xy:
                            pos = (int(z.group(1)),) + xy
                    icons = [int(n) for n in re.findall(r"npcID\s*=\s*(\d+)", body)]
                    lvl = re.search(r"\bMinLevel\s*=\s*(\d+)", body)
                    for q in re.findall(r"\d+", km.group(1)):
                        apr_steps.append(dict(q=int(q), kind=kind, pos=pos, inside="InstanceQuest" in body,
                                              npcs=icons, minlevel=int(lvl.group(1)) if lvl else None, file=fn))

# ------------------------------------------------------------------ Questie entrances
questie_entr = {}
for m in re.finditer(r'\[(\d+)\] = \{"([^"]+)",[^,]*,(\d+),\{\{(\d+), ([\d.]+), ([\d.]+)\}', open(QUESTIE_DUNGEONS, encoding="utf-8").read()):
    questie_entr[int(m.group(1))] = (int(m.group(4)), float(m.group(5)), float(m.group(6)))


# ------------------------------------------------------------------ fan-site facts
def flight(path):
    if not os.path.exists(path):
        return ""
    s = open(path, encoding="utf-8").read()
    return "".join(json.loads(c) for c in re.findall(r'self\.__next_f\.push\(\[1,(".*?")\]\)</script>', s, re.S))


SLUGS = {  # instance -> (foreverchanges slug, wowf.io slug)
    2959: ("city-of-dalaran", "dalaran"), 2970: ("the-drowned-city", "drowned-city"),
    2974: ("blackmaw-hold", "blackmaw-hold"), 2994: ("alcaz-prison", "alcaz-prison"),
    2998: ("excavation-site", "excavation-site"), 2999: ("ruins-of-lordaeron", "ruins-of-lordaeron"),
    3001: ("shapers-terrace", "shapers-terrace"), 3039: ("kroldok-stronghold", "kroldok-stronghold"),
    3065: ("hall-of-thanes", "hall-of-thanes"),
}
dec = json.JSONDecoder()
web_boss = {}   # inst -> name -> dict(display, level, rare)
web_range = {}  # inst -> (min, max)
idx = flight(os.path.join(WEB, "wowfio_index.html"))
for inst, (fc, wf) in SLUGS.items():
    m = re.search(r'\{"id":"%s",[^{}]*?"level":\[(\d+),(\d+)\]' % re.escape(wf), idx)
    if m:
        web_range[inst] = (int(m.group(1)), int(m.group(2)))
    d = flight(os.path.join(WEB, f"fc_{fc}.html"))
    i = d.find('"bosses":[{"name"')
    if i >= 0:
        for b in dec.raw_decode(d[i + 9:])[0]:
            if b.get("kind") in ("boss", "rare"):
                web_boss.setdefault(inst, {})[b["name"]] = dict(display=b.get("display") or None, level=b.get("level"),
                                                              rare=b.get("kind") == "rare")
    d = flight(os.path.join(WEB, f"wowfio_{wf}.html"))
    i = d.find('{"d":{"id":')
    if i >= 0:
        for b in dec.raw_decode(d[i:])[0]["d"]["bosses"]:
            lv = b.get("levels")
            if lv:
                rec = web_boss.setdefault(inst, {}).setdefault(b["nameEn"], dict(display=None, level=None, rare=False))
                rec.setdefault("wlevels", lv)
                rec["wlevels"] = lv

# ------------------------------------------------------------------ Generated.lua (names the addon uses)
gen_bosses, gen_quests = {}, {}
section, inst = None, None
for line in open(GENERATED, encoding="utf-8"):
    if line.startswith("ns."):
        section = line.split()[0][3:]
        continue
    m = re.match(r"\s*\[(\d+)\] = \{", line)
    if m:
        inst = int(m.group(1))
        continue
    if section == "BOSSES":
        m = re.match(r'\s*\{ name = "((?:[^"\\]|\\.)*)"(.*)\},?$', line)
        if m and inst:
            rest = m.group(2)
            g = lambda k: (re.search(k + r" = (\d+)", rest) or [None, None])[1]  # noqa: E731
            gen_bosses.setdefault(inst, []).append(dict(name=m.group(1).replace('\\"', '"'), npcID=g("npcID"),
                                                        display=g("display"), rare="rare = true" in rest))
    elif section == "QUESTS":
        m = re.match(r"\s*\{ id = (\d+),", line)
        if m and int(m.group(1)) > 90000:
            gen_quests[int(m.group(1))] = inst

# ------------------------------------------------------------------ assemble
web_used = []
dungeons, boss_display, boss_npc, boss_levels, boss_spots = {}, {}, {}, {}, {}
for inst in FOREVER:
    mp = maps[inst]
    name = mp["MapName_lang"]
    dmd = dm.get(inst, {})
    rec = {"name": name}
    if dmd.get("min"):
        rec["min"], rec["max"], rec["levelSrc"] = int(dmd["min"]), int(dmd["max"]), "DungeonMaster"
    elif inst in web_range:
        rec["min"], rec["max"], rec["levelSrc"] = web_range[inst][0], web_range[inst][1], "wowf.io"
        web_used.append(f"{name}: level range")
    md = diff.get(inst)
    ct = tuning.get(int(md["ContentTuningID"])) if md and int(md["ContentTuningID"]) else None
    if ct and int(ct["MinLevelSquish"]):
        rec["tuning"] = int(ct["MinLevelSquish"])
    if md:
        rec["players"] = int(md["MaxPlayers"])
    roots = [a for a, r in areas.items() if int(r["ContinentID"]) == inst and r["ParentAreaID"] == "0"]
    rec["areaID"] = int(mp["AreaTableID"]) or next((a for a in roots if areas[a]["AreaName_lang"] == name),
                                                     roots[0] if roots else None)
    ext = EXTERIOR_AREA.get(inst)
    zone = None
    if ext:
        zone = zone_of_area(ext)
        if zone is None:
            p = int(areas[ext]["ParentAreaID"])
            zone = EXTRA_AREA_UIMAP.get(p) or EXTRA_AREA_UIMAP.get(ext)
    # entrance: DungeonMaster > Questie > centre of the outdoor area's world map overlay (approximate)
    entr = None
    ce = dm_dungeons.get(inst, {}).get("entrance")
    if ce and ce.get("map"):
        entr = {"map": int(ce["map"]), "x": ce["x"], "y": ce["y"], "src": "DungeonMaster"}
    elif rec["areaID"] in questie_entr:
        qa, qx, qy = questie_entr[rec["areaID"]]
        um = area_to_uimap.get(qa)
        if um:
            entr = {"map": um, "x": qx, "y": qy, "src": "Questie"}
    if not entr and ext:
        for o in overlays:
            if int(o["AreaID_0"]) == ext and o["UiMapArtID"] in art_to_uimap:
                cx = (int(o["OffsetX"]) + int(o["TextureWidth"]) / 2) / 1002 * 100
                cy = (int(o["OffsetY"]) + int(o["TextureHeight"]) / 2) / 668 * 100
                entr = {"map": art_to_uimap[o["UiMapArtID"]], "x": round(cx, 1), "y": round(cy, 1), "approx": True,
                        "src": "WorldMapOverlay"}
                break
    if not entr and inst == 2974:
        # Blackmaw Hold = area 1216, renamed Timbermaw Hold of Azshara: its map overlay is area 1769
        for o in overlays:
            if int(o["AreaID_0"]) == 1769 and art_to_uimap.get(o["UiMapArtID"]) == 1447:
                cx = (int(o["OffsetX"]) + int(o["TextureWidth"]) / 2) / 1002 * 100
                cy = (int(o["OffsetY"]) + int(o["TextureHeight"]) / 2) / 668 * 100
                entr = {"map": 1447, "x": round(cx, 1), "y": round(cy, 1), "approx": True, "src": "WorldMapOverlay"}
    if zone is None and entr:
        zone = entr["map"]
    rec["zone"] = zone
    if entr:
        rec["entrance"] = entr
    ls = loadscreen.get(int(mp["LoadingScreenID"]))
    if ls:
        rec["loading"] = ls
    dungeon_art = map_art.get(str(inst), {})
    floors = [dict(floor) for floor in dungeon_art.get("floors", [])]
    if dungeon_art.get("entrance"):
        rec["entranceOnArt"] = dungeon_art["entrance"]
    for folder, prefix, fname, retail_map, kind in ART_CANDIDATES.get(inst, []):
        if not tile_set(folder, prefix):
            continue
        fl = {"tiles": f"Interface\\WorldMap\\{folder}\\{prefix}", "count": 12, "cols": 4, "rows": 3,
              "name": fname, "kind": kind, "verified": False, "retailUiMap": retail_map}
        ra = retail_assign.get(retail_map)
        if ra:
            fl["world"] = {"map": int(ra["MapID"]), "minX": round(float(ra["Region_0"]), 1),
                           "minY": round(float(ra["Region_1"]), 1), "maxX": round(float(ra["Region_3"]), 1),
                           "maxY": round(float(ra["Region_4"]), 1)}
        floors.append(fl)
    rec["floors"] = floors

    # bosses: client encounters (ordered) + DungeonMaster names
    npcs, enc_npc = apr_npc.get(inst, ({}, {}))
    blist = []
    for e in sorted(bosses_by_map[inst], key=lambda r: int(r["OrderIndex"])):
        eid = int(e["ID"])
        npc = enc_npc.get(eid)
        blist.append({"name": e["Name_lang"], "encounter": eid, "npcID": npc,
                      "npcName": npcs.get(npc) if npc else None})
    rec["bosses"] = blist
    dungeons[inst] = rec
    known = {b["name"] for b in blist} | {g["name"] for g in gen_bosses.get(inst, [])}
    for boss_name, spot in dungeon_art.get("bosses", {}).items():
        if boss_name not in known:
            print("map spot for unknown boss", inst, boss_name)
        spot = {"floor": spot["floor"], "x": spot["x"], "y": spot["y"], "roams": spot.get("roams") or None}
        boss_spots.setdefault(inst, {})[boss_name] = spot

    names = {}
    for b in blist:
        names[b["name"]] = dict(b)
        if b["npcName"] and b["npcName"] != b["name"]:
            names[b["npcName"]] = dict(b)
    for g in gen_bosses.get(inst, []):
        names.setdefault(g["name"], {"name": g["name"]})
        names[g["name"]]["gen"] = g
    for b in blist:
        if b["npcName"] == b["name"]:
            b["npcName"] = None
    wb = web_boss.get(inst, {})
    levels = {}
    for nm, b in names.items():
        g = b.get("gen") or next((x for x in gen_bosses.get(inst, []) if x["name"] in (b["name"], b.get("npcName"))), None)
        npc = (g and g["npcID"] and int(g["npcID"])) or b.get("npcID")
        if npc:
            boss_npc[nm] = npc
        disp = None
        cdm = dm_dungeons.get(inst, {}).get("bosses", {})
        for key in (nm, b["name"], b.get("npcName")):
            if key and key in cdm and cdm[key].get("display"):
                disp = int(cdm[key]["display"])
        if not disp and g and g["display"]:
            disp = int(g["display"])
        w = wb.get(nm) or wb.get(b["name"]) or (b.get("npcName") and wb.get(b["npcName"]))
        if not disp and w and w.get("display"):
            disp = int(w["display"])
            web_used.append(f"{name} / {nm}: display {disp} (foreverchanges.pro)")
        if disp:
            boss_display[nm] = disp
        if w:
            lv = w.get("level") or (w.get("wlevels") or [None])[0]
            lv2 = (w.get("wlevels") or [lv, lv])[1] if not w.get("level") else lv
            if lv:
                rank = 2 if (w.get("rare") or (g and g["rare"])) else 1
                levels[nm] = (int(lv), int(lv2), rank)
                web_used.append(f"{name} / {nm}: level {lv}")
    if levels:
        boss_levels[inst] = levels

# ------------------------------------------------------------------ quests
npc_names = {}
for q in dm_quests.values():
    if q.get("npcID") and q.get("npc"):
        npc_names[int(q["npcID"])] = q["npc"]
for inst, (npcs, _) in apr_npc.items():
    npc_names.update(npcs)

quests, conflicts = {}, []
for qid in sorted(gen_quests):
    inst = gen_quests[qid]
    dq = dm_quests.get(qid, {})
    dname = dungeons[inst]["name"] if inst in dungeons else (dm.get(inst, {}).get("name") or str(inst))
    rec = {}
    if dq.get("level"):
        rec["lvl"] = int(dq["level"])
    ups = [s for s in apr_steps if s["q"] == qid and s["kind"] == "PickUp"]
    dones = [s for s in apr_steps if s["q"] == qid and s["kind"] == "Done"]
    lv = [s["minlevel"] for s in ups if s["minlevel"]]
    if lv:
        rec["req"] = min(lv)
    # start
    st = None
    kind = "item" if dq.get("drop") else "npc"
    who = "dropBy" if dq.get("drop") else "name"  # drop quests: DungeonMaster's npc is the dropping mob
    if dq.get("inside"):
        st = {"kind": kind, "inside": dname, "src": "DungeonMaster"}
        if dq.get("npc"):
            st[who] = dq["npc"]
    elif dq.get("map") and dq.get("x") is not None:
        st = {"kind": kind, "map": int(dq["map"]), "x": dq["x"], "y": dq["y"], "src": "DungeonMaster"}
        if dq.get("npc"):
            st[who] = dq["npc"]
    apr_up = next((s for s in ups if s["pos"]), None)
    apr_in = next((s for s in ups if s["inside"] and not s["pos"]), None)
    if st is None and apr_up:
        st = {"kind": kind, "map": apr_up["pos"][0], "x": apr_up["pos"][1], "y": apr_up["pos"][2], "src": "APR"}
        if dq.get("npc"):
            st[who] = dq["npc"]
    elif st is None and apr_in:
        st = {"kind": "item", "inside": dname, "src": "APR"}
    elif st is None and dq.get("npc"):
        st = {"kind": kind, who: dq["npc"], "src": "DungeonMaster"}
    if st and apr_up and st.get("map") and st["src"] == "DungeonMaster":
        if apr_up["pos"][0] != st["map"] or math.hypot(apr_up["pos"][1] - st["x"], apr_up["pos"][2] - st["y"]) > 3:
            conflicts.append(f"{qid} start: DungeonMaster {st['map']} {st['x']},{st['y']} vs APR {apr_up['pos']}")
    if st:
        rec["start"] = st
    # finish (APR turn-in step)
    fin = None
    d_pos = next((s for s in dones if s["pos"]), None)
    d_in = next((s for s in dones if s["inside"] and not s["pos"]), None)
    if d_pos:
        mp_, x, y = d_pos["pos"]
        fin = {"kind": "npc", "map": mp_, "x": x, "y": y, "src": "APR"}
        nm = next((npc_names[n] for n in d_pos["npcs"] if n in npc_names), None)
        if not nm and st and st.get("map") == mp_ and st.get("name") and st["kind"] == "npc" \
                and math.hypot(st["x"] - x, st["y"] - y) <= 1.5:
            nm = st["name"]
        if nm:
            fin["name"] = nm
    elif d_in:
        fin = {"kind": "npc", "inside": dname, "src": "APR"}
    if fin:
        rec["finish"] = fin
    rec["dungeon"] = inst
    quests[qid] = rec


# ------------------------------------------------------------------ write Lua
def lua(v, ind=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 2)).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            key = k if isinstance(k, str) and re.match(r"^[A-Za-z_]\w*$", k) else f"[{lua(k)}]"
            parts.append(f"{key} = {lua(x, ind)}")
        return "{ " + ", ".join(parts) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x, ind) for x in v) + " }"
    raise TypeError(type(v))


L = [
    "-- GENERATED by tools/import_forever.py - do not edit by hand.",
    "--",
    "-- Sources and licences:",
    "--   * DungeonMaster by MalkDev - GPLv3: level ranges of the released dungeons, entrances, boss NPC and",
    "--     display IDs, Forever quest givers (Data.lua, Curated.lua).",
    "--   * Questie / QuestieDB - GPLv3 (https://github.com/Questie/Questie): entrances of City of Dalaran and",
    "--     Excavation Site: Wetlands (Database/Zones/data/dungeons.lua).",
    "--   * Blizzard client tables of WoW Forever 1.60.1.70938 via wago.tools (https://wago.tools/db2): Map,",
    "--     MapDifficulty, ContentTuning, DungeonEncounter, AreaTable, UiMapAssignment, UiMapXMapArt,",
    "--     WorldMapOverlay, LoadingScreens; retail UiMapAssignment for the bounds of the shipped retail map art.",
    "--   * Fan sites, plain game facts only (display IDs, boss levels, level ranges of unreleased dungeons):",
    "--     https://foreverchanges.pro/dungeons and https://wowf.io/en/dungeons. Values used:",
]
for u in sorted(set(web_used)):
    L.append(f"--       {u}")
if MAPS_FILE:
    L += [
        "--   * Map floors (tools/make_forever_maps.py): the client's own minimap tiles of each dungeon map (WDT",
        "--     MAID, by FileDataID) and retail world map tiles it ships (Interface/WorldMap/Dalaran = retail",
        "--     UiMap 125/126). Boss and entrance spots: pin positions of https://foreverchanges.pro/dungeons",
        "--     (facts only) carried onto that art through measured landmarks; approximate.",
    ]
if APR_DIR:
    L.append("--   * Azeroth Pilot Reloaded (opt-in --with-apr; licence unclear): values marked src = \"APR\".")
L += [
    "--",
    "-- dungeons[instanceID] = { name, min, max (recommended), tuning (client ContentTuning level), players,",
    "--   areaID, zone = uiMapID, entrance = { map, x, y [, approx] }, loading = loading screen FileDataID,",
    "--   floors = { { tiles = path prefix + 1..12 (4x3 grid of 256px), name, kind, verified, retailUiMap,",
    "--   world = world bounds } | { pieces = { { fileID, left, top } } (square textures of pieceSize, canvas",
    "--   pixels of the 1002x668 art; the canvas clips them), pieceSize, name, kind, world } },",
    "--   entranceOnArt = { floor, x, y } (percent of the floor art), bosses = { { name, encounter, npcID, npcName } } }",
    "-- bossDisplay[name] = creature display ID (SetPortraitTextureFromCreatureDisplayID)",
    "-- bossNpc[name] = creature ID (for PlayerModel:SetCreature when no display ID is known)",
    "-- bossLevels[instanceID][name] = { minLevel, maxLevel, rank }  (rank 1 = elite, 2 = rare elite)",
    "-- bossPositions[instanceID][name] = { floor, x, y [, roams] }  (percent of the floor art, floor = index in floors)",
    "-- quests[questID] = { lvl, req, dungeon, start = { kind, name, map, x, y | inside }, finish = {...} }",
    "",
    "local _, ns = ...",
    "",
    "ns.FOREVER = {",
    "    dungeons = {",
]
for inst, rec in dungeons.items():
    L.append(f"        [{inst}] = {{ -- {rec['name']}")
    for k, v in rec.items():
        if v is None or v == []:
            continue
        if k in ("floors", "bosses"):
            L.append(f"            {k} = {{")
            for x in v:
                L.append(f"                {lua(x)},")
            L.append("            },")
        else:
            L.append(f"            {k} = {lua(v)},")
    L.append("        },")
L += ["    },", "    bossDisplay = {"]
for k in sorted(boss_display):
    L.append(f"        [{lua(k)}] = {boss_display[k]},")
L += ["    },", "    bossNpc = {"]
for k in sorted(boss_npc):
    L.append(f"        [{lua(k)}] = {boss_npc[k]},")
L += ["    },", "    bossLevels = {"]
for inst, lv in boss_levels.items():
    L.append(f"        [{inst}] = {{")
    for k, (a, b, r) in lv.items():
        L.append(f"            [{lua(k)}] = {{ {a}, {b}, {r} }},")
    L.append("        },")
L += ["    },", "    bossPositions = {"]
for inst, spots in boss_spots.items():
    L.append(f"        [{inst}] = {{")
    for k, spot in spots.items():
        L.append(f"            [{lua(k)}] = {lua(spot)},")
    L.append("        },")
L += ["    },", "    quests = {"]
for qid, rec in quests.items():
    L.append(f"        [{qid}] = {lua(rec)},")
L += ["    },", "}", ""]
open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(L))

# ------------------------------------------------------------------ report
print("instances:", ", ".join(f"{i} {dungeons[i]['name']}" for i in dungeons))
nb = sum(len(d["bosses"]) for d in dungeons.values())
print(f"encounters: {nb}; bossDisplay: {len(boss_display)}; bossNpc: {len(boss_npc)}; "
      f"bossLevels: {sum(len(v) for v in boss_levels.values())}")
print(f"quests: {len(quests)}; with start: {sum('start' in q for q in quests.values())}; "
      f"start with map: {sum('map' in q.get('start', {}) for q in quests.values())}; "
      f"with finish: {sum('finish' in q for q in quests.values())}; "
      f"finish named: {sum('name' in q.get('finish', {}) for q in quests.values())}")
print("no display:", [b["name"] for d in dungeons.values() for b in d["bosses"]
                      if b["name"] not in boss_display and (b.get("npcName") or "") not in boss_display])
print("entrances:", {i: d.get("entrance") for i, d in dungeons.items()})
print("floors:", {i: len(d["floors"]) for i, d in dungeons.items()})
print("boss spots:", {i: len(v) for i, v in boss_spots.items()})
for c in conflicts:
    print("conflict", c)
