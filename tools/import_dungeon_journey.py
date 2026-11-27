"""Build ForeverDungeonMap/Data/JourneyContent.lua: the quests of the new WoW Forever dungeons (The
Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, The Shaper's Terrace) with their
chains, objectives and quest giver spots; the bosses and rare elites the client data does not list;
boss, rare, entrance and quest objective spots on the dungeon maps where a guide map shows them;
dungeon entrances Data/Forever.lua lacks.

Sources (plain game facts only: quest IDs, names, levels, factions, NPC names, spots, item IDs):
  * the DungeonJourney addon's data files (Data/ForeverContent.lua, Data/ForeverQuestSync.lua,
    Data/QuestLocations.lua), read as text with tools/lua_literal.py, never executed;
  * Icy Veins (https://www.icy-veins.com/wow-forever/drowned-city-guide, .../drowned-city-quests,
    .../alcaz-prison-quests): GUIDE_SPOTS, QUEST_NOTES, MAP_PINS; and its database pages
    https://db.icy-veins.com/wow-forever/npcs/<npcID>, saved as <icy-dir>/npc_<npcID>.html: rank and
    drops of the extra bosses;
  * the Mobalytics Drowned City guide (https://mobalytics.gg/wow-forever/dungeons/
    drowned-city-complete-dungeon-guide-uncas): ENTRANCES;
  * QuestieDB (GPLv3, https://github.com/Questie/QuestieDB) data/Forever/foreverNpcDB.lua and
    areaIdToUiMapId.lua in <questie-dir>: spots of quest givers no other source places, by name;
  * forg.gg dungeon pages (https://forg.gg/en/forever/dungeons/<slug>), their map data saved in
    <forg-dir> (tools/forg_maps.py): boss, rare and entrance spots of Alcaz Prison, Krol'dok
    Stronghold, The Shaper's Terrace and Blackmaw Hold, and the quests the pages list (givers,
    spots, objectives, rewards, the quests before them).

Usage:
    python -I tools/import_dungeon_journey.py <DungeonJourney-dir> <icy-dir> <questie-dir> <forg-dir> ForeverDungeonMap/Data
"""
import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua_literal import parse_table, table_after, to_lua  # noqa: E402
from quest_tables import ZONE_MAPS, complete_chains  # noqa: E402
import forg_maps  # noqa: E402

JOURNEY, ICY, QUESTIE, FORG, DATA = sys.argv[1:6]

DROWNED_CITY = 2970
# DungeonJourney's dungeon key -> instance ID of Data/Forever.lua
DUNGEONS = {"drowned_city": DROWNED_CITY, "kroldok": 3039, "alcaz_prison": 2994, "blackmaw_hold": 2974,
            "shapers_terrace": 3001}
# DungeonJourney's zone names that differ from ZONE_MAPS (Riverglades: WoW Forever zone of Krol'dok)
ZONE_ALIASES = {"Stormwind": "Stormwind City", "Dalaran": "Alterac Mountains"}
EXTRA_ZONE_MAPS = {"Riverglades": 2548}
# DungeonJourney's boss name -> encounter name of Data/Forever.lua
BOSS_ALIASES = {"Deathless Marrow": "Deathless Guardians", "Overlord Mugg": "Overseer Mugg",
                "War Handler Ashka": "Handler Ashka", "Izha'Rel and Tor'Rel": "Ravasaur Hunters"}
# quest giver spots the Icy Veins quest pages give: NPC name -> (uiMapID, x, y)
GUIDE_SPOTS = {
    "Krazek": (1434, 27.0, 77.2), "Archmage Timear": (1416, 15.4, 74.0), "Mazu'kon": (1412, 32.6, 20.6),
    "Sully McCleary": (1445, 63.4, 42.4), "Sergeant Ulka": (1445, 70.2, 19.0), "Archmage Lan'dalock": (1416, 15.4, 73.8),
    "Commander Demar Brant": (2548, 66.7, 81.0), "Ashe Amberhall": (2548, 66.6, 81.0), "Sergeant Riftan": (2548, 30.6, 49.0),
    "Krom'rosh": (2548, 59.4, 45.5), "Tran'gul": (2548, 59.4, 44.0), "Da'grosh": (2548, 33.4, 38.0),
}
# DungeonJourney names a place instead of the quest giver: questID -> { start / finish = giver } (Icy Veins quest pages)
# DungeonJourney has no giver: questID -> { start / finish = (giver, zone) } (Icy Veins quest pages)
GIVER_FIXES = {96772: {"start": "Archmage Lan'dalock", "finish": "Archmage Lan'dalock"}, 94983: {"start": "Sergeant Riftan"}}
MISSING_GIVERS = {94972: ("Tran'gul", "Riverglades"), 94975: ("Da'grosh", "Riverglades")}
# what the Icy Veins quest pages add to a quest's objective
TABLETS = ("Tablets of I'lalai: down to the left after Zul'Alai; in the pirate area, half inside a skull; "
           "by Var'Taka's room; by Min'loth the Serpent's room.")
