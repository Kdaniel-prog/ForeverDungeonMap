"""Boss, rare and entrance spots and the quests of the WoW Forever dungeons from forg.gg's dungeon pages
(https://forg.gg/en/forever/dungeons/<slug>), for tools/import_dungeon_journey.py.

Input: <forg-dir>/<slug>.json, the map object of a saved page (its Next.js flight data, the object that
holds "floors", "steps", "entrance" and "quests"), read as data only. Positions there are pixels of
forg.gg's floor pictures; FITS carries them onto our floor art (Data/Forever.lua, 1002x668 canvas):
our pixel = scale * theirs + (x, y), found by fitting each picture onto our art (the minimap pictures
by colour, the drawn ones by the shape of their floors; every pin checked to land in its room). The
pictures themselves are not shipped.
"""
import json
import os
import re

CANVAS_WIDTH, CANVAS_HEIGHT = 1002, 668
SLUGS = {2994: "alcaz-prison", 3039: "kroldok-stronghold", 3001: "shapers-terrace", 2974: "blackmaw-hold",
         2970: "drowned-city"}
# instance -> { forg.gg floor: (scale, x, y, approximate) } onto our floor 1
FITS = {
    2994: {1: (0.935206, 172, 15, False), 2: (0.954719, 168, 7, False)},
    3039: {1: (0.358194, 243, 104, False)},
    3001: {1: (0.442922, 295, 33, False)},
    2974: {1: (0.339548, 164, 140, False)},
}
# Cave levels no art of ours shows (Blackmaw Hold's floors 2-6): each is laid on the floor it is
# entered from, its way in on that floor's way out, at that floor's scale times this ratio. Only a
# rough guess (floor 2 looks drawn at floor 1's scale, the deeper ones at about twice the detail),
# so their spots are marked approximate. instance -> { floor: ratio }
CAVE_FLOORS = {2974: {2: 1.0, 3: 0.5, 4: 0.5, 5: 0.5, 6: 0.5}}
# forg.gg quest start "Name · Zone 12.3, 45.6"; zone names of forg.gg that differ from ours
START_SPOT = re.compile(r"^(?:Starts: )?(.+?) · (.+?)(?: (\d+(?:\.\d+)?), (\d+(?:\.\d+)?))?$")
START_ITEM = re.compile(r'^Starts from the item "(.+)"$')
ZONE_NAMES = {"The Riverglades": "Riverglades"}
SIDES = {"alliance": "Alliance", "horde": "Horde"}


def load(forg_dir, instance_id):
    path = os.path.join(forg_dir, "%s.json" % SLUGS[instance_id])
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else None


def art_spot(fit, at):
    scale, x, y, approximate = fit
    spot = {"floor": 1, "x": round((scale * at["x"] + x) / CANVAS_WIDTH * 100, 1),
            "y": round((scale * at["y"] + y) / CANVAS_HEIGHT * 100, 1)}
    if approximate:
        spot["approx"] = True
    return spot


def way_out(data, floor_number):
    """(floor it is entered from, the spot there) of a floor, from the other floors' links."""
    for floor in data["floors"]:
        for link in floor.get("links") or []:
            if link["to"] == floor_number and floor["n"] != floor_number:
                return floor["n"], link["at"]
    return None, None


def chain_caves(data, fits, ratios):
    """Fits of the cave floors, each laid on the floor it is entered from (see CAVE_FLOORS)."""
    fits = dict(fits)
    for floor_number in sorted(ratios):
        source, exit_spot = way_out(data, floor_number)
        floor = data["floors"][floor_number - 1]
        if source not in fits or not floor.get("route"):
            continue
        arrival = floor["route"][0]["points"][0]
        scale, x, y, _ = fits[source]
        own = scale * ratios[floor_number]
        fits[floor_number] = (own, scale * exit_spot["x"] + x - own * arrival["x"],
                              scale * exit_spot["y"] + y - own * arrival["y"], True)
    return fits


def map_spots(forg_dir, aliases):
    """instance -> { bosses = { name = spot }, entrance = spot, rares = [name] } of the fitted floors."""
    spots = {}
    for instance_id, fits in FITS.items():
        data = load(forg_dir, instance_id)
        if not data:
            continue
        fits = chain_caves(data, fits, CAVE_FLOORS.get(instance_id, {}))
        bosses, rares = {}, []
        for step in data["steps"]:
            fit = fits.get(step["floor"])
            if step.get("at") and fit and step["kind"] in ("boss", "rare"):
                name = aliases.get(step["title"], step["title"])
                bosses[name] = art_spot(fit, step["at"])
                if step["kind"] == "rare":
                    rares.append(name)
        entrance = data.get("entrance")
        fit = entrance and fits.get(entrance["floor"])
        spots[instance_id] = {"bosses": bosses, "rares": rares, "entrance": fit and art_spot(fit, entrance["at"])}
    return spots


def start_location(text, dungeon_name, zone_maps):
    """Location record of a forg.gg start text, or None."""
    if not text:
        return None
    item = START_ITEM.match(text)
    if item:
        return {"kind": "item", "name": item.group(1), "inside": dungeon_name}
    match = START_SPOT.match(text)
    if not match:
        return None
    name, zone, x, y = match.groups()
    if zone == "inside the dungeon":
        return {"kind": "npc", "name": name, "inside": dungeon_name}
    ui_map = zone_maps(ZONE_NAMES.get(zone, zone))
    record = {"kind": "npc", "name": name}
    if ui_map and x:
        record.update(map=ui_map, x=float(x), y=float(y))
    else:
        record["note"] = zone
    return record


def quest_facts(quest, instance_id, dungeon_name, zone_maps):
    """A forg.gg quest in the shape of import_dungeon_journey.py's entries."""
    items = [reward["id"] for reward in quest.get("rewards") or [] if reward.get("id")]
    before = [step["id"] for group in (quest.get("before") or {}).get("steps", []) for step in group]
    return {"dungeon": instance_id, "name": quest["name"], "faction": SIDES.get(quest.get("side")),
            "lvl": quest.get("level"), "req": quest.get("minLevel"), "objective": quest.get("objective"),
            "start": start_location(quest.get("start"), dungeon_name, zone_maps),
            "choices": items if quest.get("choose") else None, "rewards": None if quest.get("choose") else items,
            "pre": before, "next": []}


def quests(forg_dir, dungeon_names, zone_maps):
    """questID -> forg.gg facts of every quest the five dungeon pages list."""
    found = {}
    for instance_id in SLUGS:
        data = load(forg_dir, instance_id)
        for quest in (data or {}).get("quests", []):
            if isinstance(quest, dict) and quest.get("id"):
                found[quest["id"]] = quest_facts(quest, instance_id, dungeon_names[instance_id], zone_maps)
    return found
