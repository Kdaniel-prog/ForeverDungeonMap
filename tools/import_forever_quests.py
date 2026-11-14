"""Build ForeverDungeonMap/Data/ForeverQuests.lua from tools/forever_quests.json: the checked
pick-up and turn-in spots, chains and random spawn spots of the WoW Forever dungeon quests.

tools/forever_quests.json is kept by hand from public pages (Wowhead WoW Forever quest and NPC
pages, fan-site dungeon guides); every quest lists the pages it was read from. Only plain game
facts are used (who gives / takes the quest, where they stand, which quests come before / after).
Zones are written by name and turned into uiMapIDs here.

Where an NPC's ID is known, its spot comes from QuestieDB's WoW Forever NPC table (GPLv3,
https://github.com/Questie/QuestieDB, data/Forever/foreverNpcDB.lua): those coordinates were
recorded in the Forever client, whose city maps differ from the old classic ones (Stormwind
uses the modern map). The hand-kept coordinates are only the fallback; differences are printed.

Usage:
    python -I tools/import_forever_quests.py tools/forever_quests.json <questie_src-dir>         ForeverDungeonMap/Data/ForeverQuests.lua

<questie_src-dir> is the same flat directory tools/import_questie.py reads (foreverNpcDB.lua and
areaIdToUiMapId.lua); the files are read as text, never executed.
"""
import json
import os
import re
import sys

SOURCE, QUESTIE_DIR, OUT = sys.argv[1:4]
# [npcID] = {'name',minHealth,maxHealth,minLevel,maxLevel,rank,{[areaID]={{x,y},...}},...
NPC_SPAWN = re.compile(r"^\[(\d+)\] = \{'(?:[^'\\]|\\.)*',(?:[^,{]*,){5}\{\[(\d+)\]=\{\{([\d.]+),([\d.]+)\}", re.M)
AREA_MAP = re.compile(r"^\s*\[(\d+)\] = (\d+),", re.M)
# a spot further than this (percent) from Questie's is reported
REPORT_DISTANCE = 1.5

# English zone name -> uiMapID of the WoW Forever client (classic continents' zone maps).
ZONE_MAPS = {
    "Durotar": 1411, "Mulgore": 1412, "The Barrens": 1413, "Alterac Mountains": 1416, "Arathi Highlands": 1417,
    "Badlands": 1418, "Blasted Lands": 1419, "Tirisfal Glades": 1420, "Silverpine Forest": 1421,
    "Western Plaguelands": 1422, "Eastern Plaguelands": 1423, "Hillsbrad Foothills": 1424, "The Hinterlands": 1425,
    "Dun Morogh": 1426, "Searing Gorge": 1427, "Burning Steppes": 1428, "Elwynn Forest": 1429,
    "Deadwind Pass": 1430, "Duskwood": 1431, "Loch Modan": 1432, "Redridge Mountains": 1433,
    "Stranglethorn Vale": 1434, "Swamp of Sorrows": 1435, "Westfall": 1436, "Wetlands": 1437, "Teldrassil": 1438,
    "Darkshore": 1439, "Ashenvale": 1440, "Thousand Needles": 1441, "Stonetalon Mountains": 1442, "Desolace": 1443,
    "Feralas": 1444, "Dustwallow Marsh": 1445, "Tanaris": 1446, "Azshara": 1447, "Felwood": 1448,
    "Un'Goro Crater": 1449, "Moonglade": 1450, "Silithus": 1451, "Winterspring": 1452, "Stormwind City": 1453,
    "Orgrimmar": 1454, "Ironforge": 1455, "Thunder Bluff": 1456, "Darnassus": 1457, "Undercity": 1458,
}
# near = "entrance" or a boss name: where an in-dungeon giver / starter is drawn on the dungeon map
LOCATION_KEYS = ("kind", "name", "npcID", "itemID", "objectID", "map", "x", "y", "inside", "dropBy", "note", "spots", "near")
QUEST_KEYS = ("dungeon", "name", "faction", "classes", "lvl", "req", "start", "finish", "pre", "next", "inside", "drop")


def questie_npc_spots():
    """npcID -> (uiMapID, x, y): the first spawn of every NPC QuestieDB places on a zone map."""
    area_text = open(os.path.join(QUESTIE_DIR, "areaIdToUiMapId.lua"), encoding="utf-8").read()
    area_maps = {int(area): int(ui_map) for area, ui_map in AREA_MAP.findall(area_text) if int(ui_map) > 0}
    npc_text = open(os.path.join(QUESTIE_DIR, "foreverNpcDB.lua"), encoding="utf-8").read()
    spots = {}
    for npc_id, area, x, y in NPC_SPAWN.findall(npc_text):
        if int(area) in area_maps:
            spots[int(npc_id)] = (area_maps[int(area)], round(float(x), 1), round(float(y), 1))
    return spots


def apply_questie_spot(record, quest_id, npc_spots):
    """Questie's spot for a known NPC outside the dungeon; prints where the hand-kept one differs."""
    spot = npc_spots.get(record.get("npcID"))
    if not spot or "inside" in record:
        return
    ui_map, x, y = spot
    if record.get("map") != ui_map or abs(record.get("x", 0) - x) + abs(record.get("y", 0) - y) > REPORT_DISTANCE:
        print("quest %s %s: %s %s,%s -> Questie %s %s,%s" % (quest_id, record.get("name"), record.get("map"),
                                                          record.get("x"), record.get("y"), ui_map, x, y))
    record.update(map=ui_map, x=x, y=y)


