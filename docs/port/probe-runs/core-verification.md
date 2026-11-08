# Core gameplay verification: P3-02, P3-05..P3-11, P3-13

Date 2026-11-08. Headless `ro-probe --scenario core --with-audio` against the Docker rAthena stack (`ro-backend`, PACKETVER
20211103, Renewal, rAthena `d4b8e7b8`). Run JSON: `core-2026-11-08.json` (character `ProbeCore13`, fresh, account
`probecore` with `group_id` 99). Every check goes through the entry point the UI uses (`PlaySession` methods,
`MapScene.handleInteraction`, `PlaySession.useShortcut`), waits for the server's answer packet and for the client
state that packet changes. GM chat commands only set a situation up (`@item`, `@blvl`, `@skillpoint`, `@jobchange`,
`@monster`, `@killmonster`, `@zeny`, `@heal`, `@storage`), or are the thing under test (`@warp`). Details of the flags:
`Tools/ROProbe/README.md`.

Result: 9 of 9 tasks pass, 66 of 66 checks, 92.3 s, no disconnect, no unknown packet, no decode failure. The one
unimplemented packet in the run is `ZC_NAVIGATE_TO` (0x08e2), which none of these tasks needs. The same scenario passed on three more fresh characters in a row (`ProbeCore8` to `ProbeCore10`).

```sh
Tools/ROProbe/.build/debug/ro-probe --user probecore --pass probecore --char-name ProbeCore13 \
  --scenario core --with-audio --json docs/port/probe-runs/core-2026-11-08.json
```

## Results

Packet names are the plan's: `CZ_*` is what the client sent, `ZC_*` what the server answered. Counts are in the JSON,
per task (`packetsReceived`, `packetsSent`).

