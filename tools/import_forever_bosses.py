"""Build ForeverDungeonMap/Data/ForeverBosses.lua: what is known of the bosses of the WoW Forever
dungeons that are not out yet, which the client data and DungeonMaster do not name: creature ID,
rank (elite / rare elite) and loot, and whether the dungeon is out.

Sources (plain game facts only, read as data, nothing in them is executed):
  * wowf.io dungeon pages https://wowf.io/en/dungeons/<slug>, saved as <wowf-dir>/<slug>.html
    (Next.js flight data): the dungeon's status and its loot list, each item with its boss;
  * mmonster.co dungeon guides https://mmonster.co/wow-forever/guides/dungeons/<slug>, saved as
    <guides-dir>/<slug>.html: they link every boss to its Wowhead NPC page (creature ID);
  * Wowhead's tooltip data of each linked NPC, saved as <tooltips-dir>/<npcID>.json from
    https://nether.wowhead.com/forever/tooltip/npc/<npcID>: name and "(Elite)" / "(Rare Elite)".

Bosses are matched by name to the encounter names of Data/Forever.lua (case, "the" and
punctuation ignored; ALIASES for the names that differ).

Usage:
    python -I tools/import_forever_bosses.py <wowf-dir> <guides-dir> <tooltips-dir> ForeverDungeonMap/Data
"""
import html
import json
import os
import re
import sys

WOWF, GUIDES, TOOLTIPS, DATA = sys.argv[1:5]

# instance ID -> (wowf.io slug, mmonster.co slug)
SLUGS = {
    2994: ("alcaz-prison", "alcaz-prison"), 2970: ("drowned-city", "the-drowned-city"),
    2974: ("blackmaw-hold", "blackmaw-hold"), 3001: ("shapers-terrace", "shapers-terrace"),
    3039: ("kroldok-stronghold", "kroldok-stronghold"),
}
# creature name -> encounter name of the client where they differ
ALIASES = {"Overlord Mugg": "Overseer Mugg", "War Handler Ashka": "Handler Ashka",
           "Deathless Guardian": "Deathless Guardians"}
# Wowhead's classification -> rank of Data/BossLevels.lua (1 elite, 2 rare elite)
RANKS = {"Elite": 1, "Rare Elite": 2}
NPC_LINK = re.compile(r'href="https://www\.wowhead\.com/forever/npc=(\d+)"')
FLIGHT_CHUNK = re.compile(r'self\.__next_f\.push\(\[1,(".*?")\]\)</script>', re.S)


def normalized(name):
    return re.sub(r"[^a-z0-9]", "", name.lower().replace("the ", ""))


# {instanceID: [encounter name]} of the Forever dungeons in Data/Forever.lua.
def forever_bosses():
    text = open(os.path.join(DATA, "Forever.lua"), encoding="utf-8").read()
    dungeons = text[text.index("    dungeons = {"):text.index("    bossDisplay = {")]
    bosses = {}
    for match in re.finditer(r"\n        \[(\d+)\] = \{ -- .*?\n        \},", dungeons, re.S):
        block = match.group(0).split("bosses = {")[1]
        bosses[int(match.group(1))] = re.findall(r'name = "((?:[^"\\]|\\.)*)"', block)
    return bosses


def read_page(directory, slug):
    path = os.path.join(directory, f"{slug}.html")
    return open(path, encoding="utf-8").read() if os.path.exists(path) else None


# (status, {boss name: [itemID]}) from a saved wowf.io dungeon page; trash loot is left out.
def wowf_facts(slug):
    page = read_page(WOWF, slug)
    if not page:
        return None, {}
    flight = "".join(json.loads(chunk) for chunk in FLIGHT_CHUNK.findall(page))
    status = re.search(r'"id":"%s"[^{}]*?"status":"(\w+)"' % re.escape(slug), flight)
    start = flight.find('"loot":[')
    loot = {}
    for item in json.JSONDecoder().raw_decode(flight[start + len('"loot":'):])[0] if start >= 0 else []:
        boss = item.get("boss")
        if isinstance(boss, str) and not boss.startswith("$") and item["id"] not in loot.get(boss, []):
            loot.setdefault(boss, []).append(item["id"])
    return status and status.group(1), loot


