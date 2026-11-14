# Forever Dungeon Map – terv

> **v0.7.1 (2026-11-13)** – játékos visszajelzés: quest-pergamen kivágva (`TEX.PARCHMENT_COORDS`), boss-pinek gyűrű nélkül (csak portré / X / „?”), „Show on Map” és quest-pin kattintás = beépített waypoint + navigációs nyíl (`ns.SetWaypoint`), Shift-klikk = journal. run_all 20/20 zöld, telepítve.
>
> **v0.7.0 (2026-11-13) – kész, telepítve, `tools/harness/run_all.py` ALL GREEN (20/20, 4 nyelv teljes).**
> Spec: `docs/ui-spec.md` (P0+P1+P2 kész). Taint: `docs/taint-report.md`. Kiadás: `.pkgmeta`, `.github/workflows/release.yml`,
> `CHANGELOG.md`, `docs/curseforge-description.md`. Játékbeli ellenőrzés: `docs/ingame-test-checklist.md`.
> Owner TODO: CurseForge projekt + `## X-Curse-Project-ID`, `## Version: @project-version@`, repo secrets, screenshotok.
>
> **v0.5.0 (2026-11-13):** Journal újraírva (Theme.lua színtémák, Canvas.lua fix magasságú sorok, pergamen quest-lap,
> Starts at / Turn in / chain / reward-rács, faction-szűrő, kereső, TomTom waypoint). Adat: `Data/QuestInfo.lua`
> (QuestieDB, 432 quest), `Data/BossLevels.lua` (QuestieDB), `Data/Art.lua` (`tools/make_art.py`: EJ kártya/lore,
> töltőképernyők, 148 EJ boss-kép, FileDataID-k a wowf buildből a wago.tools listából). Taint-fix: pin
> SetPassThroughButtons no-op. Élő nézet: DIALOG strata + harc-biztos.
>
> **v0.3.0 (2026-11-13):** boss-helyek alapból: Blizzard Encounter Journal (retail JournalEncounter via wago.tools,
> `tools/import_boss_positions.py`, 112 boss / 15 dungeon) + futásidőben a ForeverDungeonJournal adatai, ha fent van
> (`Compat_FDJ.lua`: boss-hely, bejárat, új Forever dungeonök térképe; semmit nem másolunk át). Kézi rögzítő kivéve.
> Oldalpanel a quest log helyén: boss → loot + kapcsolódó questek; quest → cél, kezdő NPC, lánc, jutalmak.
> Élő nézet: nincs +/−, magassága = térkép-ablak. Megölt boss X-szel, /reload után is megmarad.
>
> **v0.2.0:** megírva, játékban tesztelésre vár. UI-terv: `docs/ui-mockup.html`.
> Benne: dungeon art nézet (szintek/wingek, zoom, húzás), boss-portrék a térképen + loot-ablak,
> oldalsáv Bossok/Questek (frakció-ikon, lánc-ikon, állapot), külön mozgatható élő nézet a térkép mellett
> (terep-gomb nélkül), Dungeon Journal (kártyák, LFG/EJ képek, szintszín), boss-hely rögzítő
> (boss halála után klikk a térképen, Shift-klikk kézzel), quest giver megjelölése a zónatérképen,
> jobb klikk = egy szinttel kijjebb, bejárat-pinek. Adat: `tools/import_dungeonmaster.py` → `Data/Generated.lua`
> (23 dungeon, 207 boss, 334 quest). Ikonok: `tools/make_icons.py`.
> Nyitott: barlang-ikonok (probe `/fdm pois`), boss-pozíciók gyűjtése, új Forever dungeonök artja,
> ütközés a ForeverDungeonJournal világtérkép-rétegével.

Cél: WoW Forever kliensen a nagy térkép (M) dungeonben a dungeon térképét mutassa, natív (retail-szerű) érzéssel:
saját és csapattárs pöttyök névvel hoverre, boss pinek lootokkal, dungeon questek, ki/be navigálás bal/jobb klikkel.
Kiadás: CurseForge.

---

## 1. Amit a telepítés vizsgálata megmutatott (B:\World of Warcraft)