| Task | What was done | Packets seen | Result | Notes |
| --- | --- | --- | --- | --- |
| P3-07 Inventory, equipment, weight | `@item` adds 10 Red Potions, a spare Knife and a Cotton Shirt. Weight rises by 10 x 70, a potion is used (weight falls by 70). The spare knife is equipped, the worn shirt is taken off and put on again. | `ZC_ITEM_PICKUP_ACK`, `ZC_PAR_CHANGE` (weight), `CZ_USE_ITEM`, `ZC_USE_ITEM_ACK`, `CZ_REQ_WEAR_EQUIP`, `ZC_REQ_WEAR_EQUIP_ACK` x2, `CZ_REQ_TAKEOFF_EQUIP`, `ZC_REQ_TAKEOFF_EQUIP_ACK` | pass 9/9 | A new character already wears a Knife and a Cotton Shirt. Max weight 20300. |
| P3-05 Experience, level up, stat points | Four Porings killed one at a time with `MapScene.attackMonster` (it walks into range, then repeats `CZ_REQUEST_ACT`). Base exp rises per kill, the fourth kill fills the bar: level 1 to 2, status points 48 to 51. One STR point spent with `incrementStatusProperty`. | `CZ_REQUEST_ACT` x11, `ZC_NOTIFY_EXP` x8, `ZC_LONGLONGPAR_CHANGE`, `ZC_PAR_CHANGE`, `CZ_STATUS_CHANGE`, `ZC_STATUS_CHANGE_ACK`, `ZC_COUPLESTATUS` | pass 6/6 | A Poring gives 150 base exp here. STR 1 to 2 costs 2 points. Natural level up, `@blvl 1` was not needed. |
| P3-06 Loot, drops, pickup | The monster drop (Jellopy) is tapped on the ground and picked up. Two thrown potions are dropped with `throwItem`, the character walks 4 or more cells away, taps the floor item, walks back (6 cells in the evidence run) and picks it up. | `packet_dropflooritem` (the floor item packet, `ZC_ITEM_FALL_ENTRY`), `CZ_ITEM_PICKUP`, `ZC_ITEM_PICKUP_ACK`, `ZC_ITEM_DISAPPEAR`, `CZ_ITEM_THROW`, `ZC_ITEM_THROW_ACK`, `CZ_REQUEST_MOVE` | pass 5/5 | Porings loot the floor on this server, so the hunt keeps one Poring alive at a time. |
| P3-10 Skill window, skill use, cooldowns | `@skillpoint`, Basic Skill 0 to 9 and later Bash 5, Magnum Break 1 through `upgradeSkillLevel`. `@jobchange 1` replaces the skill list. Bash cast on a Poring through `useShortcut`. Magnum Break reports a 2.0 s cooldown. | `CZ_UPGRADE_SKILLLEVEL` x15, `ZC_SKILLINFO_UPDATE` x15, `ZC_SKILLINFO_LIST`, `CZ_USE_SKILL`, `ZC_NOTIFY_SKILL`, `ZC_SKILL_POSTDELAY`, `ZC_PAR_CHANGE` (SP 72 to 64) | pass 8/8 | The server (`player_skillup_limit`) offers first-job skills only after Basic Skill 9. `@jobchange` takes the job id (`1`), not a name. |
| P3-11 Ground targeting, area skills | `@jobchange 2`, Cold Bolt 1, Lightning Bolt 4, Thunderstorm 1. Thunderstorm on a selected Poring (the client walks into range, sends the monster's cell) and with nothing selected (own cell). The cell is read from the sent frame. | `CZ_USE_SKILL_TOGROUND` (0x0366) x2, `ZC_USESKILL_ACK` (cast), `ZC_NOTIFY_GROUNDSKILL` x2, `ZC_NOTIFY_SKILL`, `ZC_SKILL_DISAPPEAR` | pass 6/6 | The client sees the skill flag 2 as ground targeted. `MapScene` created 2 to 3 effects per cast. A monster that hits the caster interrupts the cast; the scenario kills the room first and recasts up to 3 times if it happens. |
| P3-08 NPC dialog, shops, storage | `@warp prt_in`, tap the Tool Dealer (126,76): buy or sell choice, buy list, 5 Red Potions and 3 Fly Wings bought, zeny 20000 to 19200 (list price 5 x 10 + 3 x 250). Sell list, 2 potions sold (+10 zeny). `@storage`, 3 potions in and out, close. NPC dialog text, next, menu and cancel are in the Kafra run (P3-09). | `CZ_CONTACTNPC`, `ZC_SELECT_DEALTYPE`, `CZ_ACK_SELECT_DEALTYPE`, `ZC_PC_PURCHASE_ITEMLIST`, `CZ_PC_PURCHASE_ITEMLIST`, `ZC_PC_PURCHASE_RESULT`, `ZC_PC_SELL_ITEMLIST`, `CZ_PC_SELL_ITEMLIST`, `ZC_PC_SELL_RESULT`, `ZC_INVENTORY_START` (storage), `CZ_MOVE_ITEM_FROM_BODY_TO_STORE`, `ZC_ADD_ITEM_TO_STORE`, `CZ_MOVE_ITEM_FROM_STORE_TO_BODY`, `ZC_DELETE_ITEM_FROM_STORE`, `CZ_CLOSE_STORE` | pass 13/13 | Zeny in the client equals the list price maths at each step. |
| P3-09 Kafra save, teleport, storage | Prontera Kafra (151,29): dialog text, Next, menu, Cancel (`CZ_CHOOSE_MENU` 255). Then Save (DB save point `prontera 150,33`), Use Storage (40 zeny, put and take 3 potions), Use Teleport Service to Geffen (1200 zeny, lands on `geffen 120,39`). | `ZC_SAY_DIALOG`, `ZC_WAIT_DIALOG`, `CZ_REQ_NEXT_SCRIPT`, `ZC_MENU_LIST`, `CZ_CHOOSE_MENU`, `ZC_CLOSE_DIALOG`, `CZ_CLOSE_DIALOG`, `ZC_INVENTORY_START`, `ZC_NPCACK_MAPMOVE` | pass 10/10 | The teleport menu lists `Izlude -> 600 z`, `Geffen -> 1200 z`, `Payon`, `Morocc`, `Orc Dungeon`, `Alberta`. Storage needs Basic Skill 6 (the character has 9). |
| P3-02 Map transitions, portals, teleports | In Geffen: Fly Wing (same map, new cell 120,39 to 74,77) and a walk afterwards. Butterfly Wing (another map: Prontera 150,33, the Kafra save point; the DB holds the same cell). `@warp prt_fild08 170 200`. `@warp prt_in`, `@warp prontera` and the Kafra teleport in P3-08 and P3-09 were also map changes. | `CZ_USE_ITEM`, `ZC_USE_ITEM_ACK`, `ZC_AUTORUN_SKILL`, `CZ_USE_SKILL`, `ZC_USESKILL_ACK`, `ZC_NPCACK_MAPMOVE`, `CZ_NOTIFY_ACTORINIT`, `ZC_MAPPROPERTY_R2`, `CZ_REQUEST_MOVE`, `ZC_NOTIFY_PLAYERMOVE` | pass 4/4 | The wings are `itemskill AL_TELEPORT`: the server sends `ZC_AUTORUN_SKILL` and the client casts the skill itself. Walking after the jump works. Warp by click was verified earlier. |
| P3-13 Audio (headless) | `--with-audio` makes the resource provider answer audio requests and record them. The client asked for 4 BGM files and 16 sound effects over the run. The BGM of each map the run visited is looked up in `mp3nametable.txt` and decoded with `AVAudioPlayer`. Every requested wav is decoded with the client's own `AVAudioPCMBuffer.buffer`. | none (resource requests, not packets) | pass 5/5 | All 4 BGM files (`08`, `12`, `13`, `88`.mp3, 148 to 274 s long) and all 16 wavs resolved and decoded, none missing. The UI button sound and `_heal_effect.wav` decode too. Preferences were off for the run, so nothing was played. Playback and mixing are for a human. |

## Findings

- One client bug showed up (the Kafra window staying open after the warp, below); nothing else needed a package change.
- The first failing runs were probe bugs, fixed in the scenario: `@jobchange` wants the job id; first-job skills appear
  only after Basic Skill 9; Porings loot the drops, so the hunt spawns one at a time; Thunderstorm is interrupted when
  a monster hits the caster.
- The Kafra teleport script ends with `warp` then `end;`, so rAthena frees the script at once (`end` sends
  `ZC_CLOSE_DIALOG`, and `script_free_state` clears `sd->npc_id`); the server never refused a walk or an item after it.
  The client did: it kept the Kafra window with its Close button on the new map. Fixed in `PlaySession`: a map move
  closes the dialog, and the `ZC_CLOSE_DIALOG` that follows is answered with `CZ_CLOSE_DIALOG` (see
  `kafra-warp-2026-11-08.json`, P3-09 13/13: window closed, walk and Red Potion work with no click). The scenario no
  longer presses the window after the warp.
- A headless run cannot judge: window layout and drag and drop in the inventory, equipment, shop, storage and skill
  windows, the shortcut bar and cooldown overlay, the look of skill effects, and BGM and effect playback.

## Not covered

Fire Wall (Thunderstorm stands in for the ground skill), party and guild skills, mounts, Pushcart rental, Kafra Check
Other Information, selling equipped items, storage password, `ZC_NAVIGATE_TO`. Dev characters `ProbeCore6` to
`ProbeCore13` exist on the server; account `probecore` can be reused (`--char-name` with a new name for a fresh run,
and a pause of about 15 s between runs).

## Re-run on the integrated tree

2026-11-08, branch `integrate-m2` after the trade, vending, localization, WASD and gamepad merges, fresh character
`ProbeCore14`: 8 of 9 tasks passed in the full run. P3-10 failed once: the server answered the first Bash with
nothing (no `ZC_NOTIFY_SKILL`, no `ZC_ACK_TOUCHSKILL`, SP unchanged), most likely because the request came inside
the attack delay left by the loot task. `--tasks P3-10` on the same character passed 7 of 7 right after (Bash spent
8 SP). The scenario does not wait for the attack delay before its first skill yet.