QUEST_NOTES = {
    95775: TABLETS, 95787: TABLETS,
    95788: "The I'lalai Fetish drops from undead mobs in the dungeon.",
    95789: "The Voodoo-Infused Artifacts drop from Saltseer pirates in the dungeon.",
    95791: "Kill three Saltseer Coroners and Captain Dreadrise.",
    97130: "The Ancient Gurubashi Idol drops from Deathless Marrow.",
    96774: "The Ancient Gurubashi Idol drops from Deathless Marrow.",
    95776: "Kill Var'Taka in the dungeon.",
    96381: "Kill 15 Strashaz Soldiers and 8 Strashaz Enchantresses, loot Ca'zass's Head from Tidemistress Ca'zass.",
    95262: "Find the prisoner hidden in Alcaz Prison. Do not kill The Questioner before turning in.",
    96335: "The Ornate Shackle Key drops from The Questioner.",
    96772: "Zarla's Journal is looted from Blazeroar.",
    96334: "Blood Red Bandanas drop from Defias mobs in the dungeon.",
    96906: "Blood Red Bandanas drop from Defias mobs in the dungeon.",
    94968: "The Eye of Mugg drops from Overlord Mugg, the last boss.", 94982: "The Eye of Mugg drops from Overlord Mugg, the last boss.",
    94972: "The Tome of Twilight drops from Nar'gurk.", 94984: "The Tome of Twilight drops from Nar'gurk.",
    94983: "Twilight Bangles drop from Twilight mobs in the dungeon.",
    94975: "Cultist Ears drop from Twilight mobs in the dungeon.",
    96771: "Kill Zalfan Moonshadow, who patrols near Nar'gurk.",
    94973: "Tunk drops the Krol'dok Moulding: inside, by the blacksmith area near War Handler Ashka.",
    94980: "Tunk drops the Krol'dok Moulding: inside, by the blacksmith area near War Handler Ashka.",
}
# Icy Veins' Drowned City map (drowned-city-map.jpg, 717x504): pin centres in its pixels, found by
# colour. Our floor art is the same minimap picture: our pixel = MAP_SCALE * theirs + MAP_OFFSET
# (best image fit; every pin lands in its room on our 1002x668 art).
MAP_SCALE, MAP_OFFSET = 1.338, (36, -27)
CANVAS_WIDTH, CANVAS_HEIGHT = 1002, 668
MAP_PINS = {
    DROWNED_CITY: {
        "bosses": {"Min'loth the Serpent": (75.9, 256.0), "Deathless Guardians": (198.8, 253.1), "Var'Taka": (331.9, 345.0),
                   "\"Pyromancer\" Braxton": (335.9, 131.0), "Primeval Elemental": (384.9, 415.0),
                   "Captain Dreadrise": (391.8, 150.0), "Umbra": (391.9, 330.1), "Gill": (410.9, 421.0),
                   "Zul'Alai": (488.9, 255.0)},
        "entrance": (610.9, 235.0),
        "objectives": [{"name": "Tablet of I'lalai", "quests": [95775, 95787], "pins": [(55.3, 253.2), (347.2, 331.1),
                                                                                      (372.3, 172.2), (440.4, 300.1)]}],
    },
}
# rare elites of the Icy Veins guide that no other source lists: name -> creature ID
GUIDE_RARES = {DROWNED_CITY: {"\"Pyromancer\" Braxton": 260468, "Umbra": 264172}}
# dungeon entrances better than Data/Forever.lua's (none, or the rough middle of a zone map overlay):
# instance -> (uiMapID, x, y, approximate). Drowned City: Mobalytics guide; Alcaz Prison: RXPGuides'
# world spot (-2516.5, -4951.1) on the Forever Dustwallow Marsh map; Krol'dok: Zygor's dungeon guide;
# The Shaper's Terrace: wowf.io's atlas pin (2572, 8738), carried onto Un'Goro Crater by a fit on the
# atlas pins of eight Kalimdor dungeons with known entrances (about 150 yards off).
ENTRANCES = {DROWNED_CITY: (1434, 21.0, 28.0, False), 2994: (1445, 75.7, 13.8, False), 3039: (2548, 37.5, 37.6, False),
             3001: (1449, 44.9, 14.9, True)}