| Tény | Érték / következmény |
|---|---|
| Termék | `wowf` (WoW Forever), hivatalos Blizzard kliens, mappa: `_forever_` |
| Kliens verzió | 1.60.1.70938 → **`## Interface: 16001`** |
| Belső kódnév | **Camelot** (TOC suffix: `_Camelot.toc`, `AllowLoadGameType: camelot`) |
| UI motor | Modern (retail-alapú) UI: `WorldMapFrame` = MapCanvas, `ScrollContainer`, `NavBar`, `C_Map`, `Settings` API, Addon Compartment, `SettingsDropdownWithButtonsTemplate` |
| Nyelv | **Lua 5.1** (WoW-dialektus) + opcionálisan **XML** a frame-templatekhez + **`.toc`** manifest. Más nyelv nem jöhet szóba. |
| Klasszikus dungeonök térképe | A kliensben **van** art hozzájuk (`Interface\WorldMap\<Név>\...` tile-ok, `C_Map.GetMapArtLayers` ad vissza layert), csak a térkép nem vált át rájuk automatikusan |
| Új Forever dungeonök | City of Dalaran, Excavation Site: Wetlands, Ruins of Lordaeron, Hall of the Thanes, The Drowned City, Krol'dok Stronghold, Shaper's Terrace, Alcaz Prison, Blackmaw Hold (+ esetleg több) → **nincs** hozzájuk natív térkép art |

### Meglévő hasonló addonok és mi a bajuk

| Addon | Mit csinál | Gyengeség (amiből tanulunk) |
|---|---|---|
| **MapUtils** (D4KiR, GPLv3, CurseForge 1463967) | Dungeon map art, entrance pinek | **Globálisan felülírja** a `C_Map.GetMapArtLayers/Textures` függvényeket → taint-veszély, ütközik más addonokkal. Új dungeonökhöz harmadik féltől származó artot használ ("Atlas de Azeroth: Forever"). Játékospozíció nincs. |
| **ForeverDungeonJournal** (Exehn) | Journal + egy saját panelt **ráhúz** a WorldMapFrame-re | Overlay-hack: a natív pinek, pan/zoom, player layer fölé tesz egy fekete hátteret. Nem a térkép része, nincs player pötty, nincs csapat. Adatai (bossok, loot, questek) jók. |
| **DungeonMaster** (MalkDev, GPLv3) | Journal: questek, bossok, loot | Nem térkép. cMaNGOS-ból generált questadat. |
| Questie / QuestieDB | Questadatbázis | Opcionális függőségként használható a questekhez. |

**Következtetés:** egyik sem integrálódik *rendesen* a MapCanvas-ba, és egyik sem mutat játékost/csapatot a dungeon térképen. Ez a mi rést.

---

## 2. Kritikus technikai kérdés: a pozíciók (ezt KELL először tesztelni)

Modern kliensekben a Blizzard instance-on belül **korlátozza** a pozíció API-kat az addonoknak:
- `UnitPosition("party1")` instance-ban általában `nil`.
- `C_Map.GetPlayerMapPosition(mapID, "player")` működhet, ha a dungeonnek van uiMapID-ja + map assignmentje.
- A Blizzard saját `GroupMembersDataProvider`-e (C++ `UnitPositionFrame`) viszont **mégis kirajzolja** a csapattársakat, hover-tooltippel együtt → ha natív uiMap-et mutatunk, a csapatpöttyök **ingyen** jönnek, pont úgy, mint retailen.

Ezért az **1. fázis egy próba (probe) addon**, ami dungeonben kiírja:
1. `GetInstanceInfo()` → instanceID
2. `C_Map.GetBestMapForUnit("player")` → kapunk-e dungeon uiMapID-t?
3. `C_Map.GetPlayerMapPosition(id, "player")` → van-e koordináta?
4. `UnitPosition("player")` és `UnitPosition("party1")` → nil vagy szám?
5. `C_Map.GetMapInfo(id)` (mapType, parentMapID), `C_Map.GetMapGroupID` (emeletek)
6. Látszanak-e a natív party pöttyök, ha kézzel `WorldMapFrame:SetMapID(dungeonMapID)`.

A teszt eredménye dönti el, melyik ágat építjük:

| Eset | Megoldás |
|---|---|
| **A)** Van uiMap + működik a natív pozíció | Csak `SetMapID` → minden natív (pötty, hover, emeletválasztó, jobb klikk = ki). Legszebb. |
| **B)** Van uiMap art, de nincs pozíció | Natív térkép + saját pinek; player pötty `UnitPosition("player")`-ből kalibrált transzformációval (ha az működik); csapat: addon-üzenet (`C_ChatInfo.SendAddonMessage`), amiben mindenki elküldi a saját pozícióját (csak akkor megy, ha nekik is fent van az addon). |
| **C)** Nincs uiMap (új Forever dungeonök) | Saját art + saját MapCanvas-szerű nézet (lásd 3.3), pozíció B) szerint. Ha `UnitPosition` sincs instance-ban → csak bossok/questek, pötty nélkül (ezt őszintén jelezni kell). |

### 2.1 Probe EREDMÉNY (2026-11-13, Wailing Caverns, 5 fős party)
- `UnitPosition` instance-ban **nil** a playerre ÉS a party tagokra (kint a világban működik).
- `C_Map.GetBestMapForUnit` instance-ban **nil**; a név alapú uiMap keresés nem talált térképet.
- → **Nincs pozíció az addonnak dungeonben.** Addon-üzenetes pozíció-szinkron sem megoldás (nincs mit küldeni).
- ✅ A **Minimap** (C++ rajzolja) dungeonben is kirajzolja az alaprajzot; felnagyítható (600×600),
  négyzetes maszk, elrejthető keret/gombok, kattintható. Max. kizoomolás = natív zoom 0 (beltéri) → nem az egész dungeon.
- ✅ A klasszikus dungeon art kirajzolható közvetlenül a fájlokból (`Interface\WorldMap\WailingCaverns\WailingCaverns1_1..12`).
- ✅ Visszaállítás reload nélkül működik (kerek maszk visszaállítása + zoom nudge után).
- ✅ Csapattárs pöttyök látszanak a nagy minimapon (felhasználó tesztelte csapatban).
- ❌ Több terület nem jön ki: nagyobb méret + kisebb scale csak pixelesebb, ugyanannyi terület. Zoom 0 (6 szintből) a határ.
- ❌ Dead reckoning nem megoldható: instance-ban `GetPlayerFacing()` = **nil**; `GetUnitSpeed`/`IsPlayerMoving` működik,
  de irány nélkül nem számolható pozíció. Pixel/memória-olvasás ToS-sértő → kizárva.
- ❌ Natív világtérkép-réteg (UnitPositionFrame): `C_Map.GetMapInfo(279)` (WC) = **nil**, a `SetMapID(279)` Kalimdorra esik vissza.
  A kliensben a dungeon art FÁJLOK megvannak, de a dungeon **uiMap rekordok nincsenek** → a motor nem tud dungeon térképre rajzolni.
- ❌ Irány-szivárgás az iránytűből: `MinimapCompassTexture:GetRotation()` → *"forbidden aspect 'QueryRotation'"* —
  a Blizzard kifejezetten tiltja. Minimap metódusok/`C_Minimap` átnézve (249 + 23 fv.), pozíciót egyik sem ad.
- ✅ `C_Minimap.GetViewRadius()` = 150 yard (zoom 0, beltér) → méretarány ismert. `C_Minimap.GetUiMapID()` = nil.
- ✅ `C_Minimap.SetDrawGroundTextures(false)` működik: csak a pöttyök maradnak (terep nélkül), visszakapcsolható.
  → **Végleges: a natív minimap élő nézet a maximum, amit a játék enged.**
- Minimap részletek: `GetMaskTexture` nincs; a kerek maszk visszaállítása `Interface\Masks\CircleMaskScalable`-lel működik.
  A Minimap gyerekei közt vannak más addonok pinjei (QuestieFrameGroup) és gombjai (LibDBIcon) → a végleges
  addon a Questie pineket NE rejtse el, csak a keretet/gombokat.

### 2.2 Módosított koncepció (hibrid)
| Réteg | Tartalom | Forrás |
|---|---|---|
| **Teljes dungeon térkép** (M) | egész dungeon, boss pinek + loot tooltip, questek, emeletek | kliens WorldMap art / saját art (új dungeonök) |
| **Élő nézet** (beágyazott panel / toggle) | player nyíl, party pöttyök (+név, ha a minimap adja), játékos-központú, zoom | a natív Minimap átparentelve, csak amíg a térkép nyitva |

