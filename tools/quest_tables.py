"""Quest tables shared by the quest generators in tools/: zone names -> uiMapIDs of the WoW
Forever client, and whole chains written on every step."""

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
