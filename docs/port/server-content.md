# Target server content (P4-01)

What the rAthena server in `/Users/fwgl/dev/rathena` enables, so the macOS client builds UI only for content that is on.

- rAthena commit: `d4b8e7b8` ("Remove duplicate Trade block from Sinulog Hat (#10109)").
- Build PACKETVER: `20211103`, Renewal (RagexeRE packet set).
- Paths below are relative to the rAthena root.
- "On" means on in the checked-in config or compiled in. Nothing was run against a live server.
- Read-only research. Nothing under `/Users/fwgl/dev/rathena` was modified.
- The rAthena working tree has three uncommitted files that change facts below: `src/custom/defines_post.hpp` (packet obfuscation off), `tools/docker/asset/char_conf.txt` (Docker pincode, name and delete overrides), and `tools/docker/docker-compose.yml` (port bindings only). This doc uses the working tree. At HEAD, obfuscation is on by default (`src/config/packets.hpp:44-50`) and Docker does not override pincode.

## 0. Build and mode

| Fact | Value | Source |
|---|---|---|
| Build PACKETVER | 20211103 (default; Docker passes `--enable-packetver=20211103`) | `src/config/packets.hpp:16`, `tools/docker/docker-compose.yml:34` |
| RagexeRE packet set | `PACKETVER_RE` defined (window 20200902–20211118), `PACKETVER_RE_NUM = PACKETVER` | `src/config/packets.hpp:22-38` |
| Renewal vs pre-renewal | Renewal. `//#define PRERE` is commented out. | `src/config/renewal.hpp:8` |
| Renewal sub-flags | `RENEWAL`, `RENEWAL_CAST`, `RENEWAL_DROP`, `RENEWAL_EXP`, `RENEWAL_LVDMG`, `RENEWAL_ASPD`, `RENEWAL_STAT` all defined | `src/config/renewal.hpp` |
| Pre-renewal build | Off by default (`--enable-prere`) | `configure.ac` |
| DB folder | `db/re/` (`DBPATH "re/"` under `RENEWAL`) | `src/config/const.hpp:37-41` |
| Main NPC list | `npc/re/scripts_main.conf` (renewal branch) | `src/map/map.cpp:4262-4266` |
| Packet obfuscation | Off in the working tree (`#undef PACKET_OBFUSCATION`, uncommitted). At HEAD it is on by default for PACKETVER ≥ 20110817. | `src/custom/defines_post.hpp`, `src/config/packets.hpp:44-50` |
| PACKETVER override file | Empty | `src/custom/defines_pre.hpp` |
| Config/DB overrides | `conf/import/*.txt` and `db/import/*` hold comments only. Only Docker mounts real overrides (section 7). | `conf/import/`, `db/import/` (gitignored, `.gitignore:67`) |

## 1. Jobs

Source: `db/re/job_stats.yml` (83 `Jobs:` groups, 172 unique keys). Job IDs: `src/common/mmo.hpp` (enum around lines 900–1090).

| Group | Keys | Examples |
|---|---|---|
| Base and expanded (no suffix) | 86 | Novice, Swordman, Mage, Archer, Summoner, Rebellion, Kagerou, Oboro, Ninja, Taekwon, Star_Gladiator, Soul_Linker, Gunslinger, Sura, Genetic, Shadow_Chaser, Rune_Knight, Royal_Guard, Mechanic, Guillotine_Cross, Warlock, Ranger, Arch_Bishop, Sorcerer, Minstrel, Wanderer, Super_Novice, Super_Novice_E, Hyper_Novice |
| `Baby_*` / `Super_Baby*` | 54 | Baby_Swordman, Baby_Summoner, Super_Baby_E |
| `_T` / `_T2` suffix | 17 | Rune_Knight_T2, Ranger_T2, Royal_Guard_T2, Warlock_T |
| Numeric `2` suffix | 23 | Knight2, Crusader2, Paladin2, Star_Emperor2, Sky_Emperor2 (8 of these are also `Baby_*`) |