# drops rarer than this (percent) are world drops, not the boss's own loot
LOOT_CHANCE = 5
# words of DungeonJourney's quest givers / zones that mean "nobody knows yet"
UNKNOWN = re.compile(r"unknown|not known", re.I)
# a zone text saying the quest starts or ends in the dungeon (Alcaz Prison's givers stand inside it)
INSIDE = re.compile(r"\binside\b|^looted in |^Dustwallow Marsh / Alcaz Prison\b", re.I)
# Places DungeonJourney names for givers no source places: a spot near them, marked approximate.
# Farholde Keep: Ashe Amberhall there; Rog'mar: Krom'rosh and Tran'gul there (Icy Veins); Ursolan:
# Lorekeeper Nok there (forg.gg); Brackenwall Village: Krog; Legashi Stronghold: the middle of the
# Legashi satyrs' spawns; Moonbrook: the village (QuestieDB NPC spots).
PLACE_SPOTS = {
    "Riverglades / Farholde Keep": (2548, 66.6, 80.5), "Riverglades / Rog'mar": (2548, 59.4, 45.0),
    "Azshara / Ursolan": (1447, 41.4, 20.0), "Dustwallow Marsh / Brackenwall Village": (1445, 36.4, 31.9),
    "Azshara / outside Legashi Stronghold": (1447, 62.8, 25.5), "Azshara / caged in Legashi Stronghold": (1447, 65.9, 17.0),
    "Westfall": (1436, 42.6, 66.5),
}
FACTIONS = ("Alliance", "Horde")
QUESTIE_NPC = re.compile(r"^\[(\d+)\] = \{'((?:[^'\\]|\\.)*)',(?:[^,{]*,){5}\{\[(\d+)\]=\{\{([\d.]+),([\d.]+)\}", re.M)
QUESTIE_AREA = re.compile(r"^\s*\[(\d+)\] = (\d+),", re.M)
ICY_DROP = re.compile(r"#(\d+)</[^>]*>\s*(?:<[^>]*>\s*)*([\d.]+)%")


def read(name):
    return open(os.path.join(JOURNEY, "Data", name), encoding="utf-8").read()


def quest_records(content, sync):
    """questID -> DungeonJourney quest record (the later sync file wins)."""
    records = {}
    for table in (table_after(content, "local QUESTS="), table_after(sync, "local NEWQ=")):
        for quest_id, entry in table.items():
            records[quest_id] = dict(entry["record"], draft=entry.get("draft") is True)
    for quest_id, fields in table_after(sync, "local FIELDS=").items():
        if quest_id in records:
            records[quest_id].update(fields)
    return records


def dungeon_lists(content, sync):
    """dungeon key -> (target quest IDs, chain quest IDs) of the five dungeons."""
    lists = {key: ([], []) for key in DUNGEONS}
    for match in re.finditer(r"D\.foreverOverrides\.dungeons\.(\w+)=dungeonEntry\(", content):
        if match.group(1) in lists:
            entry = parse_table(content, match.end())[0]
            lists[match.group(1)][0].extend(entry.get("targets", []))
            lists[match.group(1)][1].extend(entry.get("journey", []))
    for key, add in table_after(sync, "local ADDS=").items():
        if key in lists:
            lists[key][0].extend(add.get("targets", []))
            lists[key][1].extend(add.get("journey", []))
    return lists


def known_spots(content):
    """"NPC@Zone" -> (x, y) from DungeonJourney's spot tables."""
    spots = {key: (spot["x"], spot["y"]) for key, spot in table_after(read("QuestLocations.lua"), "L.seed=").items()}
    spots.update({key: (spot["x"], spot["y"]) for key, spot in table_after(content, "local PINS=").items()})
    return spots


