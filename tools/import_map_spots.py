"""Build the spots on the classic dungeon map art:

    ForeverDungeonMap/Data/BossPositions.lua  boss pins
    ForeverDungeonMap/Data/DungeonSpots.lua   entrances and quest NPCs/objects inside dungeons
    ForeverDungeonMap/Data/FloorAreas.lua     subzone name -> floor (live view)

Boss spots come first from Blizzard's Encounter Journal (JournalEncounter.Map_0/Map_1,
retail build). Where the journal has no spot, and for every entrance and quest giver, the
world position comes from the CMaNGOS classic-db (GPLv3, https://github.com/cmangos/classic-db):
creature / gameobject spawns (a rare's most central spawn), script summons of event bosses,
areatrigger_teleport targets and quest relations. A world
position becomes a 0..1 spot on a floor's art with Blizzard's UiMapAssignment table (the
same art as the WoW Forever client for the unchanged classic dungeons).

Floors are the dungeon's UiMaps in UiMapAssignment, in ID order (the art's floor numbers).
When several floors cover a spot, the floor is taken from the WMO group the spot is in
(group boxes from the dungeon's WMO files, groups tied to floors by UiMapAssignment), else
from the nearest boss whose journal floor is known; a group drawn on several floors takes the
nearest known boss's floor, else the lowest of them.

Inputs (all treated as data only, nothing in them is executed):
    <wago-dir>    retail CSVs from https://wago.tools/db2/<Table>/csv : JournalEncounter,
                  JournalInstance, UiMapAssignment, Map, WMOAreaTable, AreaTrigger
    <forever-dir> the same site with ?build=1.60.1.70938 (WoW Forever): WMOAreaTable, AreaTable,
                  UiMapAssignment, UiMap
    <casc-dir>    game files named <FileDataID>.bin from https://wago.tools/api/casc/<id>?download
                  (WDT, obj0 ADT, WMO root and group files). The FileDataIDs still needed are
                  printed at the end of a run; download them and run again until none are left.
    <classic-db>  Full_DB/ClassicDB_*.sql.gz of cmangos/classic-db
    <questie-dungeons> Database/Zones/data/dungeons.lua of Questie (GPLv3): the zone each
                  dungeon's entrance is in
    <worldmap-files> wago.tools file list of the WoW Forever build (JSON {fileDataID: path}):
                  https://wago.tools/api/files?search=interface/worldmap/&version=1.60.1.70938
                  The floors' art tiles it names are read from <casc-dir> like the WMO files.
    <pillow-dir>  site-packages directory holding Pillow (reads the BLP art tiles)

Every spot is checked against the floor art itself: a spot more than ON_FLOOR_RADIUS pixels
from the drawn floor (pale, lighter than the parchment) is moved to the nearest drawn-floor
pixel; each move is printed. Only spots out on the open parchment move (reachable from the
frame without crossing drawn lines): a walled-in spot may be in a room the detection misses. Journal spots and entrances (the art draws the portal swirl,
often on the parchment) are never moved. A floor is only checked when all its journal spots
land on the detected floor and at least half the floor's creature spawns do; other floors
are listed as not checked.

Usage:
    python -I tools/import_map_spots.py <wago-dir> <forever-dir> <casc-dir> <classic-db> \
        <questie-dungeons> <worldmap-files> <pillow-dir> ForeverDungeonMap/Data
"""
import csv
import gzip
import json
import itertools
import math
import os
import re
import statistics
import struct
import sys

WAGO, FOREVER, CASC, CLASSIC_DB, QUESTIE_DUNGEONS, WORLDMAP_FILES, PILLOW, DATA = sys.argv[1:9]
sys.path.append(PILLOW)
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat  # noqa: E402

# floor art: 4 x 3 tiles of 256 px, of which the top-left 1002 x 668 are visible
ART_TILE, ART_COLUMNS, ART_TILES, ART_SIZE = 256, 4, 12, (1002, 668)
# a pixel looks drawn when its colour differs from the parchment's (brightness-free distance)
# by more than FLOOR_CHROMA, or it is FLOOR_LIGHTER lighter with some colour change, or
# FLOOR_BRIGHT lighter outright; darker than FLOOR_DARKER below the parchment is outline/rim
FLOOR_CHROMA, FLOOR_TINT = 0.2, 0.05
FLOOR_LIGHTER, FLOOR_BRIGHT, FLOOR_DARKER = 15, 35, 15
# drawn patches are bigger than this (pixels) and have an inked edge: mean edge strength
# around them at least FLOOR_EDGE (parchment stains are soft, about 15..22); patches bigger
# than FLOOR_LARGE_AREA are floor whatever their edge (the largest stain seen is ~15500)
FLOOR_MIN_AREA, FLOOR_EDGE, FLOOR_LARGE_AREA = 400, 24, 20000
# the parchment colour is measured in this band (pixels from the edge, inside the frame)
PARCHMENT_BAND = (40, 80)
# drawn lines (walls, outlines) are this much darker than the parchment
OUTLINE_DARKER = 25
# share of a floor's creature spawns that must land on detected floor to trust the detection
# (Wailing Caverns, whose art leaves out a part of the cave, has 0.51; failed detections <0.4)
FLOOR_COVERAGE = 0.5
# a spot this close (pixels) to drawn floor is on it; a moved spot lands this far inside it
ON_FLOOR_RADIUS = 10
FLOOR_MARGIN = 3
# farthest (pixels) a spot is moved; farther means the art does not show that place at all
MAX_MOVE = 150
# ADT placements are stored relative to this corner of the 64x64 tile world
ADT_ORIGIN = 17066.666
# a WMO's local axes are turned this much past the placement's yaw (checked against MODF extents)
WMO_YAW_OFFSET = 180
# UiMapAssignment rows wider than this are catch-alls, not a floor
CATCH_ALL_SIZE = 10000
# spawns closer than this (yards) count as one cluster of a rare's spawn points
CLUSTER_RADIUS = 40
# spawns stand on a floor surface: let them sit this far outside a WMO group box
GROUP_MARGIN = 2.0
# UiMap.Type of a zone map (continents are 2, dungeons 4)
ZONE_MAP_TYPE = "3"
# Retail swapped these dungeons' WMO for a remake whose groups UiMapAssignment never lists;
# WMOID -> root FileDataID of the classic WMO (wago.tools file list), set where the remake sits.
CLASSIC_WMO_ROOTS = {
    2212: 108373,  # world/wmo/dungeon/az_blackrock/blackrock_upper_instance.wmo
    2213: 108299,  # world/wmo/dungeon/az_blackrock/blackrock_lower_instance.wmo
    3454: 110159,  # world/wmo/dungeon/ld_stratholme/stratholme_b.wmo
}

