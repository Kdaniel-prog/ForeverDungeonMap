"""Build the map floors and boss spots of the WoW Forever dungeons (JSON, merged into
Data/Forever.lua by import_forever.py --maps).

The client has no UiMap for any Forever dungeon (UiMap.db2 of 1.60.1.70938 has 61 rows, none
for these instances), but it ships two kinds of art that show them:
  * minimap tiles of the dungeon's own map: the WDT (Map.WdtFileDataID) lists one 512x512
    minimap texture per ADT tile (MAID chunk, 8th FileDataID). A floor is a crop of that grid,
    drawn as square pieces (FileDataID + top-left corner on the 1002x668 canvas, one size).
  * retail world map tiles of a place the dungeon reuses: City of Dalaran is the Northrend
    Dalaran (retail UiMap 125 "Dalaran" and 126 "The Underbelly", Interface\\WorldMap\\Dalaran).
Boss spots: the pins of https://foreverchanges.pro/dungeons/<slug> (positions only, plain game
facts) sit on hand-drawn maps by Santiago Reyes; they are carried onto our art through landmarks
measured on both images (affine fit + inverse-distance correction). The fan maps themselves are
never shipped or read at runtime.

Usage:
    python -I tools/make_forever_maps.py <Map.csv> <wdt-dir> <web-dir> <out.json>
<wdt-dir> holds the WDT files as <WdtFileDataID>.wdt (or .bin), downloaded from
https://wago.tools/api/casc/<fdid>?download&version=1.60.1.70938; <web-dir> the saved
foreverchanges pages fc_<slug>.html (as for import_forever.py). Inputs are read as data only.
"""
import csv
import json
import os
import re
import struct
import sys

MAP_CSV, WDT_DIR, WEB_DIR, OUT = sys.argv[1:5]

# Map art canvas of the addon and the fan maps (pixels)
CANVAS_WIDTH, CANVAS_HEIGHT = 1002, 668
FAN_WIDTH, FAN_HEIGHT = 2100, 1400
# Every minimap texture of these maps is 512x512 (measured on all 154 tiles); one ADT tile = 533.33 yards
MINIMAP_TILE_PIXELS = 512
ADT_YARDS = 1600 / 3

# Floors per dungeon, in floor order. A "minimap" floor is a 3:2 view of the minimap grid,
# given as (left, top, width) in pixels of the grid whose top-left is the map's first ADT tile
# ("whole" = every tile).
# A "tiles" floor is a 4x3 world map tile set the client ships.
DUNGEON_FLOORS = {
    2959: [
        {"name": "The Underbelly", "tiles": "Interface\\WorldMap\\Dalaran\\Dalaran2_", "retailUiMap": 126, "fan": "city-of-dalaran-sewers"},
        # retail art: its west (Violet Citadel) is north in the dungeon (seen on the dungeon's minimap)
        {"name": "Dalaran", "tiles": "Interface\\WorldMap\\Dalaran\\Dalaran1_", "retailUiMap": 125, "fan": "city-of-dalaran-city"},
    ],
    2998: [{"name": "Excavation Site", "minimap": (948, 1348, 1000), "fan": "excavation-site"}],
    2999: [{"name": "Ruins of Lordaeron", "minimap": (365, 735, 870), "fan": "ruins-of-lordaeron"}],
    3065: [{"name": "The Hall of Thanes", "minimap": (1995, 2965, 1140), "fan": "hall-of-thanes"}],
    # not released yet: views picked by eye around the built part of the map, no boss spots
    2970: [{"name": "The Drowned City", "minimap": (690, 545, 1500)}],
    2974: [{"name": "Blackmaw Hold", "minimap": (-5, 123, 1850)}],
    2994: [{"name": "Alcaz Prison", "minimap": (113, 164, 345)}],
    3001: [{"name": "The Shaper's Terrace", "minimap": (0, 400, 2048)}],
    3039: [{"name": "Krol'dok Stronghold", "minimap": "whole"}],
}