Totals: 86 + 54 + 17 + 23 − 8 (overlap) = 172.

- Summoner: on (`JOB_SUMMONER = 4218`, `src/common/mmo.hpp:1044`; key `Summoner` in `db/re/job_stats.yml`).
- Expanded classes: on. Later-branch names present: Star_Emperor, Sky_Emperor (`JOB_SKY_EMPEROR = 4302`), Soul_Reaper, Shinkiro, Shiranui, Night_Watch, Spirit_Handler, Soul_Ascetic, Dragon_Knight, Meister, Windhawk, Imperial_Guard, Biolo, Abyss_Chaser, Elemental_Master, Inquisitor, Troubadour, Trouvere.
- 4th-job tier: not verified. `job_stats.yml` has no tier field.
- Pre-renewal comparison: `db/pre-re/job_stats.yml` has 74 keys.
- Other job data: `db/re/job_exp.yml`, `job_aspd.yml`, `job_basepoints.yml`, `job_outfits.yml`, `job_noenter_map.txt`.

## 2. Maps

| Item | Value | Source |
|---|---|---|
| Active map lines | 1265 (41 commented out) | `conf/maps_athena.conf` |
| Instance maps `N@name` | 163 lines, loaded at startup (e.g. `1@tower`, `2@tower`, `1@cata`, `1@orcs`, `1@nyd`) | `conf/maps_athena.conf` |
| Map index | 1295 names. Every active map is in the index. | `db/map_index.txt` |
| Instance definitions | 78 entries (Endless Tower, Sealed Catacomb, Orc's Memory, Nidhoggur's Nest, Bakonawa Lake, Old Glast Heim, Geffen Magic Tournament, Sky Fortress Invasion, Infinite Space, Eclage Interior, and others) | `db/re/instance_db.yml` |
| Instance creation | Copies a loaded base map at runtime | `src/map/map.cpp:2819` (`map_addinstancemap`) |
| Episode and expansion maps | Loaded: `pay_*`, `ra_*`, `ein_*`, `lhz_*`, `hu_*`, `gld_*`, `ayo_*`, `lou_*`, `gon_*`, `mosk_*`, `dic_*`, `bif_*`, `ama_*`, `tur_*`, `xmas*`, `cmd_*`, `anthell*`, `new_*`, `force_*`, `mjolnir_*`, and others | `conf/maps_athena.conf` |
| Main towns loaded | prontera, geffen, payon, morocc, alberta, izlude, aldebaran, comodo, yuno, lighthalzen, einbroch, einbech, hugel, rachel, veins, moscovia, ayothaya, louyang, jawaii, umbala, niflheim, brasilis, amatsu, gonryun, manuk, splendide, mora, malangdo, malaya, dewata, eclage | `conf/maps_athena.conf` |
| Towns with NPCs but no map | `lutie` (`npc/cities/lutie.txt` loads, no map in `maps_athena.conf` or `map_index.txt`); `rockridge` (no map); `dicastes` (only `dicastes01`, `dic_*`) | `conf/maps_athena.conf`, `db/map_index.txt` |

## 3. Systems

"On" means the switch is on or the system is compiled in with no switch. "Loaded NPC" means the file is reached from `npc/re/scripts_main.conf` (section 4).