# classic boss -> retail boss standing in the same spot (redesigned dungeons)
ALIASES = {
    36: {"Rhahk'Zor": "Glubtok", "Gilnid": "Helix Gearbreaker", "Sneed": "Foe Reaper 5000",
         "Sneed's Shredder": "Foe Reaper 5000", "Mr. Smite": "Admiral Ripsnarl",
         "Captain Greenskin": "Admiral Ripsnarl", "Cookie": "\"Captain\" Cookie",
         "Edwin VanCleef": "Vanessa VanCleef"},
}


def normalized(name):
    return re.sub(r"[^a-z0-9]", "", name.lower().replace("the ", ""))


def read_csv(directory, table):
    return list(csv.DictReader(open(os.path.join(directory, f"{table}.csv"), encoding="utf-8")))


# Generated.lua: {instanceID: [(name, encounterID, npcID)]} and every quest ID of ns.QUESTS.
def read_generated(path):
    text = open(path, encoding="utf-8").read()
    bosses, instance = {}, None
    for line in text[:text.index("ns.WINGS")].splitlines():
        header = re.match(r"\s*\[(\d+)\] = \{ -- ", line)
        if header:
            instance = int(header.group(1))
            bosses[instance] = []
            continue
        boss = re.match(r'\s*\{ name = "((?:[^"\\]|\\.)*)"(.*)\},', line)
        if boss and instance is not None:
            encounter = re.search(r"encounter = (\d+)", boss.group(2))
            npc = re.search(r"npcID = (\d+)", boss.group(2))
            bosses[instance].append((boss.group(1).replace('\\"', '"'),
                                     int(encounter.group(1)) if encounter else None,
                                     int(npc.group(1)) if npc else None))
    return bosses, quest_ids(text)


def quest_ids(text):
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    start = text.index("ns.QUESTS = {")
    block = text[start:re.compile(r"^}", re.M).search(text, start).start()]
    ids = {int(x) for x in re.findall(r"\bid\s*=\s*(\d+)", block)}
    for pre in re.finditer(r"\bpre\s*=\s*\{([^}]*)\}", block):
        ids.update(int(x) for x in re.findall(r"\d+", pre.group(1)))
    return ids


SQL_ROW = re.compile(r"\(((?:'(?:[^'\\]|\\.)*'|[^'()])*)\)")
SQL_FIELD = re.compile(r"'((?:[^'\\]|\\.)*)'|([^,]+)")
SQL_TABLES = ("creature", "creature_spawn_entry", "gameobject", "gameobject_spawn_entry",
              "creature_template", "gameobject_template", "creature_questrelation",
              "creature_involvedrelation", "gameobject_questrelation",
              "gameobject_involvedrelation", "areatrigger_teleport")
SCRIPT_TABLES = tuple(f"dbscripts_on_{source}" for source in (
    "creature_death", "creature_movement", "event", "go_template_use", "go_use", "gossip",
    "quest_end", "quest_start", "relay", "spell"))
SQL_TABLES += SCRIPT_TABLES
# dbscripts command that summons a creature (datalong = entry) at x, y, z
SCRIPT_SUMMON_CREATURE = "10"


# The dump's INSERT rows of SQL_TABLES as dicts keyed by column name.
def read_classic_db(path):
    columns, rows, creating = {}, {table: [] for table in SQL_TABLES}, None
    for line in gzip.open(path, "rt", encoding="utf-8", errors="replace"):
        create = re.match(r"CREATE TABLE `(\w+)`", line)
        if create:
            creating = create.group(1) if create.group(1) in SQL_TABLES else None
            columns[creating] = []
        elif creating and re.match(r"\s+`(\w+)`", line):
            columns[creating].append(re.match(r"\s+`(\w+)`", line).group(1))
        elif line.startswith("INSERT INTO `"):
            table = line[13:line.index("`", 13)]
            if table in rows:
                rows[table] += [dict(zip(columns[table], sql_fields(row.group(1))))
                                for row in SQL_ROW.finditer(line)]
    return rows


def sql_fields(row):
    return [field.group(1).replace("\\'", "'") if field.group(1) is not None else field.group(2).strip()
            for field in SQL_FIELD.finditer(row)]


# Spawn points per entry: {(kind, entry): [(map, x, y, z)]}, random-entry spawns included.
def spawn_points(db):
    points = {}
    for kind, table in (("npc", "creature"), ("object", "gameobject")):
        random_entries = {}
        for row in db[f"{table}_spawn_entry"]:
            random_entries.setdefault(row["guid"], []).append(int(row["entry"]))
        for row in db[table]:
            entries = [int(row["id"])] if row["id"] != "0" else random_entries.get(row["guid"], [])
            point = (int(row["map"]), float(row["position_x"]), float(row["position_y"]),
                     float(row["position_z"]))
            for entry in entries:
                points.setdefault((kind, entry), []).append(point)
    return points


# Script summons (event bosses without a spawn): {npcID: [(x, y, z)]}, map unknown.
def summon_points(db):
    points = {}
    for table in SCRIPT_TABLES:
        for row in db[table]:
            if row["command"] == SCRIPT_SUMMON_CREATURE:
                points.setdefault(int(row["datalong"]), []).append(
                    (float(row["x"]), float(row["y"]), float(row["z"])))
    return points


# The spawn with the most other spawns around it (where a rare's spawns cluster); ties go to
# the one closest to all others.
def densest_spawn(points):
    def crowding(p):
        return (-sum(math.dist(p[1:], q[1:]) <= CLUSTER_RADIUS for q in points),
                sum(math.dist(p[1:], q[1:]) for q in points))
    return min(points, key=crowding)