def questie_spots():
    """NPC name -> [(uiMapID, x, y)] of every QuestieDB Forever NPC placed on a zone map."""
    areas = open(os.path.join(QUESTIE, "areaIdToUiMapId.lua"), encoding="utf-8").read()
    area_maps = {int(area): int(ui_map) for area, ui_map in QUESTIE_AREA.findall(areas) if int(ui_map) > 0}
    spots = {}
    npcs = open(os.path.join(QUESTIE, "foreverNpcDB.lua"), encoding="utf-8").read()
    for _, name, area, x, y in QUESTIE_NPC.findall(npcs):
        if int(area) in area_maps:
            spots.setdefault(name.replace("\\'", "'"), []).append((area_maps[int(area)], round(float(x), 1), round(float(y), 1)))
    return spots


def zone_map(zone):
    main = zone.split(" / ")[0].strip()
    main = ZONE_ALIASES.get(main, main)
    return ZONE_MAPS.get(main) or EXTRA_ZONE_MAPS.get(main)


class Spots:
    """Where a quest giver stands: DungeonJourney, then the Icy Veins guides, then QuestieDB by name."""

    def __init__(self, content):
        self.journey, self.questie = known_spots(content), questie_spots()

    def same_zone(self, name, ui_map):
        """DungeonJourney's spot of the NPC in the same zone, whatever words name the place."""
        for key, spot in self.journey.items():
            npc, _, zone = key.partition("@")
            if npc == name and ui_map and zone_map(zone) == ui_map:
                return spot
        return None

    def find(self, name, zone):
        ui_map = zone_map(zone)
        journey = self.journey.get("%s@%s" % (name, zone)) or self.same_zone(name, ui_map)
        if journey and ui_map:
            return ui_map, journey[0], journey[1]
        guide = GUIDE_SPOTS.get(name)
        if guide and ui_map in (None, guide[0]):
            return guide
        candidates = [spot for spot in self.questie.get(name, []) if ui_map in (None, spot[0])]
        return candidates[0] if len(candidates) == 1 or (candidates and ui_map) else None


def location(name, zone, dungeon_name, picked_up_inside, spots):
    """Location record of the addon for one end of a quest, or None when nobody knows it."""
    if not name or UNKNOWN.search(name) or (zone and UNKNOWN.search(zone) and not INSIDE.search(zone)):
        return None
    zone = zone or ""
    is_item = name.startswith("Item start: ") or zone.startswith("looted in ")
    record = {"kind": "item" if is_item else "npc", "name": name.replace("Item start: ", "")}
    # "Inside Alcaz Prison" names a place, not who gives the quest
    if INSIDE.match(name):
        del record["name"]
    if picked_up_inside or INSIDE.search(zone):
        record["inside"] = dungeon_name
        return record
    spot = spots.find(record.get("name"), zone)
    if spot:
        record.update(map=spot[0], x=spot[1], y=spot[2])
    elif zone in PLACE_SPOTS:
        ui_map, x, y = PLACE_SPOTS[zone]
        record.update(map=ui_map, x=x, y=y, approx=True, note=zone)
    elif zone:
        record["note"] = zone
    return record


def chain_steps(quest_id, records, allowed):
    """Every quest of `allowed` linked to quest_id through prerequisites / follow-ups."""
    seen, todo = set(), [quest_id]
    while todo:
        step = todo.pop()
        if step in seen or step not in records or step not in allowed:
            continue
        seen.add(step)
        todo += list(records[step].get("prerequisites") or []) + list(records[step].get("followups") or [])
    return seen


def objective(quest_id, record):
    """DungeonJourney's objective text with the Icy Veins note after it."""
    parts = [text for text in (record.get("objective"), QUEST_NOTES.get(quest_id)) if text and not UNKNOWN.search(text)]
    return " ".join(parts) or None


def apply_giver_fix(quest_id, record):
    for which, giver in GIVER_FIXES.get(quest_id, {}).items():
        record[which] = giver
    if quest_id in MISSING_GIVERS:
        record["start"], record["startZone"] = MISSING_GIVERS[quest_id]


def item_ids(items):
    """Item IDs of DungeonJourney's reward list, or None."""
    ids = [item["itemID"] for item in items or [] if isinstance(item, dict) and item.get("itemID")]
    return ids or None