# foreverchanges.pro page slug per dungeon; "fan" in a floor is the file name of its fan map
FAN_PAGES = {2959: "city-of-dalaran", 2998: "excavation-site", 2999: "ruins-of-lordaeron", 3065: "hall-of-thanes"}

# Landmarks per fan map, measured by eye on gridded crops: (fan map pixel) -> (our art pixel). Art pixels
# are minimap grid pixels for minimap floors and 1002x668 pixels for tile floors.
LANDMARKS = {
    "city-of-dalaran-sewers": [  # retail Underbelly art: the fan map is a trace of it
        ((1012, 606), (430, 257)), ((1137, 712), (493, 310)), ((1281, 825), (550, 343)),
        ((1437, 262), (617, 100)), ((506, 656), (220, 287)), ((1562, 756), (673, 330)),
    ],
    "city-of-dalaran-city": [  # retail Dalaran art, turned 90 degrees on the fan map
        ((1096, 1176), (727, 305)), ((756, 1154), (719, 498)), ((1100, 360), (238, 305)),
        ((819, 472), (327, 463)), ((1131, 760), (492, 294)),
    ],
    "ruins-of-lordaeron": [
        ((1100, 698), (792, 1005)), ((790, 690), (647, 1001)), ((1410, 690), (935, 1003)),
        ((790, 390), (650, 865)), ((1415, 392), (935, 867)), ((1100, 300), (792, 825)),
        ((722, 898), (617, 1096)),
    ],
    "excavation-site": [
        ((168, 651), (1056, 1656)), ((220, 851), (1081, 1749)), ((790, 893), (1342, 1767)),
        ((764, 1016), (1331, 1822)), ((1418, 640), (1647, 1656)), ((924, 588), (1409, 1600)),
    ],
    "hall-of-thanes": [
        ((1068, 233), (2560, 3243)), ((1068, 934), (2560, 3532)), ((1068, 1152), (2560, 3618)),
        ((1068, 714), (2560, 3443)), ((724, 934), (2412, 3532)), ((1428, 934), (2705, 3532)),
        ((1470, 651), (2737, 3414)), ((1068, 1328), (2560, 3689)),
    ],
}


def read_chunks(data):
    """(tag, body) of every chunk of a WDT/ADT file."""
    offset = 0
    while offset + 8 <= len(data):
        tag = data[offset:offset + 4][::-1].decode("latin1")
        size = struct.unpack_from("<I", data, offset + 4)[0]
        yield tag, data[offset + 8:offset + 8 + size]
        offset += 8 + size


