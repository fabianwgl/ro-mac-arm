# Known gaps

Release-notes list for RO Mac Client against rAthena `d4b8e7b8`, PACKETVER
20211103 (plan task P4-10). Scope is the content the target server enables
([server-content.md](server-content.md)), not full kRO parity. The detailed
per-packet backlog is upstream's [ROBROWSER_PARITY.md](../ROBROWSER_PARITY.md).

## Works

- Login, pincode (enter, create, change), character create/select/delete,
  map entry, reconnect after a server restart.
- Walk, map change, map-server handoff (`ZC_NPCACK_SERVERMOVE`), warp portals
  by click.
- Public, whisper (`/w`, To field), party (`%`) and guild (`$`) chat.
- Attack, damage, death, respawn, experience, stat points, skills, ground
  skills, hotkey bar (upstream).
- Inventory, equipment, drops, pickup, NPC dialogs, shops, storage, Kafra menus
  (upstream).
- Party window (create, invite, accept, leave, kick, leader, member HP and
  minimap dots), friends window, quest log, attendance window (`ZC_UI_OPEN`,
  `CZ_OPEN_UI`, `CZ_REQ_CHECK_ATTENDANCE`).
- Guild window (Menu, Guild): create (needs an Emperium), invite by name and
  accept or decline an invitation, members with position, level, job and
  online state (login and logout live), expel, leave, disband (master, empty
  guild), position names and permissions, notice (read, and edit as master),
  alliance and hostile guild lists (read only), expulsion list.
- Pet window (status, feed, performance, return to egg, unequip accessory,
  rename, auto feed) and the egg list a pet incubator opens; homunculus window
  (status, feed, rename, delete, call, vaporize, resurrect, auto feed, skill
  list). Menu buttons, Option-J and Option-R.
- Trade with another player: request (select a player, then the action button or
  `/exchange`), accept or decline, offer items and zeny, OK, Trade, cancel, and
  the ack messages (too far, overweight, inventory full). Verified live between
  two clients ([trade-2026-11-08.json](probe-runs/trade-2026-11-08.json)). Items
  are offered from a picker, not by drag and drop.
- Chat rooms: create from the menu or `/chat [title]` (title, limit, public or
  private with a password), click the owner or the sign to join, a password
  prompt for private rooms, room window with members, messages, leave, and the
  owner's settings, expel and give owner. Verified live between two clients
  ([chatroom-2026-11-08.json](probe-runs/chatroom-2026-11-08.json)).
- NPC dialogs close on a map change, so a Kafra teleport (`warp` then `end`)
  leaves no window on the new map.
- Vending: click a vendor or the sign above the head to browse and buy; the
  Vending skill opens the set up window (cart items, prices, title) and your
  own shop window closes it. Buying store: click a buyer to sell to them; the
  license item (12548) opens the set up window. Cart lists, add and remove.
  Verified live between two clients
  ([vending-2026-11-08.json](probe-runs/vending-2026-11-08.json)).
- macOS keyboard controls with rebinding, WASD walking and Space to attack the
  nearest monster (the third hotkey row is Option-1..9), game controller (left
  stick and d-pad walk, A attack, B close window, X/Y/shoulders/triggers hotkey
  row 1, Menu options; fixed layout, not tried on a physical pad yet), sound and
  display preferences, saved password in the Keychain, crash marker and log
  export, launcher.

## Gaps on the target server

| Area | Server state | Client state |
| --- | --- | --- |
| Guild window: skills, emblem image, editing positions and member positions, alliance and hostility requests, castle info, member dots on the minimap | enabled | Info, Members, Positions and Notice tabs work (see Works); skills (`ZC_GUILD_SKILLINFO`), `ZC_GUILD_EMBLEM_IMG`, `CZ_REG_CHANGE_GUILD_POSITIONINFO`, `CZ_REQ_CHANGE_MEMBERPOS`, `CZ_REQ_ALLY_GUILD`/`CZ_ALLY_GUILD`/`CZ_REQ_HOSTILE_GUILD` and `ZC_GUILD_AGIT_INFO` are not used; an incoming alliance request only prints a chat line |
| Pets, homunculus, mercenaries | enabled | pet and homunculus windows and commands done (see Works); missing: taming (`ZC_START_CAPTURE`, `CZ_TRYCAPTURE_MONSTER`), pet evolution (`CZ_PET_EVOLUTION`), pet emotes and talk (`ZC_PET_ACT`), homunculus skill upgrade, attack and move orders, homunculus Lua AI; mercenary packets are not handled and there is no mercenary window |
| RODEX mail | enabled | mailbox window (Mail and Account tabs, list, read, take zeny and items, delete, reply), write window (name check, title, text, zeny, up to 5 items), unread icon and message. Opened from the menu mail button or `@mail`: the `openmail` NPC cannot open it at this PACKETVER (`BUILDIN_FUNC(openmail)` only logs that it is unsupported, after the NPC took 130 zeny). Not done: returning a mail (rAthena ignores `CZ_RODEX_RETURN`), the "all mails" account requests (`CZ_OPEN_ALL_RODEX`, none in rAthena) |
| Achievements | enabled | menu window, claim button and completion message work; titles need `System/achievement_list.lub` in the client folder, else rows read "Achievement #id"; no title wearing |
| Attendance | feature on, but `db/re/attendance.yml` has no running period (the 2018 example is commented out), so the server never opens the window or accepts a check-in until a period is added to `db/import/attendance.yml` | window, menu entry and check-in implemented; day numbers only (the server sends no period dates or reward table, reward arrives by mail); untested against the live server for lack of a period |
| Navigation (`ZC_NAVIGATION_ACTIVE` 0x08e2) | enabled | framed and skipped |
| Clan | enabled | missing |
| Chat room extras | enabled | rooms owned by NPCs (arena and PK waiting rooms, `waitingroom` script command) are not shown or joinable; passwords are capped at 7 bytes because rAthena compares 9 bytes of an 8-byte field |
| Vending and buying store extras | enabled | no "Move to cart" in the inventory item menu (the shop set up window has "To cart"); signs are text labels, not the signboard art; a title that is not UTF-8 drops the sign; shop rows show refine but not cards; search store (`CZ_SEARCH_STORE_INFO`) not done |
| Refine, enchant, item reform, Laphine, stylist, roulette | enabled | missing |
| Bank | one NPC only | missing |
| Cash shop | code on, no items | missing (nothing to buy) |
| Battlegrounds | maps loaded | `ZC_BATTLEFIELD_*` framed, no UI |
| Reputation (`ZC_REPUTE_OPEN`) | enabled | framed and skipped |
| Character rename, slot move | enabled | framed, no UI |
| Names and descriptions | n/a | English names for every server item, skill and monster (locale table, then English table, then the server's English name; see [localization.md](localization.md)); 203 of 1,265 maps show the map file name; 384 skills have no English description and show the Aegis name; no appraisal (Magnifier) window, so unidentified drops stay unidentified; refine and slot suffixes are not drawn in names |
| Window position persistence | n/a | game windows are fixed-layout SwiftUI; main and game windows use macOS defaults |

## Not verified on this machine

- Visual check of the play UI by a person for one hour (P3-15). Protocol-level
  soak runs pass; see [phase0-probe-report.md](phase0-probe-report.md).
- Metal GPU capture, 120 fps on M1, RSS and cold-start targets (P5-01..P5-06):
  the build Mac is an M4; numbers are not recorded yet.