# (name, rank) from a saved tooltip, rank None when the creature is no elite.
def tooltip_facts(npc):
    path = os.path.join(TOOLTIPS, f"{npc}.json")
    if not os.path.exists(path):
        return None, None
    tooltip = json.load(open(path, encoding="utf-8"))
    classification = re.search(r"\((Rare Elite|Elite)\)", tooltip.get("tooltip", ""))
    return html.unescape(tooltip.get("name") or ""), classification and RANKS[classification.group(1)]


# {boss name: {"npcID": n, "rank": r}} of one dungeon's guide page.
def guide_facts(slug, by_key):
    page = read_page(GUIDES, slug) or ""
    facts = {}
    for npc in dict.fromkeys(int(n) for n in NPC_LINK.findall(page)):
        name, rank = tooltip_facts(npc)
        boss = by_key.get(normalized(ALIASES.get(name, name)))
        if boss and rank and boss not in facts:
            facts[boss] = {"npcID": npc, "rank": rank}
    return facts


# {"status": s, "bosses": {name: {npcID, rank, loot}}} of one dungeon.
def dungeon_facts(instance, names):
    wowf_slug, guide_slug = SLUGS[instance]
    by_key = {normalized(name): name for name in names}
    bosses = guide_facts(guide_slug, by_key)
    status, loot = wowf_facts(wowf_slug)
    for boss_name, items in loot.items():
        boss = by_key.get(normalized(ALIASES.get(boss_name, boss_name)))
        if boss:
            bosses.setdefault(boss, {})["loot"] = items
    return {"status": status, "bosses": {name: bosses[name] for name in names if name in bosses}}


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_boss(boss, fact):
    fields = [f"{key} = {fact[key]}" for key in ("npcID", "rank") if key in fact]
    if fact.get("loot"):
        fields.append("loot = { " + ", ".join(str(item) for item in fact["loot"]) + " }")
    return f"            [{lua_string(boss)}] = {{ {', '.join(fields)} }},"


def write(facts):
    lines = [
        "-- ForeverDungeonMap - bosses of the WoW Forever dungeons that are not out yet",
        "-- GENERATED by tools/import_forever_bosses.py. Do not edit by hand.",
        "-- Sources: wowf.io dungeon pages (status, loot per boss), mmonster.co dungeon guides",
        "-- (boss -> Wowhead NPC link) and Wowhead's NPC tooltips (Elite / Rare Elite); plain game facts.",
        "-- [instanceID] = { comingSoon = true | false, bosses = { [bossName] = { npcID = creature ID,",
        "--   rank = 1 elite | 2 rare elite, loot = { itemID, ... } } } }",
        "",
        "local _, ns = ...",
        "",
        "ns.FOREVER_BOSSES = {",
    ]
    for instance in sorted(facts):
        lines.append(f"    [{instance}] = {{")
        if facts[instance]["status"]:
            lines.append(f"        comingSoon = {'true' if facts[instance]['status'] == 'soon' else 'false'},")
        lines.append("        bosses = {")
        lines += [lua_boss(boss, fact) for boss, fact in facts[instance]["bosses"].items()]
        lines += ["        },", "    },"]
    lines.append("}")
    path = os.path.join(DATA, "ForeverBosses.lua")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def main():
    bosses = forever_bosses()
    facts = {instance: dungeon_facts(instance, bosses.get(instance, [])) for instance in SLUGS}
    write(facts)
    for instance, fact in sorted(facts.items()):
        names = bosses.get(instance, [])
        no_npc = [name for name in names if "npcID" not in fact["bosses"].get(name, {})]
        no_loot = [name for name in names if not fact["bosses"].get(name, {}).get("loot")]
        print(instance, fact["status"], "without creature ID:", no_npc, "without loot:", no_loot)


main()