def quest_entry(quest_id, record, instance_id, dungeon_name, inside_ids, spots):
    """A quest as written to ns.JOURNEY_QUESTS (instance_id None for a chain step outside the dungeon)."""
    apply_giver_fix(quest_id, record)
    entry = {"dungeon": instance_id, "name": record.get("name"), "faction": record.get("faction"),
             "classes": [record["class"]] if record.get("class") else None,
             "lvl": record.get("level"), "req": record.get("minLevel"), "objective": objective(quest_id, record),
             "start": location(record.get("start"), record.get("startZone"), dungeon_name, quest_id in inside_ids, spots),
             "finish": location(record.get("finish"), record.get("finishZone"), dungeon_name, False, spots),
             "choices": item_ids(record.get("rewardChoices")), "rewards": item_ids(record.get("rewardItems")),
             "pre": list(record.get("prerequisites") or []),
             "next": list(record.get("followups") or [])}
    if entry["faction"] not in FACTIONS:
        entry["faction"] = None
    return entry


def drop_draft_twins(quests, records):
    """A quest with a provisional ID (draft) goes when its dungeon has the real one: same name and faction."""
    def draft(quest_id):
        return records.get(quest_id, {}).get("draft", False)

    real = {(quest["dungeon"], quest["name"], quest["faction"]) for quest_id, quest in quests.items()
            if quest["dungeon"] and not draft(quest_id)}
    for quest_id in [quest_id for quest_id, quest in quests.items() if draft(quest_id)
                     and (quest["dungeon"], quest["name"], quest["faction"]) in real]:
        del quests[quest_id]
    for quest in quests.values():
        quest["pre"] = [step for step in quest["pre"] if step in quests]
        quest["next"] = [step for step in quest["next"] if step in quests]


def merge_guide_quest(quest, facts):
    """forg.gg's facts fill what DungeonJourney's quest lacks; its giver spot wins when ours has none."""
    quest["dungeon"] = quest["dungeon"] or facts["dungeon"]
    start = quest.get("start")
    if facts["start"] and (not start or not ("map" in start or "inside" in start)):
        quest["start"] = facts["start"]
    for key in ("objective", "choices", "rewards", "lvl", "req", "faction"):
        if not quest.get(key):
            quest[key] = facts[key]
    quest["pre"] += [step for step in facts["pre"] if step not in quest["pre"]]


def add_guide_quests(quests, dungeon_names):
    """forg.gg's quests of the five dungeons: new ones added, known ones completed."""
    for quest_id, facts in forg_maps.quests(FORG, dungeon_names, zone_map_by_name).items():
        if quest_id in quests:
            merge_guide_quest(quests[quest_id], facts)
        else:
            quests[quest_id] = facts


def share_known_spots(quests):
    """An NPC placed in one quest is placed in every other quest it gives or takes (same zone)."""
    known = {}
    for quest in quests.values():
        for which in ("start", "finish"):
            location = quest.get(which) or {}
            if "map" in location and location.get("name") and not location.get("approx"):
                known.setdefault(location["name"], location)
    for quest in quests.values():
        for which in ("start", "finish"):
            location = quest.get(which) or {}
            spot = known.get(location.get("name"))
            if spot and "note" in location and "map" not in location and zone_map(location["note"]) in (None, spot["map"]):
                del location["note"]
                location.update(map=spot["map"], x=spot["x"], y=spot["y"])


def zone_map_by_name(zone):
    return zone_map(zone)


def journey_quests(content, sync, dungeon_names):
    """questID -> quest entry of the five dungeons' quests and their chain steps."""
    records, spots = quest_records(content, sync), Spots(content)
    inside_ids = set(table_after(sync, "local PDJ="))
    quests = {}
    for key, (targets, chain) in dungeon_lists(content, sync).items():
        instance_id = DUNGEONS[key]
        allowed = set(targets) | set(chain)
        for target in targets:
            for step in chain_steps(target, records, allowed):
                if step in quests and quests[step]["dungeon"]:
                    continue
                quests[step] = quest_entry(step, records[step], instance_id if step in targets else None,
                                           dungeon_names[instance_id], inside_ids, spots)
    add_guide_quests(quests, dungeon_names)
    drop_draft_twins(quests, records)
    share_known_spots(quests)
    # complete_chains works on the string keys of tools/forever_quests.json
    complete_chains({str(quest_id): quest for quest_id, quest in quests.items()})
    # a chain step outside the dungeons stays only while a dungeon quest's chain holds it
    in_chains = {step for quest in quests.values() if quest["dungeon"] for step in quest["pre"] + quest["next"]}
    # a chain always carries its lists (an empty one clears older data); other empty values go
    return {quest_id: {key: value for key, value in quest.items() if value not in (None, "") and (value != [] or key in ("pre", "next"))}
            for quest_id, quest in quests.items() if quest["dungeon"] or quest_id in in_chains}


