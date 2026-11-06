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
- macOS keyboard controls with rebinding, sound and display preferences, saved
  password in the Keychain, crash marker and log export, launcher.

## Gaps on the target server

| Area | Server state | Client state |
| --- | --- | --- |
| Guild window (members, positions, skills, emblem, alliances) | enabled | guild chat only; `ZC_ACK_CHANGE_GUILD_POSITIONINFO` and `ZC_ACK_REQ_CHANGE_MEMBERS` are framed and skipped |
| Pets, homunculus, mercenaries | enabled | no windows or commands |
| RODEX mail | enabled | no window in the play UI |
| Achievements | enabled | packets ignored, no window |
| Attendance | feature on, but `db/re/attendance.yml` has no running period (the 2018 example is commented out), so the server never opens the window or accepts a check-in until a period is added to `db/import/attendance.yml` | window, menu entry and check-in implemented; day numbers only (the server sends no period dates or reward table, reward arrives by mail); untested against the live server for lack of a period |
| Navigation (`ZC_NAVIGATION_ACTIVE` 0x08e2) | enabled | framed and skipped |
| Clan, chat rooms, trade, vending, buying store | enabled | missing |
| Refine, enchant, item reform, Laphine, stylist, roulette | enabled | missing |
| Bank | one NPC only | missing |
| Cash shop | code on, no items | missing (nothing to buy) |
| Battlegrounds | maps loaded | `ZC_BATTLEFIELD_*` framed, no UI |
| Reputation (`ZC_REPUTE_OPEN`) | enabled | framed and skipped |
| Character rename, slot move | enabled | framed, no UI |
| Gamepad | n/a | not implemented |
| Window position persistence | n/a | game windows are fixed-layout SwiftUI; main and game windows use macOS defaults |

## Not verified on this machine

- Visual check of the play UI by a person for one hour (P3-15). Protocol-level
  soak runs pass; see [phase0-probe-report.md](phase0-probe-report.md).
- Metal GPU capture, 120 fps on M1, RSS and cold-start targets (P5-01..P5-06):
  the build Mac is an M4; numbers are not recorded yet.
- Notarization (P5-10): needs the maintainer's `notarytool` keychain profile.
- Install on a clean Mac by a second person (P5-13).