def minimap_tiles(wdt_file_id):
    """{(tileX, tileY): minimap FileDataID} of a WDT."""
    for extension in (".wdt", ".bin"):
        path = os.path.join(WDT_DIR, f"{wdt_file_id}{extension}")
        if os.path.exists(path):
            chunks = dict(read_chunks(open(path, "rb").read()))
            break
    else:
        raise FileNotFoundError(f"WDT {wdt_file_id} missing in {WDT_DIR}")
    tiles = {}
    for index in range(4096):
        if struct.unpack_from("<I", chunks["MAIN"], index * 8)[0] & 1:
            minimap = struct.unpack_from("<8I", chunks["MAID"], index * 32)[7]
            if minimap:
                tiles[(index % 64, index // 64)] = minimap
    return tiles


def minimap_floor(tiles, view):
    """Pieces [fileID, left, top] in canvas pixels, piece size and world bounds of a 3:2 minimap view."""
    grid_x = min(x for x, _ in tiles)
    grid_y = min(y for _, y in tiles)
    left, top, width = view
    height = width * CANVAS_HEIGHT / CANVAS_WIDTH
    scale = CANVAS_WIDTH / width
    pieces = []
    for (tile_x, tile_y), file_id in sorted(tiles.items(), key=lambda item: (item[0][1], item[0][0])):
        x = (tile_x - grid_x) * MINIMAP_TILE_PIXELS - left
        y = (tile_y - grid_y) * MINIMAP_TILE_PIXELS - top
        if x < width and y < height and x + MINIMAP_TILE_PIXELS > 0 and y + MINIMAP_TILE_PIXELS > 0:
            pieces.append([file_id, round(x * scale, 2), round(y * scale, 2)])
    yards_per_pixel = ADT_YARDS / MINIMAP_TILE_PIXELS
    max_x = (32 - grid_y) * ADT_YARDS - top * yards_per_pixel
    max_y = (32 - grid_x) * ADT_YARDS - left * yards_per_pixel
    world = {"minX": round(max_x - height * yards_per_pixel, 1), "minY": round(max_y - width * yards_per_pixel, 1),
             "maxX": round(max_x, 1), "maxY": round(max_y, 1)}
    return pieces, round(MINIMAP_TILE_PIXELS * scale, 2), world


def solve3(matrix, vector):
    """Solve a 3x3 linear system (Cramer's rule)."""
    def det(m):
        return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    whole = det(matrix)
    result = []
    for column in range(3):
        replaced = [[vector[row] if c == column else matrix[row][c] for c in range(3)] for row in range(3)]
        result.append(det(replaced) / whole)
    return result


def fit_affine(pairs):
    """Least-squares affine map fan pixel -> art pixel; returns a function."""
    normal = [[0.0] * 3 for _ in range(3)]
    right_x, right_y = [0.0] * 3, [0.0] * 3
    for (fx, fy), (ax, ay) in pairs:
        row = (fx, fy, 1.0)
        for i in range(3):
            for j in range(3):
                normal[i][j] += row[i] * row[j]
            right_x[i] += row[i] * ax
            right_y[i] += row[i] * ay
    cx, cy = solve3(normal, right_x), solve3(normal, right_y)
    return lambda x, y: (cx[0] * x + cx[1] * y + cx[2], cy[0] * x + cy[1] * y + cy[2])


def fit_landmarks(pairs):
    """Affine fit plus inverse-distance correction so every landmark maps exactly (hand-drawn maps bend)."""
    affine = fit_affine(pairs)
    residuals = [((fx, fy), (ax - affine(fx, fy)[0], ay - affine(fx, fy)[1])) for (fx, fy), (ax, ay) in pairs]

    def transform(x, y):
        base_x, base_y = affine(x, y)
        total_weight, shift_x, shift_y = 0.0, 0.0, 0.0
        for (fx, fy), (dx, dy) in residuals:
            distance_squared = (x - fx) ** 2 + (y - fy) ** 2
            if distance_squared < 1e-6:
                return base_x + dx, base_y + dy
            weight = 1 / distance_squared
            total_weight += weight
            shift_x += weight * dx
            shift_y += weight * dy
        return base_x + shift_x / total_weight, base_y + shift_y / total_weight
    return transform


def fan_pins(slug):
    """{fan map file name: [pin]} from a saved foreverchanges.pro page (Next.js flight data)."""
    if not slug:
        return {}
    page = open(os.path.join(WEB_DIR, f"fc_{slug}.html"), encoding="utf-8").read()
    flight = "".join(json.loads(c) for c in re.findall(r'self\.__next_f\.push\(\[1,(".*?")\]\)</script>', page, re.S))
    start = flight.find('{"map":{"by"')
    floors = json.JSONDecoder().raw_decode(flight[start:])[0]["map"]["floors"]
    return {floor["src"].rsplit("/", 1)[-1].rsplit(".", 1)[0]: floor["pins"] for floor in floors}


def art_percent(floor, point):
    """Art pixel -> percent of the floor canvas."""
    x, y = point
    if "minimap" in floor:
        left, top, width = floor["minimap"]
        height = width * CANVAS_HEIGHT / CANVAS_WIDTH
        return round((x - left) / width * 100, 1), round((y - top) / height * 100, 1)
    return round(x / CANVAS_WIDTH * 100, 1), round(y / CANVAS_HEIGHT * 100, 1)


def whole_grid_view(tiles):
    """(left, top, width) of a 3:2 view around every minimap tile of the map."""
    columns = max(x for x, _ in tiles) - min(x for x, _ in tiles) + 1
    rows = max(y for _, y in tiles) - min(y for _, y in tiles) + 1
    width = max(columns, rows * CANVAS_WIDTH / CANVAS_HEIGHT) * MINIMAP_TILE_PIXELS
    height = width * CANVAS_HEIGHT / CANVAS_WIDTH
    return (round((columns * MINIMAP_TILE_PIXELS - width) / 2), round((rows * MINIMAP_TILE_PIXELS - height) / 2), round(width))


def floor_record(instance_id, wdt_file_id, floor):
    """Floor as written to Data/Forever.lua (tile set or minimap pieces)."""
    record = {"name": floor["name"], "kind": "dungeon"}
    if "tiles" in floor:
        record.update(tiles=floor["tiles"], retailUiMap=floor["retailUiMap"], verified=True)
        return record
    tiles = minimap_tiles(wdt_file_id)
    if floor["minimap"] == "whole":
        floor["minimap"] = whole_grid_view(tiles)
    record["pieces"], record["pieceSize"], world = minimap_floor(tiles, floor["minimap"])
    record["world"] = dict(map=instance_id, **world)
    return record


def largest_affine_error(pairs):
    """Largest landmark miss of the plain affine fit (pixels): how much the fan map bends."""
    affine = fit_affine(pairs)
    return round(max(((ax - affine(fx, fy)[0]) ** 2 + (ay - affine(fx, fy)[1]) ** 2) ** 0.5
                     for (fx, fy), (ax, ay) in pairs), 1)


def place_pins(result, floor_number, floor, pins):
    """Boss and entrance pins of one fan map, carried onto the floor art."""
    transform = fit_landmarks(LANDMARKS[floor["fan"]])
    for pin in pins:
        x, y = art_percent(floor, transform(pin["x"] / 100 * FAN_WIDTH, pin["y"] / 100 * FAN_HEIGHT))
        if pin.get("kind") == "entrance":
            result["entrance"] = {"floor": floor_number, "x": x, "y": y}
        elif pin.get("boss"):
            result["bosses"][pin["label"]] = {"floor": floor_number, "x": x, "y": y, "roams": bool(pin.get("roams"))}


def build_dungeon(instance_id, wdt_file_id):
    """Floors, boss spots and entrance spot of one dungeon."""
    result = {"floors": [], "bosses": {}, "landmarkError": {}}
    pins_by_fan_map = fan_pins(FAN_PAGES.get(instance_id))
    for floor_number, floor in enumerate(DUNGEON_FLOORS[instance_id], 1):
        result["floors"].append(floor_record(instance_id, wdt_file_id, floor))
        if floor.get("fan"):
            result["landmarkError"][floor_number] = largest_affine_error(LANDMARKS[floor["fan"]])
            place_pins(result, floor_number, floor, pins_by_fan_map.get(floor["fan"], []))
    return result


def main():
    wdt_ids = {int(row["ID"]): int(row["WdtFileDataID"]) for row in csv.DictReader(open(MAP_CSV, encoding="utf-8"))}
    dungeons = {instance_id: build_dungeon(instance_id, wdt_ids[instance_id]) for instance_id in DUNGEON_FLOORS}
    json.dump({"source": "tools/make_forever_maps.py", "dungeons": dungeons}, open(OUT, "w", encoding="utf-8"), indent=1)
    for instance_id, dungeon in dungeons.items():
        print(instance_id, "floors", len(dungeon["floors"]), "pieces", [len(f.get("pieces", [])) for f in dungeon["floors"]],
              "bosses", len(dungeon["bosses"]), "affine error px", dungeon["landmarkError"])


main()