def icy_npc(npc_id):
    """(rare elite?, [itemID dropped at LOOT_CHANCE or more]) from a saved Icy Veins NPC page, or None."""
    path = os.path.join(ICY, "npc_%d.html" % npc_id)
    if not os.path.exists(path):
        return None
    page = open(path, encoding="utf-8").read()
    text = html.unescape(re.sub(r"<[^>]+>", " ", page))
    rare = re.search(r"Rank:\s*Rare Elite", text) is not None
    drops = [int(item) for item, chance in ICY_DROP.findall(page) if float(chance) >= LOOT_CHANCE]
    return rare, list(dict.fromkeys(drops))


def boss_record(name, npc_id, rare, loot):
    """An extra boss; the Icy Veins database page, when saved, has the last word on rank and loot."""
    facts = npc_id and icy_npc(npc_id)
    if facts:
        rare, loot = facts[0] or rare, facts[1] or loot
    record = {"name": name, "npcID": npc_id, "rare": rare or None, "loot": loot}
    return {key: value for key, value in record.items() if value not in (None, [])}


def extra_bosses(content, forever):
    """instance ID -> bosses (rare elites among them) DungeonJourney and the guides list and Data/Forever.lua does not."""
    bosses = {}
    for dungeon in table_after(content, "local COMPANION="):
        instance_id = DUNGEONS.get(dungeon["key"])
        if not instance_id:
            continue
        known = {boss["name"] for boss in forever["dungeons"][instance_id]["bosses"]}
        for boss in dungeon["bosses"]:
            if boss.get("trash") or boss["name"] == "Trash Drops" or BOSS_ALIASES.get(boss["name"], boss["name"]) in known:
                continue
            loot = [item["itemID"] for item in boss.get("loot", []) if item.get("itemID")]
            bosses.setdefault(instance_id, []).append(boss_record(boss["name"], boss.get("npcID"), boss.get("rare"), loot))
    for instance_id, rares in GUIDE_RARES.items():
        for name, npc_id in rares.items():
            bosses.setdefault(instance_id, []).append(boss_record(name, npc_id, True, []))
    add_guide_rares(bosses, forever)
    return bosses


def add_guide_rares(bosses, forever):
    """Rares on forg.gg's maps that neither the client data nor DungeonJourney lists."""
    for instance_id, found in forg_maps.map_spots(FORG, BOSS_ALIASES).items():
        known = {boss["name"] for boss in forever["dungeons"][instance_id]["bosses"]}
        known |= {boss["name"] for boss in bosses.get(instance_id, [])}
        for name in found["rares"]:
            if name not in known:
                bosses.setdefault(instance_id, []).append({"name": name, "rare": True})


def released_dungeons():
    """Instance IDs of the new dungeons whose bosses (Data/ForeverBosses.lua) the Icy Veins database has
    seen drop loot: they are out, whatever the "coming soon" of wowf.io still says."""
    coming = table_after(open(os.path.join(DATA, "ForeverBosses.lua"), encoding="utf-8").read(), "ns.FOREVER_BOSSES = ")
    released = {}
    for instance_id, dungeon in coming.items():
        for boss in dungeon["bosses"].values():
            facts = boss.get("npcID") and icy_npc(boss["npcID"])
            if facts and facts[1]:
                released[instance_id] = True
    return released


def art_spot(pin):
    """A guide map pin as percent of our floor art (floor 1)."""
    x, y = MAP_SCALE * pin[0] + MAP_OFFSET[0], MAP_SCALE * pin[1] + MAP_OFFSET[1]
    return {"floor": 1, "x": round(x / CANVAS_WIDTH * 100, 1), "y": round(y / CANVAS_HEIGHT * 100, 1)}