A két réteg nem illeszthető egymásra (nincs koordináta). Jobb klikk → zóna világtérkép marad.

---

## 3. Architektúra

### 3.1 Fájlstruktúra (tervezett)

```
ForeverDungeonMap/
  ForeverDungeonMap.toc          ## Interface: 16001 (+ _Camelot.toc ha kell)
  Core/
    Init.lua                     namespace, SavedVariables, események
    InstanceTracker.lua          belépés/kilépés, instanceID → dungeon rekord, emelet
    Comm.lua                     (B/C eset) pozíció-szinkron addon üzenettel
  Map/
    WorldMapHook.lua             M megnyitáskor dungeon map; navigáció (bal/jobb klikk)
    Providers/
      BossDataProvider.lua       MapCanvasDataProviderMixin: boss pinek
      QuestDataProvider.lua      quest pinek (dungeonon belüli NPC-k, tárgyak)
      EntranceDataProvider.lua   zónatérképen: dungeon bejárat → bal klikk = be
      GroupDataProvider.lua      (B/C eset) saját player/party pöttyök
    Pins.xml                     pin templatek (MapCanvasPinMixin)
    CustomArtLayer.lua           (C eset) saját textúra a canvasra
    SidePanel.lua                térkép melletti panel: bossok, loot, questek
  Data/
    Dungeons.lua                 instanceID → {uiMapID/floors, art, kalibráció, bejárat}
    Bosses.lua                   boss: npcID, név, pozíció (x,y,floor), loot itemID-k
    Quests.lua                   questID, adó NPC + hely, szint, faction, láncok
  Locales/  enUS.lua, deDE.lua, huHU? (WoW-ban nincs huHU kliens → angol alap)
  Media/                         saját art az új dungeonökhöz, ikonok
```

### 3.2 Térkép integráció – a "natív érzés" kulcsa
- **Nem** írjuk felül a `C_Map` függvényeket (ez volt a MapUtils baja), és **nem** teszünk fekete overlay-t (ez volt az FDJ baja).
- `hooksecurefunc(WorldMapFrame, "OnShow"/"OnMapChanged")` + `WorldMapFrame:SetMapID(dungeonMapID)` → amikor instance-ban vagy és megnyitod az M-et, a dungeon térkép jelenik meg.
- Saját tartalom **data providerként**: `WorldMapFrame:AddDataProvider(CreateFromMixins(MapCanvasDataProviderMixin, ...))`. A pinek így együtt zoomolnak/mozognak a térképpel, ugyanúgy néznek ki, mint a natív pinek.
- **Navigáció:**
  - Dungeon térképen **jobb klikk** = fel a szülő zónára (natív viselkedés, ha a uiMap parentje be van állítva; ha nem, mi kezeljük).
  - Zóna térképen a dungeon bejárat pinre **bal klikk** = be a dungeon térképre.
  - NavBar breadcrumbban látszik: Kontinens › Zóna › Dungeon (›Emelet).
  - Több emeletes dungeon: natív emeletválasztó (MapGroup) vagy saját dropdown ugyanazzal a templattel.
- Combat lockdown: map-váltás nem védett művelet, de figyelni kell a taintre (ne nyúljunk secure frame-ekhez).

### 3.3 Új Forever dungeonök (C eset)
- Ha nincs uiMapID: a WorldMapFrame-et egy „gazda” uiMapID-n hagyjuk (a bejárat zónája), és a canvas child-ra egy **saját textúra réteget** rakunk, a natív pineket ilyenkor elrejtjük. Így megmarad a natív pan/zoom és keret.
- Art: **saját készítésű vagy engedéllyel használt** térkép. Más addon artját (Atlas de Azeroth, FDJ Media) engedély nélkül **nem** tehetjük ki CurseForge-ra.
- Kalibráció: 2–3 ismert pontnál `UnitPosition`-t mérünk → affin transzformáció world→art koordináta (dungeonönként a Data/Dungeons.lua-ban).