| System | State | Config key or source | Data and NPCs |
|---|---|---|---|
| Pets | On | `conf/battle/pet.conf` (`pet_equip_required: yes`, `pet_autofeed_always: yes`, `pet_catch_rate: 100`). `feature.petevolution: on`, `feature.petautofeed: on` in `conf/battle/feature.conf`. | `db/re/pet_db.yml` (107 pets). Loaded: `npc/re/merchants/pet_trader.txt`, `pet_groomer.txt`. |
| Homunculus | On | `conf/battle/homunc.conf` (`homunculus_max_level: 99`, `homunculus_S_max_level: 275`, `homunculus_autofeed_always: yes`). `feature.homunculus_autofeed: on`. | `db/re/homunculus_db.yml` (21 classes), `exp_homun.yml`. Loaded: `npc/re/quests/homun_s.txt`. |
| Mercenaries | On | Table `mercenary_owner_db` in `conf/inter_athena.conf:129`. `mercenary_autoloot: no` in `conf/battle/drops.conf:177`. | `db/re/mercenary_db.yml` (20). Loaded: `npc/re/other/mercenary_rent.txt`. |
| Elementals | On | `elemental_db.yml` | 17 entries. Loaded: `npc/merchants/elemental_trader.txt`. |
| Mounts (Peco, Dragon, Wug, Madogear) | On, item-driven | Option bits in `src/map/pc.cpp:1364`. `rental_mount_speed_boost: 25` in `conf/battle/player.conf:195`. | Loaded: `npc/merchants/renters.txt` (rental mounts), `npc/re/quests/quests_16_1.txt` (`setriding`, `setdragon`, `setwug`). |
| Cash mounts | Not available | No cash items (see Cash shop). | none |
| Costumes | On, item-driven | `Costume_*` flags in `db/re/item_db_equip.yml`. `db/re/job_outfits.yml`. | Loaded: `npc/re/mapflag/nocostume.txt`, `npc/re/merchants/malangdo_costume.txt`. |
| Mail (RODEX) | On | `src/map/mail.cpp` (PACKETVER ≥ 20150513 gate, line 183). `conf/battle/misc.conf`: `mail_daily_count: 100`, `mail_zeny_fee: 2`, `mail_attachment_price: 2500`, `mail_attachment_weight: 2000`, `mail_delay: 1000`. `conf/char_athena.conf`: `mail_return_days: 15`, `mail_delete_days: 15`, `mail_retrieve: yes`, `mail_return_empty: yes`. | Loaded: `npc/other/mail.txt`, but its `openmail` command is not supported at PACKETVER 20150513 and later (`script.cpp` `BUILDIN_FUNC(openmail)` logs an error and fails), so the NPC takes 130 zeny and opens nothing. RODEX is opened by the client (`CZ_OPEN_MAILBOX2`) or by `@mail` (`ZC_MAIL_WINDOWS`). |
| Achievements | On | `feature.achievement: on` (`conf/battle/feature.conf:81`). `achievement_mob_share: no` (`conf/battle/monster.conf:328`). | `db/re/achievement_db.yml` (511), `achievement_level_db.yml`. Loaded: `npc/re/other/achievements.txt`. |
| Cash shop | Code on, no items | `cashshop_show_points: no` (`conf/battle/misc.conf:135`). Items come from `db/item_cash.yml`, which imports `db/import/item_cash.yml`. | That import is header-only (no `Body`), so the item list is empty. Loaded: `npc/re/merchants/cashmall.txt`, `npc/re/other/CashShop_Functions.txt`. |
| Quest log | On | `quest_skill_learn: no`, `quest_skill_reset: no` (`conf/battle/player.conf:39,44`). `quest_exp_rate: 100` (`conf/battle/exp.conf:57`). | `db/re/quest_db.yml` (4867 entries), `src/map/quest.cpp`. 154 quest NPC files loaded. |
| Party | On | `conf/battle/party.conf`: `party_item_share_type: 0`, `show_party_share_picker: yes`, `party_update_interval: 1000`, `block_account_in_same_party: yes`. | No feature switch. |
| Guild | On | `conf/battle/guild.conf`: `guild_exp_limit: 50`, `max_guild_alliance: 3`, `guild_leaderchange_delay: 1440`, `require_glory_guild: no`. | `db/re/guild_skill_tree.yml`. About 51 guild and castle NPC files loaded (`npc/guild`, `npc/guild2`, `npc/re/guild`, `npc/re/guild3`). |
| Clan | On | `clan_table` in `conf/inter_athena.conf:138`. `clan_remove_inactive_days: 14` in `conf/char_athena.conf:278`. | Loaded: `npc/re/other/clans.txt` (`clan_join`). |
| Bank | Feature on, reachable only via one quest NPC | `feature.banking: on` (`conf/battle/feature.conf:34`). `feature.banking_state_enforce: no` (line 39). PACKETVER gate ≥ 20130724 (`src/map/battle.cpp:9035`, passes). | `openbank` is called only by `npc/re/quests/quests_rockridge.txt` (loaded). Bank NPCs `npc/custom/etc/bank.txt` and `bank_kafra.txt` are commented out in `npc/scripts_custom.conf`. |
| Roulette | On | `feature.roulette: on` (`conf/battle/feature.conf:73`). `feature.roulette_bonus_reward: on` (line 77). Table `roulette_table = db_roulette` (`conf/inter_athena.conf:163`). | Client packet handler `clif_parse_roulette_open` (`src/map/clif.cpp:20879`). No loaded NPC calls `open_roulette`. |
| Barter | On | `feature.barter: on` (`conf/battle/feature.conf:126`). `feature.barter_extended: on` (line 130). Entry `npc/barters.yml` (`src/map/npc.cpp:394-395`). | `npc/barters.yml` imports `npc/re/merchants/barters.yml` (Mode: Renewal, which imports 16 barter files) and `npc/custom/barters.yml`. |
| Private airship | On | `feature.privateairship: on` | Loaded: `npc/re/mapflag/privateairship.txt`, `npc/airports/airships.txt`. |
| Stylist (hair/style) | On | `feature.stylist: on` (`conf/battle/feature.conf:179`). | `db/re/stylist.yml`. Loaded: `npc/re/merchants/Extended_Stylist.txt`. Base `npc/custom/stylist.txt` is not loaded. |
| Refine UI | On | `feature.refineui: on`. | `db/re/refine.yml`. Loaded: `npc/re/merchants/refine.txt`, `advanced_refiner.txt`, `hd_refiner.txt`, `shadow_refiner.txt`. |
| Enchant UI (enchant grade, socket) | On (no switch) | `OUT_UI_ENCHANT`, `OUT_UI_ENCHANTGRADE` (`src/map/clif.hpp:1423-1424`). | `db/re/enchantgrade.yml`, `db/re/item_enchant.yml` (138). Loaded: `npc/re/merchants/enchantgrade.txt`, `socket_enchant2.txt`. |
| Attendance | On | `feature.attendance: on` (`conf/battle/feature.conf:118`). | `db/re/attendance.yml` (20 day rewards). Opens at login if not rewarded today (`src/map/pc.cpp:14796`, `:15576`). No NPC needed. |
| Navigation (navi) | On (no switch) | `src/map/navi.cpp`. | Loaded: `npc/re/guides/navigation.txt`. `navigateto` used by about 12 loaded instance and quest scripts. |
| Hat effects | On, item-driven | `hateffect()` builtin (`src/map/script.cpp:24753`). | Called from `db/re/item_db_equip.yml` and `item_db_etc.yml`. No loaded NPC calls it. No config key. |
| Item reform | On | `db/re/item_reform.yml`, loader `src/map/itemdb.cpp:1913`. | `item_reform()` called by 3 loaded NPC files: `npc/re/merchants/rgsr_in.txt`, `npc/re/quests/garden_of_time.txt`, `npc/re/quests/quests_18.txt`. |
| Lapine (Laphine upgrade and synthesis) | On, item-driven | `laphine_synthesis.yml`, `laphine_upgrade.yml`. Builtins `buildin_laphine_synthesis` and `buildin_laphine_upgrade` (`src/map/script.cpp:26992`, `:27026`). | Triggered from `db/re/item_db_usable.yml` (`laphine_upgrade()` calls). Rare. |
| Equipswitch | On | `feature.equipswitch: on`. | No NPC needed. |
| Itemlink and mesitem link/icon | On | `feature.itemlink: on`, `feature.mesitemlink: on`, `feature.mesitemicon: on`. | No NPC needed. |
| Buying store, search store, autotrade | On | `feature.buying_store: on`, `feature.search_stores: on`, `feature.autotrade: on` (`conf/battle/feature.conf`). | No NPC needed. |
| Battleground queue | On | `feature.bgqueue: on`. `conf/battle/battleground.conf`. | Loaded: `npc/battleground` (12 files), `npc/re/battleground` (1). |
| Auction | Off | `feature.auction: off`. | none |