class Floor:
    def __init__(self, number, ui_map):
        self.number, self.ui_map, self.rows = number, ui_map, []

    # 0..1 spot on this floor's art, or None if the floor does not cover the point.
    def spot(self, x, y, z):
        for region, art, _ in self.rows:
            if region[0] <= x <= region[3] and region[1] <= y <= region[4] and region[2] <= z <= region[5]:
                return (art[0] + (region[4] - y) / (region[4] - region[1]) * (art[2] - art[0]),
                        art[1] + (region[3] - x) / (region[3] - region[0]) * (art[3] - art[1]))
        return None

    def group_ids(self):
        return {group for _, _, group in self.rows}


# {mapID: [Floor]} from UiMapAssignment; floor number = rank of the UiMap ID.
def read_floors(assignments, instances):
    rows_by_map = {}
    for row in assignments:
        map_id = int(row["MapID"])
        region = [float(row[f"Region_{i}"]) for i in range(6)]
        width = region[3] - region[0]
        if map_id in instances and 0 < width < CATCH_ALL_SIZE:
            art = [float(row[c]) for c in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")]
            rows_by_map.setdefault(map_id, {}).setdefault(int(row["UiMapID"]), []).append(
                (region, art, int(row["WMOGroupID"])))
    floors = {}
    for map_id, by_ui_map in rows_by_map.items():
        floors[map_id] = []
        for number, ui_map in enumerate(sorted(by_ui_map), 1):
            floor = Floor(number, ui_map)
            floor.rows = by_ui_map[ui_map]
            floors[map_id].append(floor)
    return floors


def floors_overlap(floors):
    for a, b in itertools.combinations(floors, 2):
        for (ra, _, _), (rb, _, _) in itertools.product(a.rows, b.rows):
            if ra[0] < rb[3] and rb[0] < ra[3] and ra[1] < rb[4] and rb[1] < ra[4]:
                return True
    return False


class Casc:
    """Game files by FileDataID from <casc-dir>; remembers the ones not downloaded yet."""

    def __init__(self, directory):
        self.directory, self.missing = directory, set()

    def chunks(self, file_id):
        path = os.path.join(self.directory, f"{file_id}.bin")
        if not os.path.exists(path):
            self.missing.add(file_id)
            return None
        data, found, offset = open(path, "rb").read(), {}, 0
        while offset + 8 <= len(data):
            tag = data[offset:offset + 4][::-1].decode("latin1")
            size = struct.unpack_from("<I", data, offset + 4)[0]
            found.setdefault(tag, []).append(data[offset + 8:offset + 8 + size])
            offset += 8 + size
        return found

    def path(self, file_id):
        path = os.path.join(self.directory, f"{file_id}.bin")
        if not os.path.exists(path):
            self.missing.add(file_id)
            return None
        return path


# WMO placements of a map: [(rootFileID, (x, y, z) world origin, yaw degrees)].
def wmo_placements(casc, wdt_id):
    wdt = casc.chunks(wdt_id)
    if wdt is None:
        return []
    if struct.unpack_from("<I", wdt["MPHD"][0], 0)[0] & 1:
        return [placement(entry, 0) for entry in modf_entries(wdt)]
    entries = []
    for tile in range(4096):
        obj0 = struct.unpack_from("<8I", wdt["MAID"][0], tile * 32)[1]
        tile_chunks = casc.chunks(obj0) if obj0 else None
        entries += modf_entries(tile_chunks) if tile_chunks else []
    unique = {struct.unpack_from("<I", entry, 4)[0]: entry for entry in entries}
    return [placement(entry, ADT_ORIGIN) for entry in unique.values()]


def modf_entries(chunks):
    return [body[i:i + 64] for body in chunks.get("MODF", []) for i in range(0, len(body), 64)]


def placement(entry, origin):
    px, py, pz = struct.unpack_from("<3f", entry, 8)
    yaw = struct.unpack_from("<3f", entry, 20)[1]
    return struct.unpack_from("<I", entry, 0)[0], (origin - pz, origin - px, py), yaw


# {groupID: world box} of the WMOs whose groups are tied to floors (WMOAreaTable.WMOID);
# a remade dungeon uses its classic WMO at the place of the map's biggest WMO.
def group_boxes(casc, wdt_id, wanted_wmo_ids):
    placements = wmo_placements(casc, wdt_id)
    roots = [(casc.chunks(root_id), origin, yaw) for root_id, origin, yaw in placements]
    roots = [(root, origin, yaw) for root, origin, yaw in roots if root]
    placed_ids = {struct.unpack_from("<I", root["MOHD"][0], 32)[0] for root, _, _ in roots}
    replaced = [w for w in wanted_wmo_ids - placed_ids if w in CLASSIC_WMO_ROOTS]
    if replaced and roots:
        main_origin, main_yaw = max(roots, key=lambda r: len(r[0]["GFID"][0]))[1:]
        classic = [casc.chunks(CLASSIC_WMO_ROOTS[w]) for w in replaced]
        roots += [(root, main_origin, main_yaw) for root in classic if root]
    boxes = {}
    for root, origin, yaw in roots:
        if struct.unpack_from("<I", root["MOHD"][0], 32)[0] in wanted_wmo_ids:
            boxes.update(wmo_group_boxes(casc, root, origin, yaw))
    return boxes


def wmo_group_boxes(casc, root, origin, yaw):
    boxes = {}
    for file_id in struct.unpack_from(f"<{len(root['GFID'][0]) // 4}I", root["GFID"][0]):
        group = casc.chunks(file_id) if file_id else None
        if group:
            header = group["MOGP"][0]
            local_box = struct.unpack_from("<6f", header, 12)
            boxes[struct.unpack_from("<I", header, 56)[0]] = world_box(local_box, origin, yaw)
    return boxes


def world_box(box, origin, yaw):
    angle = math.radians(yaw + WMO_YAW_OFFSET)
    xs, ys = [], []
    for x, y in itertools.product((box[0], box[3]), (box[1], box[4])):
        xs.append(origin[0] + x * math.cos(angle) - y * math.sin(angle))
        ys.append(origin[1] + x * math.sin(angle) + y * math.cos(angle))
    return (min(xs), min(ys), origin[2] + box[2], max(xs), max(ys), origin[2] + box[5])


class Dungeon:
    """One instance map: its floors, WMO group boxes and floors of known boss spawns."""

    def __init__(self, map_id, floors, boxes):
        self.map_id, self.floors, self.boxes, self.references = map_id, floors, boxes, []

    def candidates(self, point):
        found = [(floor, floor.spot(*point)) for floor in self.floors]
        return [(floor.number, spot) for floor, spot in found if spot]

    # (floor, x, y) of a world point, or None if no floor holds it. A WMO group drawn on
    # several floors goes to the floor of the nearest known boss, else the lowest one.
    def place(self, point, references=None):
        candidates = dict(self.candidates(point))
        numbers = set(candidates)
        group_floors = self.floor_from_groups(point, numbers) if len(numbers) > 1 else None
        numbers = group_floors or numbers
        if len(numbers) > 1:
            numbers = self.floor_from_references(point, numbers, references) or numbers
        if not numbers or (len(numbers) > 1 and not group_floors):
            return None
        number = min(numbers)
        return number, *candidates[number]

    # Floors of the smallest WMO group holding the point (it stands on the group's floor,
    # so it may sit just below the box, never above it).
    def floor_from_groups(self, point, numbers):
        inside = [(box_volume(box), group) for group, box in self.boxes.items()
                  if all(box[i] - GROUP_MARGIN <= point[i] <= box[i + 3] + GROUP_MARGIN for i in range(2))
                  and box[2] - GROUP_MARGIN <= point[2] <= box[5]]
        for _, group in sorted(inside):
            owners = {f.number for f in self.floors if group in f.group_ids()} & numbers
            if owners:
                return owners
        return None

    def floor_from_references(self, point, numbers, references):
        known = self.references if references is None else references
        usable = [(math.dist(point, p), n) for p, n in known if n in numbers]
        return {min(usable)[1]} if usable else None


def box_volume(box):
    return (box[3] - box[0]) * (box[4] - box[1]) * (box[5] - box[2])


# {instanceID: Dungeon} for every instance with floors; WMO groups only where floors overlap.
def build_dungeons(instances, casc):
    floors = read_floors(read_csv(WAGO, "UiMapAssignment"), instances)
    wdts = {int(r["ID"]): int(r["WdtFileDataID"]) for r in read_csv(WAGO, "Map")}
    wmo_of_group = {int(r["WMOGroupID"]): int(r["WMOID"]) for r in read_csv(WAGO, "WMOAreaTable")}
    dungeons = {}
    for map_id, map_floors in floors.items():
        boxes = {}
        if floors_overlap(map_floors):
            wanted = {wmo_of_group.get(g) for f in map_floors for g in f.group_ids()} - {None}
            boxes = group_boxes(casc, wdts[map_id], wanted)
        dungeons[map_id] = Dungeon(map_id, map_floors, boxes)
    return dungeons


# {instanceID: {boss: (floor, x, y)}} from the Encounter Journal.
def journal_spots(bosses, dungeons):
    encounters, journals = read_csv(WAGO, "JournalEncounter"), read_csv(WAGO, "JournalInstance")
    spots = {}
    for instance, dungeon in dungeons.items():
        floor_of = {f.ui_map: f.number for f in dungeon.floors}
        journal_ids = {r["ID"] for r in journals if r["MapID"] == str(instance)}
        rows = [r for r in encounters if r["JournalInstanceID"] in journal_ids
                and int(r["UiMapID"] or 0) in floor_of and float(r["Map_0"]) + float(r["Map_1"]) > 0]
        by_encounter = {int(r["DungeonEncounterID"]): r for r in rows if r["DungeonEncounterID"]}
        by_name = {normalized(r["Name_lang"]): r for r in rows}
        for name, encounter, _ in bosses.get(instance, []):
            alias = ALIASES.get(instance, {}).get(name)
            row = (by_encounter.get(encounter) or by_name.get(normalized(name))
                   or (alias and by_name.get(normalized(alias))))
            if row:
                spots.setdefault(instance, {})[name] = (floor_of[int(row["UiMapID"])],
                                                        float(row["Map_0"]), float(row["Map_1"]))
    return spots


# The boss's spawn in its dungeon; bosses sharing a random spawn pool each get a spawn
# not taken yet (taken = spawns already given out in this dungeon).
def boss_spawn(points, instance, npc, taken=()):
    inside = [p for p in points.get(("npc", npc), []) if p[0] == instance] if npc else []
    free = [p for p in inside if p[1:] not in taken] or inside
    return densest_spawn(free)[1:] if free else None


# Journal bosses' spawns become the floor references of their dungeon.
def add_references(dungeons, bosses, journal, points):
    for instance, dungeon in dungeons.items():
        for name, _, npc in bosses.get(instance, []):
            spawn = boss_spawn(points, instance, npc)
            if spawn and name in journal.get(instance, {}):
                dungeon.references.append((spawn, journal[instance][name][0]))


# A script summon point of the boss that lies on one of the dungeon's floors.
def boss_summon(summons, dungeon, npc):
    on_floors = [p for p in summons.get(npc, []) if dungeon.candidates(p)]
    return on_floors[0] if on_floors else None


# Journal spots first, spawn (else summon) spots for the rest; returns (spots, missing, compared).
def boss_spots(bosses, dungeons, journal, points, summons):
    spots, missing, compared = {}, [], []
    for instance, dungeon in dungeons.items():
        taken = set()
        for name, _, npc in bosses.get(instance, []):
            spawn = boss_spawn(points, instance, npc, taken)
            taken.add(spawn)
            known = journal.get(instance, {}).get(name)
            if known and spawn:
                others = [r for r in dungeon.references if r[0] != spawn]
                compared.append((instance, name, known, dungeon.place(spawn, others)))
            spawn = spawn or boss_summon(summons, dungeon, npc)
            placed = known or (spawn and dungeon.place(spawn))
            if placed:
                spots.setdefault(instance, {})[name] = placed
            else:
                missing.append((instance, name, "no spawn" if not spawn else "no floor"))
    return spots, missing, compared


# Entrances: areatrigger_teleport targets; the first trigger is the main entrance.
def entrance_spots(db, dungeons):
    spots = {}
    for row in sorted(db["areatrigger_teleport"], key=lambda r: int(r["id"])):
        dungeon = dungeons.get(int(row["target_map"]))
        point = tuple(float(row[f"target_position_{a}"]) for a in "xyz")
        placed = dungeon and dungeon.place(point)
        if placed:
            spots.setdefault(dungeon.map_id, []).append(placed)
    return spots


QUESTIE_DUNGEON = re.compile(
    r'^\s*\[(\d+)\]\s*=\s*\{"(?:[^"\\]|\\.)*",\s*(?:nil|\{[^}]*\}),\s*(\d+),'
    r'(?:\s*\{\s*\{\s*(\d+),\s*([\d.]+),\s*([\d.]+)\s*\})?', re.M)


# Questie's dungeons.lua: {dungeon AreaID: AreaID of the zone the entrance is in}.
def questie_parent_zones(path):
    text = open(path, encoding="utf-8").read()
    return {int(m.group(1)): int(m.group(2)) for m in QUESTIE_DUNGEON.finditer(text)}


# Questie's first entrance (the cave mouth) per dungeon: {dungeon AreaID: (zone AreaID, x%, y%)}.
def questie_entrances(path):
    text = open(path, encoding="utf-8").read()
    return {int(m.group(1)): (int(m.group(3)), float(m.group(4)), float(m.group(5)))
            for m in QUESTIE_DUNGEON.finditer(text) if m.group(3)}


# {dungeon AreaID: instanceID} from Map.AreaTableID and the instances' top AreaTable rows.
def instance_of_area():
    instances = {int(r["AreaTableID"]): int(r["ID"]) for r in read_csv(WAGO, "Map")}
    instances.update({int(r["ID"]): int(r["ContinentID"]) for r in read_csv(FOREVER, "AreaTable")
                      if r["ParentAreaID"] == "0" and r["ContinentID"] not in ("0", "1")})
    return instances


# {zone AreaID: (continentID, zone as a Floor)}: the WoW Forever zone maps.
def zone_maps():
    zone_types = {r["ID"] for r in read_csv(FOREVER, "UiMap") if r["Type"] == ZONE_MAP_TYPE}
    zones = {}
    for row in read_csv(FOREVER, "UiMapAssignment"):
        if row["UiMapID"] in zone_types:
            zone = Floor(0, int(row["UiMapID"]))
            zone.rows = [([float(row[f"Region_{i}"]) for i in range(6)],
                          [float(row[c]) for c in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")], 0)]
            zones[int(row["AreaID"])] = (int(row["MapID"]), zone)
    return zones


# {instanceID: (continentID, zone as a Floor)}: the zone map holding the entrance.
def entrance_zones(questie_dungeons):
    instances, zones = instance_of_area(), zone_maps()
    return {instances[area]: zones[parent]
            for area, parent in questie_parent_zones(questie_dungeons).items()
            if area in instances and parent in zones}


# Cave mouths from Questie: {instanceID: (uiMapID, x%, y%)}.
def questie_zone_spots(dungeons, questie_dungeons):
    instances, zones = instance_of_area(), zone_maps()
    return {instances[area]: (zones[zone][1].ui_map, x, y)
            for area, (zone, x, y) in questie_entrances(questie_dungeons).items()
            if instances.get(area) in dungeons and zone in zones}


# Entrance of each of our dungeons on its zone map: {instanceID: (uiMapID, x%, y%)}.
# Questie's cave mouth where it has one, else the main portal (lowest areatrigger_teleport ID).
def entrance_zone_spots(db, dungeons, questie_dungeons):
    zones, spots = entrance_zones(questie_dungeons), questie_zone_spots(dungeons, questie_dungeons)
    triggers = {r["ID"]: r for r in read_csv(WAGO, "AreaTrigger")}
    for row in sorted(db["areatrigger_teleport"], key=lambda r: int(r["id"])):
        instance, trigger = int(row["target_map"]), triggers.get(row["id"])
        if instance in spots or instance not in dungeons or instance not in zones or not trigger:
            continue
        continent, zone = zones[instance]
        position = (float(trigger["Pos_0"]), float(trigger["Pos_1"]), float(trigger["Pos_2"]))
        spot = int(trigger["ContinentID"]) == continent and zone.spot(*position)
        if spot:
            spots[instance] = (zone.ui_map, 100 * spot[0], 100 * spot[1])
    return spots


# Quest givers/enders spawned inside a dungeon: {instanceID: [spot dict]} sorted by name.
def quest_spots(db, dungeons, points, quests):
    names = {("npc", int(r["Entry"])): r["Name"] for r in db["creature_template"]}
    names.update({("object", int(r["entry"])): r["name"] for r in db["gameobject_template"]})
    roles = {}
    for kind, table in (("npc", "creature"), ("object", "gameobject")):
        for role, suffix in (("starts", "questrelation"), ("ends", "involvedrelation")):
            for row in db[f"{table}_{suffix}"]:
                if int(row["quest"]) in quests:
                    key = (kind, int(row["id"]))
                    roles.setdefault(key, {"starts": set(), "ends": set()})[role].add(int(row["quest"]))
    spots = {}
    for key, quest_roles in roles.items():
        inside = [p for p in points.get(key, []) if p[0] in dungeons]
        if not inside:
            continue
        spawn = densest_spawn(inside)
        placed = dungeons[spawn[0]].place(spawn[1:])
        if placed:
            spots.setdefault(spawn[0], []).append(
                {"kind": key[0], "id": key[1], "name": names.get(key, "?"), "spot": placed, **quest_roles})
    return {i: sorted(s, key=lambda q: (q["name"], q["id"])) for i, s in spots.items()}


# Subzone names (WoW Forever WMOAreaTable/AreaTable) that only ever show on one floor.
def floor_areas(dungeons):
    area_names = {r["ID"]: r["AreaName_lang"] for r in read_csv(FOREVER, "AreaTable")}
    names_of_group = {}
    for row in read_csv(FOREVER, "WMOAreaTable"):
        name = row["AreaName_lang"] or area_names.get(row["AreaTableID"], "")
        if name:
            names_of_group.setdefault(int(row["WMOGroupID"]), set()).add(name)
    result = {}
    for instance, dungeon in dungeons.items():
        floors_of_name = {}
        for floor in dungeon.floors:
            for group in floor.group_ids():
                for name in names_of_group.get(group, ()):
                    floors_of_name.setdefault(name, set()).add(floor.number)
        unique = {name: min(numbers) for name, numbers in floors_of_name.items() if len(numbers) == 1}
        if len(dungeon.floors) > 1 and unique:
            result[instance] = unique
    return result


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_spot(placed):
    floor, x, y = placed
    return f"floor = {floor}, x = {round(x, 3)}, y = {round(y, 3)}"


def lua_ids(ids):
    return "{ " + ", ".join(str(i) for i in sorted(ids)) + " }" if ids else "{}"


def write_lua(name, header, body):
    lines = ["-- ForeverDungeonMap - " + header[0]] + ["-- " + h for h in header[1:]]
    lines += ["", "local _, ns = ...", ""] + body + [""]
    open(os.path.join(DATA, name), "w", encoding="utf-8", newline="\n").write("\n".join(lines))


SOURCE_LINES = [
    "GENERATED by tools/import_map_spots.py. Do not edit by hand.",
    "Sources: Blizzard's Encounter Journal and UiMapAssignment (retail, via wago.tools);",
    "spawns from CMaNGOS classic-db (GPLv3, https://github.com/cmangos/classic-db).",
]


def write_boss_positions(spots, bosses):
    body = ["ns.BOSS_POS = {"]
    for instance in sorted(spots):
        body.append(f"    [{instance}] = {{")
        for name, _, _ in bosses[instance]:
            if name in spots[instance]:
                body.append(f"        [{lua_string(name)}] = {{ {lua_spot(spots[instance][name])} }},")
        body.append("    },")
    header = ["boss positions on the dungeon map art"] + SOURCE_LINES + [
        "Journal spots first; bosses the journal lacks are placed at their spawn point.",
        "[instanceID] = { [bossName] = { floor = n, x = 0..1, y = 0..1 } }"]
    write_lua("BossPositions.lua", header, body + ["}"])


def entrance_art_lines(entrances):
    body = ["ns.ENTRANCE_ON_ART = {"]
    for instance in sorted(entrances):
        main, *others = entrances[instance]
        extra = ", others = { " + ", ".join(f"{{ {lua_spot(o)} }}" for o in others) + " }" if others else ""
        body.append(f"    [{instance}] = {{ {lua_spot(main)}{extra} }},")
    return body + ["}"]


def entrance_zone_lines(zone_entrances):
    body = ["ns.ENTRANCE_ON_ZONE = {"]
    for instance in sorted(zone_entrances):
        ui_map, x, y = zone_entrances[instance]
        body.append(f"    [{instance}] = {{ map = {ui_map}, x = {round(x, 1)}, y = {round(y, 1)} }},")
    return body + ["}"]


def quest_lines(quests):
    body = ["ns.QUEST_NPC_ON_ART = {"]
    for instance in sorted(quests):
        body.append(f"    [{instance}] = {{")
        for q in quests[instance]:
            body.append(f'        {{ kind = "{q["kind"]}", id = {q["id"]}, name = {lua_string(q["name"])}, '
                        f'{lua_spot(q["spot"])}, starts = {lua_ids(q["starts"])}, ends = {lua_ids(q["ends"])} }},')
        body.append("    },")
    return body + ["}"]


def write_dungeon_spots(entrances, zone_entrances, quests, displays):
    body = entrance_art_lines(entrances) + [""] + entrance_zone_lines(zone_entrances) + [""] + \
        quest_lines(quests) + [""] + creature_display_lines(displays)
    header = ["entrances and quest NPCs/objects on the dungeon map art"] + SOURCE_LINES + [
        "ENTRANCE_ON_ART[instanceID] = { floor, x, y, others = { {floor, x, y}, ... } }:",
        "  where you arrive through the instance portal; others = further portals (wings, back doors).",
        "ENTRANCE_ON_ZONE[instanceID] = { map = zone uiMapID, x = 0..100, y = 0..100 }: the cave",
        "  mouth from Questie's dungeons.lua (GPLv3); where Questie has none, the main portal",
        "  (lowest areatrigger_teleport ID, retail AreaTrigger) on the WoW Forever zone map.",
        "QUEST_NPC_ON_ART[instanceID] = { { kind = \"npc\"|\"object\", id, name, floor, x, y,",
        "  starts = {questIDs}, ends = {questIDs} }, ... }: quest givers/enders spawned inside.",
        "CREATURE_DISPLAY[npcID] = CreatureDisplayID for bosses/rares Generated.lua has no display",
        "  for (classic-db creature_template.ModelId1).",
        "Spots off the drawn floor of the art are moved onto it (tools/import_map_spots.py)."]
    write_lua("DungeonSpots.lua", header, body)


def write_floor_areas(areas):
    body = ["ns.FLOOR_BY_AREA = {"]
    for instance in sorted(areas):
        body.append(f"    [{instance}] = {{")
        body += [f"        [{lua_string(n)}] = {f}," for n, f in sorted(areas[instance].items())]
        body.append("    },")
    header = ["which floor of a dungeon a subzone name (GetSubZoneText) is on",
              "GENERATED by tools/import_map_spots.py. Do not edit by hand.",
              "Sources: WMOAreaTable/AreaTable of WoW Forever 1.60.1 and retail UiMapAssignment",
              "(via wago.tools). Only names that show on exactly one floor are listed.",
              "[instanceID] = { [subzoneName] = floorNumber }"]
    write_lua("FloorAreas.lua", header, body + ["}"])


# {instanceID: art name} from Dungeons.lua ("Interface\WorldMap\<art>\<art><floor>_<tile>").
def art_names():
    text = open(os.path.join(DATA, "Dungeons.lua"), encoding="utf-8").read()
    return {int(m.group(1)): m.group(2) for m in re.finditer(r'\[(\d+)\] = \{[^\n]*?art = "(\w+)"', text)}


class FloorArt:
    """Which pixels of one floor's art show drawn floor, and moving spots onto them."""

    def __init__(self, image):
        self.floor = floor_mask(image)
        self.inner = self.floor.filter(ImageFilter.MinFilter(2 * FLOOR_MARGIN + 1)).load()
        self.pixels = self.floor.load()
        self.outside = outside_region(image, self.floor).load()

    # (x, y, pixels moved) with x, y in 0..1; None when the art shows no floor near it.
    # Only a spot out on the open parchment moves: anything walled in by drawn lines may be a
    # room the detection misses.
    def snap(self, x, y):
        px, py = round(x * (ART_SIZE[0] - 1)), round(y * (ART_SIZE[1] - 1))
        if self.nearest(self.pixels, px, py, ON_FLOOR_RADIUS) or not self.outside[px, py]:
            return x, y, 0
        found = self.nearest(self.inner, px, py, MAX_MOVE)
        if not found:
            return None
        return found[0] / (ART_SIZE[0] - 1), found[1] / (ART_SIZE[1] - 1), math.dist(found, (px, py))

    def on_floor(self, x, y):
        px, py = round(x * (ART_SIZE[0] - 1)), round(y * (ART_SIZE[1] - 1))
        return bool(self.nearest(self.pixels, px, py, ON_FLOOR_RADIUS))

    # Nearest pixel set in `mask` within `radius` of (px, py), searched ring by ring.
    def nearest(self, mask, px, py, radius):
        for r in range(radius + 1):
            ring = [(px + dx, py + dy) for dx in range(-r, r + 1) for dy in (-r, r)]
            ring += [(px + dx, py + dy) for dx in (-r, r) for dy in range(-r + 1, r)]
            hits = [(math.dist(p, (px, py)), p) for p in ring
                    if 0 <= p[0] < ART_SIZE[0] and 0 <= p[1] < ART_SIZE[1] and mask[p]]
            if hits:
                return min(hits)[1]
        return None


# 255 where the art shows drawn floor: patches that differ from the parchment in colour or
# brightness and have an inked edge (stains on the parchment do not).
def floor_mask(image):
    soft = image.filter(ImageFilter.BoxBlur(2))
    parchment = parchment_colour(soft)
    mask = Image.new("L", image.size)
    mask.putdata([255 if looks_drawn(pixel, parchment) else 0 for pixel in soft.get_flattened_data()])
    mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    return keep_inked_patches(mask, image.convert("L").filter(ImageFilter.FIND_EDGES).filter(ImageFilter.BoxBlur(1)))


def lightness(pixel):
    return 0.3 * pixel[0] + 0.59 * pixel[1] + 0.11 * pixel[2] + 1e-6


# Median colour of a band just inside the frame, where every map shows bare parchment.
def parchment_colour(image):
    width, height = image.size
    band = [image.getpixel((x, y)) for y in range(0, height, 2) for x in range(0, width, 2)
            if PARCHMENT_BAND[0] <= min(x, y, width - 1 - x, height - 1 - y) <= PARCHMENT_BAND[1]]
    return tuple(statistics.median(p[i] for p in band) for i in range(3))


def looks_drawn(pixel, parchment):
    light, parchment_light = lightness(pixel), lightness(parchment)
    chroma = sum(abs(pixel[i] / light - parchment[i] / parchment_light) for i in range(3))
    lighter = light - parchment_light
    return ((chroma > FLOOR_CHROMA and lighter > -FLOOR_DARKER) or lighter > FLOOR_BRIGHT
            or (lighter > FLOOR_LIGHTER and chroma > FLOOR_TINT))


# 255 on the open parchment: what is reachable from the frame without crossing detected
# floor or a drawn (dark) line.
def outside_region(image, floor):
    light = image.convert("L").filter(ImageFilter.BoxBlur(1))
    dark_below = lightness(parchment_colour(image)) - OUTLINE_DARKER
    walls = ImageChops.lighter(light.point(lambda v: 255 if v < dark_below else 0), floor)
    region = walls.filter(ImageFilter.MaxFilter(3)).point(lambda v: 0 if v else 128)
    width, height = ART_SIZE
    edge = [(x, y) for x in range(0, width, 4) for y in (PARCHMENT_BAND[0], height - PARCHMENT_BAND[0])]
    edge += [(x, y) for y in range(0, height, 4) for x in (PARCHMENT_BAND[0], width - PARCHMENT_BAND[0])]
    for point in edge:
        if region.getpixel(point) == 128:
            ImageDraw.floodfill(region, point, 255, thresh=0)
    return region.point(lambda v: 255 if v == 255 else 0)


def keep_inked_patches(mask, edges):
    pixels = mask.load()
    for y in range(0, ART_SIZE[1], 3):
        for x in range(0, ART_SIZE[0], 3):
            if pixels[x, y] == 255:
                ImageDraw.floodfill(mask, (x, y), 100, thresh=0)
                ImageDraw.floodfill(mask, (x, y), 200 if is_inked_patch(mask, edges) else 0, thresh=0)
    return mask.point(lambda v: 255 if v == 200 else 0)


# The patch just flood-filled with 100: big enough and with a sharp edge around it.
def is_inked_patch(mask, edges):
    patch = mask.point(lambda v: 255 if v == 100 else 0)
    area = patch.histogram()[255]
    if area < FLOOR_MIN_AREA or area > FLOOR_LARGE_AREA:
        return area > FLOOR_LARGE_AREA
    rim = ImageChops.subtract(patch.filter(ImageFilter.MaxFilter(5)), patch)
    return bool(rim.histogram()[255]) and ImageStat.Stat(edges, rim).mean[0] >= FLOOR_EDGE


class ArtCheck:
    """Floor art of every dungeon floor, loaded once; moves off-floor spots onto drawn floor.
    A floor's drawn-floor detection is trusted only when every Encounter Journal spot on it
    (Blizzard's own boss skulls, always drawn on the floor) lands on detected floor and at
    least FLOOR_COVERAGE of the floor's creature spawns do."""

    def __init__(self, casc, journal, spawns):
        listing = json.load(open(WORLDMAP_FILES, encoding="utf-8"))
        self.file_ids = {path.lower(): int(file_id) for file_id, path in listing.items()}
        self.casc, self.arts, self.names, self.moves = casc, {}, art_names(), []
        self.journal, self.spawns = journal, spawns

    # The floor's art, or None when it is missing or its drawn floor is not detected reliably.
    def art(self, instance, floor):
        if (instance, floor) not in self.arts:
            art = self.load(instance, floor)
            self.arts[(instance, floor)] = art if art and self.trusted(art, instance, floor) else None
        return self.arts[(instance, floor)]

    def trusted(self, art, instance, floor):
        spots = [s for s in self.journal.get(instance, {}).values() if s[0] == floor]
        spawns = self.spawns.get((instance, floor), [])
        covered = sum(art.on_floor(x, y) for x, y in spawns)
        return all(art.on_floor(x, y) for _, x, y in spots) and covered >= FLOOR_COVERAGE * len(spawns)

    def untrusted_floors(self):
        return sorted(key for key, art in self.arts.items() if art is None)

    def load(self, instance, floor):
        name = self.names.get(instance, "").lower()
        paths = [f"interface/worldmap/{name}/{name}{floor}_{i}.blp" for i in range(1, ART_TILES + 1)]
        files = [self.casc.path(self.file_ids[p]) if p in self.file_ids else None for p in paths]
        if not name or None in files:
            return None
        image = Image.new("RGB", (ART_COLUMNS * ART_TILE, ART_TILES // ART_COLUMNS * ART_TILE))
        for i, path in enumerate(files):
            tile = Image.open(path).convert("RGB")
            image.paste(tile, (i % ART_COLUMNS * ART_TILE, i // ART_COLUMNS * ART_TILE))
        return FloorArt(image.crop((0, 0) + ART_SIZE))

    # The spot, moved onto drawn floor when it is off it (journal spots are only reported).
    def check(self, instance, label, placed, movable=True):
        art = self.art(instance, placed[0])
        snapped = art and art.snap(placed[1], placed[2])
        if not snapped or not snapped[2]:
            return placed
        self.moves.append((instance, placed[0], label, round(snapped[2]), movable))
        return (placed[0], snapped[0], snapped[1]) if movable else placed


def check_boss_spots(art, spots, journal):
    for instance, by_name in spots.items():
        for name, placed in by_name.items():
            by_name[name] = art.check(instance, name, placed, name not in journal.get(instance, {}))


# Entrances are only reported: the art draws the portal swirl there, often on the parchment.
def check_entrances(art, entrances):
    for instance, spots in entrances.items():
        entrances[instance] = [art.check(instance, f"entrance {i + 1}", s, False) for i, s in enumerate(spots)]


def check_quest_spots(art, quests):
    for instance, spots in quests.items():
        for spot in spots:
            spot["spot"] = art.check(instance, spot["name"], spot["spot"])


def print_moves(art):
    print("spots off the drawn floor (instance, floor, spot, pixels; entrances kept):")
    for instance, floor, label, distance, moved in art.moves:
        print(f"  {instance:4} f{floor} {label:32} {distance:4} px {'moved' if moved else 'kept'}")
    print("floors not checked (art missing, or a journal spot off the detected floor):",
          " ".join(f"{i}/f{f}" for i, f in art.untrusted_floors()))


# {(instanceID, floor): [(x, y)]}: every creature spawn of our dungeons on its floor's art.
def floor_spawns(db, dungeons):
    spawns = {}
    for row in db["creature"]:
        dungeon = dungeons.get(int(row["map"]))
        placed = dungeon and dungeon.place(tuple(float(row[f"position_{a}"]) for a in "xyz"))
        if placed:
            spawns.setdefault((dungeon.map_id, placed[0]), []).append(placed[1:])
    return spawns


# {npcID: displayID} of Generated.lua bosses without a display (classic-db creature_template).
def creature_displays(db):
    text = open(os.path.join(DATA, "Generated.lua"), encoding="utf-8").read()
    lacking = {int(m.group(1)) for line in text[:text.index("ns.WINGS")].splitlines()
               if "display =" not in line for m in [re.search(r"npcID = (\d+)", line)] if m}
    models = {int(r["Entry"]): int(r["ModelId1"]) for r in db["creature_template"]}
    return {npc: models[npc] for npc in sorted(lacking) if models.get(npc)}


def creature_display_lines(displays):
    return ["ns.CREATURE_DISPLAY = {"] + [f"    [{npc}] = {display}," for npc, display in displays.items()] + ["}"]


# Validation: journal spot vs the spot computed from the boss's spawn (other floor = "floor!").
def print_report(compared, missing, spots, journal):
    errors = []
    print("journal vs spawn (instance, boss, journal, spawn, error):")
    for instance, name, known, placed in compared:
        same_floor = placed is not None and placed[0] == known[0]
        if same_floor:
            errors.append(max(abs(placed[1] - known[1]), abs(placed[2] - known[2])))
        print(f"  {instance:4} {name:32} {lua_spot(known):36} {lua_spot(placed) if placed else '-':36} "
              f"{round(errors[-1], 3) if same_floor else 'floor!'}")
    print(f"same floor {len(errors)}/{len(compared)}, median error {statistics.median(errors):.3f}, "
          f"max {max(errors):.3f}")
    filled = {i: len(s) - len(journal.get(i, {})) for i, s in spots.items()}
    print("filled from spawns:", {i: n for i, n in sorted(filled.items()) if n})
    print("still missing:")
    for instance, name, why in missing:
        print(f"  {instance}: {name} ({why})")


def main():
    bosses, quests = read_generated(os.path.join(DATA, "Generated.lua"))
    casc = Casc(CASC)
    dungeons = build_dungeons(set(bosses), casc)
    db = read_classic_db(CLASSIC_DB)
    points = spawn_points(db)
    journal = journal_spots(bosses, dungeons)
    add_references(dungeons, bosses, journal, points)
    spots, missing, compared = boss_spots(bosses, dungeons, journal, points, summon_points(db))
    entrances, quest_givers, art = entrance_spots(db, dungeons), quest_spots(db, dungeons, points, quests), ArtCheck(casc, journal, floor_spawns(db, dungeons))
    check_boss_spots(art, spots, journal)
    check_entrances(art, entrances)
    check_quest_spots(art, quest_givers)
    write_boss_positions(spots, bosses)
    write_dungeon_spots(entrances, entrance_zone_spots(db, dungeons, QUESTIE_DUNGEONS), quest_givers,
                        creature_displays(db))
    write_floor_areas(floor_areas(dungeons))
    print_report(compared, missing, spots, journal)
    print_moves(art)
    if casc.missing:
        print("casc files still to download:", " ".join(str(i) for i in sorted(casc.missing)))


main()