def map_spots():
    """instance ID -> { bosses = { name = spot }, entrance = spot, objectives = { { name, quests, floor, x, y } } }."""
    spots = {instance_id: {"bosses": found["bosses"], "entrance": found["entrance"]}
             for instance_id, found in forg_maps.map_spots(FORG, BOSS_ALIASES).items()}
    for instance_id, pins in MAP_PINS.items():
        objectives = [dict(name=group["name"], quests=group["quests"], **art_spot(pin))
                      for group in pins["objectives"] for pin in group["pins"]]
        spots[instance_id] = {"bosses": {name: art_spot(pin) for name, pin in pins["bosses"].items()},
                              "entrance": art_spot(pins["entrance"]), "objectives": objectives}
    return spots


def lua_lines(name, table):
    """`ns.<name> = { [key] = value, ... }` one key per line."""
    lines = ["ns.%s = {" % name]
    lines += ["    [%d] = %s," % (key, to_lua(table[key])) for key in sorted(table)]
    return lines + ["}", ""]


HEADER = [
    "-- ForeverDungeonMap - quests of the new WoW Forever dungeons, bosses and rare elites the client data",
    "-- does not list, spots on the dungeon maps from guide maps, and missing dungeon entrances.",
    "-- GENERATED by tools/import_dungeon_journey.py - do not edit by hand.",
    "-- Sources (plain game facts only): the DungeonJourney addon's data files (read as text), Icy Veins",
    "-- guides, map and NPC database, the Mobalytics Drowned City guide, QuestieDB NPC spots (GPLv3).",
    "-- ns.JOURNEY_QUESTS: shape of ns.FOREVER_QUESTS (Data/ForeverQuests.lua) plus objective; that checked",
    "-- table wins where both have a quest.",
    "-- ns.JOURNEY_BOSSES[instanceID] = { { name, npcID, rare, loot = { itemID, ... } } }",
    "-- ns.JOURNEY_SPOTS[instanceID] = { bosses = { [name] = { floor, x, y } }, entrance = { floor, x, y },",
    "--   objectives = { { name, quests = { questID }, floor, x, y } } }  (percent of the floor art)",
    "-- ns.JOURNEY_ENTRANCES[instanceID] = { map, x, y [, approx] }: wins over a rough entrance of Data/Forever.lua",
    "-- ns.JOURNEY_RELEASED[instanceID] = true: the dungeon is out (its bosses drop loot on Icy Veins' database)",
    "",
    "local _, ns = ...",
    "",
]


def write(quests, bosses, spots):
    entrances = {key: dict({"map": ui_map, "x": x, "y": y}, **({"approx": True} if approx else {}))
                 for key, (ui_map, x, y, approx) in ENTRANCES.items()}
    lines = HEADER + lua_lines("JOURNEY_QUESTS", quests) + lua_lines("JOURNEY_BOSSES", bosses)
    lines += lua_lines("JOURNEY_SPOTS", spots) + lua_lines("JOURNEY_ENTRANCES", entrances)
    lines += lua_lines("JOURNEY_RELEASED", released_dungeons())
    with open(os.path.join(DATA, "JourneyContent.lua"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines).rstrip("\n") + "\n")


def report(quests, bosses, dungeon_names):
    for instance_id, name in dungeon_names.items():
        own = [quest for quest in quests.values() if quest.get("dungeon") == instance_id]
        placed = sum(1 for quest in own if "map" in quest.get("start", {}) or "inside" in quest.get("start", {}))
        print("%s: quests %d (start known %d), extra bosses %s" % (name, len(own), placed,
                                                                 [boss["name"] for boss in bosses.get(instance_id, [])]))
    unplaced = sorted({quest[which]["name"] for quest in quests.values() for which in ("start", "finish")
                       if "note" in quest.get(which, {}) and "name" in quest[which] and "map" not in quest[which]})
    print("givers without a spot:", ", ".join(unplaced))


def main():
    content, sync = read("ForeverContent.lua"), read("ForeverQuestSync.lua")
    forever = table_after(open(os.path.join(DATA, "Forever.lua"), encoding="utf-8").read(), "ns.FOREVER = ")
    dungeon_names = {instance_id: forever["dungeons"][instance_id]["name"] for instance_id in DUNGEONS.values()}
    quests = journey_quests(content, sync, dungeon_names)
    bosses = extra_bosses(content, forever)
    write(quests, bosses, map_spots())
    report(quests, bosses, dungeon_names)


if __name__ == "__main__":
    main()