## 4. NPC script groups

Method: follow the `import:` lines from `npc/re/scripts_main.conf` recursively, skipping `//` lines and collecting `npc:` entries. Result: 835 `npc:` entries, 0 missing files.

| Group | Loaded files | Note |
|---|---|---|
| `npc/re/mobs` | 100 | |
| `npc/quests` | 86 | of 88 files |
| `npc/warps` | 81 | |
| `npc/re/quests` | 68 | |
| `npc/re/warps` | 56 | |
| `npc/re/merchants` | 54 | |
| `npc/re/instances` | 47 | |
| `npc/jobs` | 33 | |
| `npc/re/guides` | 32 | |
| `npc/other` | 29 | |
| `npc/mapflag` | 28 | |
| `npc/cities` | 27 | |
| `npc/re/jobs` | 27 | |
| `npc/merchants` | 23 | |
| `npc/guild` | 22 | |
| `npc/re/mapflag` | 21 | |
| `npc/re/other` | 17 | |
| `npc/guild2` | 13 | |
| `npc/re/cities` | 13 | |
| `npc/re/guild3` | 12 | |
| `npc/battleground` | 12 | |
| `npc/airports` | 7 | |
| `npc/instances` | 4 | |
| `npc/kafras`, `npc/re/kafras` | 4 + 4 | |
| `npc/re/guild` | 4 | |
| `npc/events` | 3 | of 36 files. `gdevent_aru`, `gdevent_sch`, `god_se_festival`. |
| `npc/mobs` | 3 | |
| `npc/re/custom` | 3 | lasagna quests only |
| `npc/custom` | 0 | of 65 files. `npc/scripts_custom.conf` has every entry commented out. |

