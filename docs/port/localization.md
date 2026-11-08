# Names and descriptions in the play UI (P4-03, P4-04)

What a player reads for items, skills, monsters, maps, jobs and statuses, where each string comes from, and what
changed. Checked against rAthena `d4b8e7b8` (`db/re`, 29,356 items, 1,635 skills, 2,675 monsters, 1,265 maps) and the
kRO 2021-04-06 client in `~/Games/kRO_20210406/client`.

## Where the text comes from

- **Locale.** `Locale.current` picks the nearest `*.lproj` of `RagnarokLocalization`. On the build Mac (`en_PT`) that
  is `en`; a language with no table (`fi_FI`) also gets `en`; `pt_PT` gets `pt-BR`. There is no in-game language
  setting.
- **The kRO files are Korean only.** `System/itemInfo.lub`, `data.grf` `msgstringtable.txt` and the rest hold Korean
  text. The game reads none of them for names. The `ko.lproj` tables are a bake of those files, and
  `ItemCommonInfo.json` (RagnarokResources) holds the sprite and icon names. The only `System/*.lub` file the game
  loads is `achievement_list.lub`.
- **English comes from the upstream tables** (`en.lproj`, built from an English client) and, where those have no
  entry, from rAthena's own database files.
- **The server's SQL `item_db`, `mob_db` and `skill` tables are empty or hold ids only** (`use_sql_db: no`; the
  `inventory` table has ids and flags). The YAML is the database.
- **The server sends monster, NPC and player names itself** (`clif_set_unit_idle` and the walking and spawn variants
  copy `status_get_name`, which is the `Name` of `mob_db.yml` for a monster). The client shows that string.

## What a player sees

Samples are the ids from the task: items 501, 1201, 2301, 4001 (and 1190, 542 that the English table lacks), skills
1 (NV_BASIC), 5 (SM_BASH), 18 (MG_FIREWALL), 360 (LK_FURY), monsters 1002, 1113. "Before" is `Locale en_PT` unless
stated; every value was read from the real tables by a unit test (`NameLookupSampleTests`).