def location(raw, dungeon_name, quest_id, npc_spots):
    """Location record of the addon: zone name -> map, "inside" -> the dungeon's name."""
    if not raw:
        return None
    record = {key: raw[key] for key in LOCATION_KEYS if raw.get(key) not in (None, "", [])}
    zone = raw.get("zone")
    if zone == "inside":
        record["inside"] = dungeon_name
    elif zone:
        if zone not in ZONE_MAPS:
            sys.exit("quest %s: unknown zone %r" % (quest_id, zone))
        record["map"] = ZONE_MAPS[zone]
    apply_questie_spot(record, quest_id, npc_spots)
    if "map" in record and not ("x" in record and "y" in record):
        sys.exit("quest %s: zone without coordinates" % quest_id)
    return record


def lua(value, indent=""):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(round(value, 1)) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, list):
        return "{ " + ", ".join(lua(item, indent) for item in value) + " }"
    if isinstance(value, dict):
        return "{ " + ", ".join("%s = %s" % (key, lua(item, indent)) for key, item in value.items()) + " }"
    raise TypeError(value)


def quest_record(quest_id, raw, dungeon_names, npc_spots):
    dungeon_name = dungeon_names.get(str(raw.get("dungeon")), "")
    record = {}
    for key in QUEST_KEYS:
        value = raw.get(key)
        if key in ("start", "finish"):
            value = location(value, dungeon_name, quest_id, npc_spots)
        # a dungeon quest always carries its chain: an empty one clears what older data claimed
        keeps_empty = key in ("pre", "next") and "dungeon" in raw
        if value not in (None, "", []) or (keeps_empty and value == []):
            record[key] = value
    return record


def write(quests, names, sources):
    lines = [
        "-- GENERATED by tools/import_forever_quests.py from tools/forever_quests.json - do not edit by hand.",
        "-- Pick-up / turn-in spots, chains and random spawn spots of the WoW Forever dungeon quests, read",
        "-- (plain game facts only) from: " + ", ".join(sources) + ".",
        "-- ns.FOREVER_QUESTS[questID] = { dungeon, name, faction, lvl, req, start, finish, pre, next, inside, drop }",
        "--   start / finish = { kind, name, npcID | itemID | objectID, map, x, y | inside, dropBy, note, spots, near }",
        "--   near = \"entrance\" or a boss name: where an in-dungeon giver / starter goes on the dungeon map",
        "--   dungeon = nil for a follow-up step done outside the dungeon (shown only in the chain).",
        "-- ns.FOREVER_QUEST_NAMES[questID] = name of a chain step no other table names",
        "",
        "local _, ns = ...",
        "",
        "ns.FOREVER_QUESTS = {",
    ]
    for quest_id in sorted(quests, key=int):
        lines.append("    [%s] = %s," % (quest_id, lua(quests[quest_id])))
    lines += ["}", "", "ns.FOREVER_QUEST_NAMES = {"]
    for quest_id in sorted(names, key=int):
        lines.append("    [%s] = %s," % (quest_id, lua(names[quest_id])))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def complete_chains(quests):
    """Write the whole chain on every quest: all earlier steps in `pre`, all later ones in `next`,
    following the links both ways (A.next = B also makes A a step before B)."""
    before = {quest_id: list(raw.get("pre") or []) for quest_id, raw in quests.items()}
    after = {quest_id: list(raw.get("next") or []) for quest_id, raw in quests.items()}
    for quest_id in quests:
        for step in after[quest_id]:
            before.setdefault(str(step), [])
            if int(quest_id) not in before[str(step)]:
                before[str(step)].append(int(quest_id))
        for step in before[quest_id]:
            after.setdefault(str(step), [])
            if int(quest_id) not in after[str(step)]:
                after[str(step)].append(int(quest_id))

    # a step's own earlier steps come before it, its later steps after it
    def walk(links, quest_id, seen, earlier):
        steps = []
        for step in links.get(str(quest_id), []):
            if step not in seen:
                seen.add(step)
                deeper = walk(links, step, seen, earlier)
                steps += deeper + [step] if earlier else [step] + deeper
        return steps

    for quest_id, raw in quests.items():
        raw["pre"] = walk(before, quest_id, {int(quest_id)}, True)
        raw["next"] = walk(after, quest_id, {int(quest_id)}, False)


def main():
    data = json.load(open(SOURCE, encoding="utf-8"))
    dungeon_names = data["dungeons"]
    complete_chains(data["quests"])
    npc_spots = questie_npc_spots()
    quests = {quest_id: quest_record(quest_id, raw, dungeon_names, npc_spots) for quest_id, raw in data["quests"].items()}
    write(quests, data.get("names", {}), data["sources"])
    with_finish = sum("finish" in quest for quest in quests.values())
    print("quests %d, with start %d, with turn-in %d" % (len(quests), sum("start" in q for q in quests.values()), with_finish))


if __name__ == "__main__":
    main()