The main file is `npc/re/scripts_main.conf`. The `scripts_*.conf` files are under `npc/`, not `conf/`. `conf/script_athena.conf` holds only script-engine limits.

## 5. Rates

| Key | Value | File |
|---|---|---|
| `base_exp_rate`, `job_exp_rate`, `mvp_exp_rate`, `quest_exp_rate` | 100 | `conf/battle/exp.conf` (lines 13, 16, 54, 57) |
| `exp_bonus_attacker`, `exp_bonus_max_attacker` | 25, 12 | `conf/battle/exp.conf` |
| `death_penalty_type`, `death_penalty_base`, `death_penalty_job` | 1, 100, 100 | `conf/battle/exp.conf` |
| `zeny_penalty`, `multi_level_up` | 0, no | `conf/battle/exp.conf` |
| `use_statpoint_table`, `use_traitpoint_table` | yes, yes | `conf/battle/exp.conf` |
| `item_rate_common`, `_heal`, `_use`, `_equip`, `_card`, `_mvp`, `_treasure` (and boss/mvp variants) | 100 | `conf/battle/drops.conf` (line 57 onward) |
| `drop_rate_cap`, `drop_rate_cap_vip` | 9000, 9000 | `conf/battle/drops.conf:209-210` |
| `item_logarithmic_drops`, `drops_by_luk` | no, 0 | `conf/battle/drops.conf` |
| `enable_bonus_map_drops` | yes | `conf/battle/drops.conf` |

All rates are 1x.

## 6. Server flags that touch the client