| Thing shown | Source | Locale | Before | After |
| --- | --- | --- | --- | --- |
| Item name in inventory, equipment, storage, shop, mail, drops | `ItemInfoTable` (`ItemInfo.json`) | en | `Red Potion`, `Knife`, `Cotton Shirt`, `Poring Card`; ids missing from the table (11,382 of the server's 29,356: Claymore 1190, Festival Cookie 542) showed the bare number `1190`, `542`; 34 names (16 items, such as Booster Pack 100029) were Korean bytes read as Latin-1 | same for the first four; `Claymore`, `Festival Cookie`; the 34 garbled names show the English name (`Booster Pack(1)`) |
| Same | same | pt-BR (`pt_PT`) | 1190 showed `Å©·¹ÀÌ¸ð¾î`; 11,449 pt-BR item names are untranslated Korean bytes | `Claymore` (English, then server name) |
| Same | same | ko | `크레이모어`; 542 showed `542` | unchanged; 542 shows `Festival Cookie` |
| Unidentified equipment or card (inventory detail) | `ItemInfoTable`, `Flag.IsIdentified` of the item list packet | en | identified name and text: `Knife`, `Cotton Shirt`, `Poring Card`, "A simple knife..." | `Dagger`, `Armor`, `Card`, "An unknown item that requires appraisal. It can be identified by using a Magnifier." |
| Item description | `ItemInfoTable` | en | identified text for every item | identified or unidentified text by the flag |
| Skill name in the skill window and homunculus skill list | `SkillInfoTable` (`SkillInfo.json`) | en | `Basic Skill`, `Bash`, `Fire Wall`; skills missing from the table (222 of 1,635) showed the Aegis name `LK_FURY` or `Skill 5499` | `Fury`, `Four Colors Charm` (server `Description`); same for the rest |
| Skill description | `SkillInfoTable` | en | full text for 1,251 of the server's 1,635 skills; the Aegis name for the rest | unchanged; no English text exists for the rest |
| Hotkey bar (skills and items) | icon only, from the GRF by Aegis name | n/a | no text | no text |
| Monster name over a head and on the target selector | server packet (`mob_db.yml` `Name`) | n/a | `Poring`, `Drops` | unchanged |
| Monster name from an id (quest objective with no name in the packet, database pages) | `MonsterNameTable` | en | `nil` (only zh-Hans and zh-Hant have a table); the quest line read `Monster #1002` | `Poring`, `Drops` (server `Name`); zh keeps `波利` |
| NPC name | server packet; text after `#` is dropped | n/a | `Kafra Employee` | unchanged |
| Map name (warp list, world map, party, character select, map change message) | `MapInfoTable` (`MapInfo.json`) | en | `Prontera, the Capital of Rune-Midgarts Kingdom`, `Prontera Field`; 203 of 1,265 maps (`gef_fild12`, `new_zone01`, test maps) show the map file name | unchanged for en; other languages now fall back to en |
| Job name in the status window | `JobID.localizedName` (`JobID.xcstrings`) | en | `NOVICE` (Aegis name; the character, party, guild and mail windows already used the localized name) | `Novice` |
| Status icon tooltip | `StatusInfoTable` (`StatusInfo.json`, 695 statuses) | en | text for the 695 statuses; nothing for others | unchanged |
| Chat and system messages | `MessageStringTable` | en | English; 10 entries are Korean bytes read as Latin-1 (1900-1907, 1942, 2032: old security password, send-log and summon-timer texts), none used by a window today | unchanged |

## Lookup order

Implemented in `RagnarokLocalization`, which already owned the tables. The call sites (`localizedIdentifiedItemName`,
`localizedSkillName`, `localizedMonsterName`, `localizedMapName`) keep their names, so every window gets the fix.

1. The table of the locale. An entry that is empty, or that holds Korean in a table that is not Korean (Hangul, or
   its CP949 or UTF-8 bytes read as Latin-1), counts as missing.
2. The English table, unless the locale is English.
3. The server's name: `ServerNames.json`, English `Name` of `item_db_*.yml` and `mob_db.yml`, `Description` of
   `skill_db.yml`. Items, skills and monsters only. Descriptions have no server text.
4. `nil`. The views keep their own last resort (the id, the Aegis name).

`ItemInfoTable.localizedItemName(forItemID:isIdentified:)` and `localizedItemDescription(forItemID:isIdentified:)` add
the unidentified text. An unidentified item with no unidentified entry reads as identified.

`ServerNames.json` is a snapshot of the YAML names that `RagnarokDatabase` already parses for the database browser.
`RagnarokGame` does not link `RagnarokDatabase` or `swift-rathena` (a whole server), so the names travel as a 1 MB
resource instead. Regenerate it when the rAthena pin moves:

```sh
scripts/gen-server-names.py ~/dev/rathena     # or no argument for the swift-rathena submodule
```

`swift-rathena/db/re` and `~/dev/rathena/db/re` agree on every item, skill and monster name today.

`InventoryItem.isIdentified` (RagnarokModels) reads bit 0 of the `Flag` byte of the item list packets
(`NORMALITEM_INFO`, `EQUIPITEM_INFO`), and `IsIdentified` of the pickup and storage packets.

## What stays Korean, missing or raw

- **Skill descriptions.** 384 of the server's 1,635 skills have no English description (222 of them have no English
  name either, now recovered from the server). The window shows the Aegis name there, as before. Most are monster
  skills (`NPC_*`) and 29 skills of jobs newer than the 2021 client.
- **Map names.** 203 of 1,265 maps have no name in any table, and the YAML has none, so the map file name shows.
- **Korean in the Korean locale** stays Korean by design, with the English server name for ids the Korean table lacks.
- **Appraisal is not built.** `ZC_ITEMIDENTIFY_LIST` is not registered in `PacketRegistry`, so a Magnifier cannot be
  used and `ZC_ACK_ITEMIDENTIFY` is not applied. Weapons and armor drop unidentified (`itemdb_isidentified`), and
  rAthena refuses to equip them (`clif_parse_EquipItem`), so they read `Dagger` and stay that way in the client, as
  they could not be worn before either. Not part of this task.
- **Refine and slot suffixes** (`+7 Knife [3]`) are not drawn. `EQUIPITEM_INFO.RefiningLevel` is decoded and dropped,
  and `slotCount` of `ItemCommonInfo.json` is unused.
- **`System/itemInfo.lub` is not read.** English players gain nothing from it (Korean text). Its resource names are
  already in `ItemCommonInfo.json`: 23,202 items, which leaves 7,250 server items (all newer than the 2021 client)
  and one monster drop (18115 Orc Archer Bow) without an icon name.
- **The database tables of other languages** still carry the Korean entries listed above (pt-BR 11,449 item names,
  id 6,693, th 28). They are hidden by the lookup, not repaired in the JSON.

## Tests

- `swift test --package-path Packages/RagnarokLocalization`: 93 tests. `NameLookupOrderTests` builds tables by hand
  and checks the order and the Korean filter; `LocalizedTextTests` checks the Korean detector on real strings;
  `NameLookupSampleTests` resolves the samples above from the shipped tables and sweeps the English item names for
  Korean.
- `swift test --package-path Packages/RagnarokModels`: `InventoryItemTests` checks the identified flag of each packet.
- `swift test --package-path Packages/RagnarokGame`: 183 tests, unchanged.