### 3.4 Pöttyök és hover
- A) eset: natív (a Blizzard pötty + tooltip, osztályszín).
- B/C eset: saját pin, osztályszínű pötty, a saját karakter nyíllal; `OnEnter` → GameTooltip a névvel (több egymásra eső pöttynél mindegyik neve, mint retailen). Frissítés `OnUpdate`-ből, kb. 10–20 Hz-en.

### 3.5 Bossok, loot, questek
- Boss pin (koponya ikon / portré): hover → név, szint, loot lista (item linkek, `Item:CreateFromItemID` aszinkron betöltéssel), klikk → oldalpanel.
- Oldalpanel: bossok sorrendben, loot slot/típus szűrővel, questek (felvehető / felvett / kész: `C_QuestLog.IsOnQuest`, `IsQuestFlaggedCompleted`), honnan kell felvenni (zóna + koordináta, pinként a zónatérképen).
- Adatforrás: saját kurált adat (wowforevertalents.com, foreverchanges.pro, wowf.io mint referencia), plusz **opcionális** QuestieDB integráció, ha fent van. GPL-es addonok (MapUtils, DungeonMaster) adatai csak akkor vehetők át, ha az addonunk is GPLv3 → **licencet el kell dönteni**.

---

## 4. Fázisok

| # | Fázis | Kimenet | Teszt |
|---|---|---|---|
| 0 | Fejlesztői környezet | VS Code + Lua LS + WoW API annotációk (Ketho `wow-api` extension), symlink a repóból az AddOns mappába, BugSack/BugGrabber a hibákhoz | addon betölt, `/reload` |
| 1 | **Probe addon** | `/fdm probe` kiírja a 2. pont értékeit | 1 klasszikus (pl. Deadmines) + 1 új dungeon, csapattal |
| 2 | Térkép auto-váltás | M dungeonben → dungeon térkép; jobb/bal klikk navigáció; emeletek | klasszikus dungeonök |
| 3 | Pöttyök | A/B/C ág szerint player + party, hover név | 2-3 fős csapat |
| 4 | Boss pinek + loot tooltip | data provider + Bosses.lua | |
| 5 | Oldalpanel: loot + questek | | |
| 6 | Új Forever dungeonök | art, kalibráció | mind a 9 |
| 7 | Beállítások | Settings panel: ki/be funkciók, pin méret, auto-váltás ki/be | |
| 8 | Kiadás | GitHub repo, `.pkgmeta`, BigWigs packager GitHub Action → CurseForge (+ Wago) automatikus feltöltés tagre | első release |

## 5. CurseForge kiadás
- TOC: `## Interface: 16001`, `## X-Curse-Project-ID: <id>`, `## Version: @project-version@`, `## IconTexture`, `## Category: Map`.
- Ellenőrizni: a CurseForge-on van-e külön „WoW Forever” játékverzió (a MapUtils és ImprovedForever kint van CurseForge-on Forever TOC-cal → igen, támogatott).
- Csomagolás: BigWigsMods/packager GitHub Actionnel, tag → zip → feltöltés.
- **Licenc: GPLv3 (eldöntve).** `LICENSE` fájl a repóban + `THIRD_PARTY.md`: mely adatok honnan származnak
  (MapUtils – D4KiR, GPLv3; DungeonMaster – MalkDev, GPLv3). A ForeverDungeonJournal-nak nincs licence →
  adatát/artját csak a szerző (Exehn) engedélyével használhatjuk.

## 6. Kockázatok
1. **Instance pozíció-korlátozás**: ha a kliens semmit nem ad, a csapatpöttyök nem lesznek megoldhatók (csak addon-üzenettel, és ott is csak, ha `UnitPosition("player")` működik). Az 1. fázis eldönti.
2. **Map art az új dungeonökhöz**: saját art kell, vagy engedély.
3. **Ütközés** MapUtils-szal / FDJ-vel: mindkettő a dungeon térképre hookol → detektálni és ajánlani, hogy kapcsolják ki a funkciójukat (vagy kompatibilitási mód).
4. Kliens patchek (16002, 16100...) → Interface szám frissítés.

## 7. Nyitott kérdések (a felhasználónak)
- ~~Addon neve~~ → **ForeverDungeonMap**
- ~~Licenc~~ → GPLv3
- Kezdjük-e a probe addonnal (javasolt), amit neked kell majd egy dungeonben futtatnod és visszaküldened az eredményt?