| Flag | Value | Source |
|---|---|---|
| `pincode_enabled` / `pincode_force` | yes / yes (`pincode_maxtry: 3`, `pincode_changetime: 0`) | `conf/char_athena.conf` ~lines 222–230 |
| PIN code support in packets | Yes (`PACKETVER_SUPPORTS_PINCODE`, PACKETVER ≥ 20110309) | `src/config/packets.hpp:83` |
| `new_account` | no. Login refuses account registration. | `conf/login_athena.conf:56`; `src/login/login.cpp:324`. Code default is true (`login.cpp:758`), but the conf value wins. |
| `char_new` | yes | `conf/char_athena.conf:88` |
| `char_name_option` / `char_name_min_length` | 1 (letters from `char_name_letters`) / 4 | `conf/char_athena.conf:160` |
| `char_del_delay` | 86400 s (24 h) | `conf/char_athena.conf:176` |
| `char_del_option` / `char_del_restriction` | 2 / 3 (blocked while in party or guild) | `conf/char_athena.conf:188,195` |
| Web server | On (`WEB_SERVER_ENABLE` for PACKETVER > 20200300). `web_port: 8888`. `use_web_auth_token: yes`. | `src/config/packets.hpp:92`, `conf/web_athena.conf`, `conf/login_athena.conf` |
| `client_hash_check` | off | `conf/login_athena.conf` |
| Packet obfuscation | Off in the working tree (uncommitted). On by default at HEAD. | `src/custom/defines_post.hpp`, `src/config/packets.hpp:44-50` |

## 7. Docker versus native config

Docker mounts three files over the `conf/import/` includes (`tools/docker/docker-compose.yml:24-26`, repeated for each service). Only these three are overridden. Login is not overridden.

| Key | Native (`conf/`) | Docker (`tools/docker/asset/char_conf.txt`) |
|---|---|---|
| `pincode_enabled` | yes | no |
| `char_name_option` | 1 | 0 |
| `char_del_delay` | 86400 | 0 |
| `new_account` | no | no (login not overridden) |

The Docker IP settings (`inter_conf.txt`, `map_conf.txt`) point at service names and do not change content.

The three Docker overrides exist only in the uncommitted working tree. At HEAD, `tools/docker/asset/char_conf.txt` sets only `login_ip` and `char_ip`, so Docker would use the native values.

## 8. Client UI priority

Ranked by how often a player touches each system per day. This is a judgement from the server's daily loops (login popups, mail, quests, party, gear upgrades), not measured data. Items at the bottom are optional.

1. Chat, party, inventory, storage, and Kafra/warp services. Kafra and warp NPCs are loaded (`npc/kafras`, `npc/re/kafras`, `npc/warps` 81, `npc/re/warps` 56).
2. Attendance login popup and the 20-day reward (`feature.attendance`, `db/re/attendance.yml`).
3. Mail (RODEX). The client opens it itself, the `openmail` NPC does not work at this PACKETVER. Mail fees and attachments apply.
4. Quest log and quest dialogs. 4867 quest entries; 154 quest NPC files loaded.
5. Party, including the share picker.
6. Refine, enchant, and socket UI. Frequent during gear progression.
7. Equipswitch. Frequent for gear swaps.
8. Roulette (daily bonus; client-opened).
9. Pets and homunculus status and autofeed (passive when autofeed is on, but open daily when owned).
10. Achievements (passive, reviewed now and then).
11. Guild and castle screens (weekly).
12. Mercenaries (rent NPC loaded).
13. Mounts and rental mounts (`renters.txt` loaded).
14. Stylist, dye, and costume screens (occasional).
15. Barter shops (occasional).
16. Private airship (occasional).
17. Navigation (occasional).
18. Buying store, search store, autotrade (occasional).
19. Clan (occasional). Bank is only reachable from one quest NPC (rare).
20. Battleground queue (weekends).
21. Item reform, Laphine upgrade and synthesis, hat effects (rare).
22. Cash shop: empty in this checkout. Skip the UI until data exists.
23. Auction: off. Skip.

## Known gaps in this checkout

- The cash shop has no items. `db/import/item_cash.yml` is header-only.
- `lutie` and `rockridge` have NPC scripts but no map, so those NPCs will not spawn.
- Account registration is off (`new_account: no`). The client cannot create accounts.
- Pincode is on natively and off under Docker, but the Docker override is uncommitted.
- Packet obfuscation is off only in the working tree. A client built against HEAD must match whichever setting the server runs.
- Bank is switched on, but its NPCs are not loaded.
