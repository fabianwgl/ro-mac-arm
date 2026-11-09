# Plan: Native macOS Ragnarok Online Client

Revised 2026-11-09 after a direction review. The original plan (a client for a
private multiplayer rAthena server, phases with week estimates) is in git
history at `f52bf996`. What changed and why is in section 2.

## 1. Goal

One person plays Ragnarok Online on this Mac, alone, in a native client:
Swift 6, Metal, arm64, macOS 15 or newer.

The player starts the app, presses Play, and can take a character of any 1st
or 2nd job from Novice to its job change and on: walk, fight, loot, use skills,
talk to NPCs, buy and sell, store items, change equipment. No Docker, no
database setup, no second machine.

## 2. Decisions

Taken on 2026-11-09. Each one replaces an assumption of the original plan.

| Decision | Was | Now |
| --- | --- | --- |
| Audience | "A private rAthena server", players unspecified | Solo, local only. No friends server, no public release |
| Content cap | "The content the target server enables", which on a stock rAthena is everything (172 job keys, 78 instances) | 1st and 2nd jobs: Novice, the six 1st jobs and the 2nd jobs they change into. Nothing transcendent, 3rd, 4th or expanded |
| Upstream | "Keep local patches small", while the fork grew by 68,000 lines | Split the work. Upstream owns single-player content. The fork owns the macOS shell, the verification tools and fixes. Merge upstream weekly and offer fixes back |

One thing follows from the first decision and is proposed, not yet proven
(gate G1 in section 6):

- **Play against the embedded server.** Upstream's app already contains real
  rAthena (`swift-rathena`: login, char, map and web servers in the app
  process, SQLite save data, Renewal and Pre-Renewal builds, PACKETVER
  20211103). The fork never tried it (P0-03 was skipped) and hid it behind
  Developer Tools. For a solo player it removes Docker, MariaDB and the
  account SQL. The Docker stack stays as the reference server for the probe
  and the golden tests, not as something the player needs.

Open, to decide after the first playtest:

- Renewal or Pre-Renewal for play. The embedded server has both. Every check
  so far ran on Renewal.
- The look of the windows. They are upstream's SwiftUI windows with touch
  style buttons, not the classic skin. Whether that is good enough is a
  judgement only a player can make.

Open, to decide before the next push:

- Whether the repository stays public. `fabianwgl/ro-mac-arm` is public and
  is not a GitHub fork of upstream. "No public release" and a public
  repository can coexist (GPL source, no assets in it), but every push
  publishes the work, the docs and the probe runs.

## 3. Non-goals

- Multiplayer. Party, friends, guild, trade, vending, buying stores, chat
  rooms and mail are built and stay in the tree with their tests, but get no
  further work (section 8).
- Transcendent, 3rd and 4th jobs, expanded classes, instances, War of
  Emperium, battlegrounds, cash shop.
- A release for other people: signing, notarization, DMG, source archive,
  install guide for strangers. `scripts/release.sh` stays as it is.
- Official Ragnarok Online servers. Their anti-cheat blocks third-party
  clients.
- iOS or visionOS. Upstream supports them; this fork only builds macOS arm64.
- Bundling Gravity assets. The user supplies kRO files.
- A new renderer, engine or UI framework.

## 4. Strategy

### Stay a thin fork

Upstream (`arkadeleon/ragnarok-offline`, GPL-3.0) is one active maintainer
working toward the same solo game: about 150 commits a month, most of them in
`RagnarokGame`, and a written roBrowser parity list
([ROBROWSER_PARITY.md](../ROBROWSER_PARITY.md)) ordered for a single player on
the embedded server. Its order: combat and growth first, then skill effects,
cart, pets, quests and settings, then homunculus, refine and navigation, and
everything multiplayer last.

So the same work should not be done twice:

| Area | Owner | Rule for the fork |
| --- | --- | --- |
| Renderer, effects, sprites, file formats | Upstream | Take it from the weekly merge. Do not build here |
| Single-player windows and systems (skills, cart, pets, quests, refine, navigation, status icons) | Upstream | Same. Exception below |
| macOS shell: launcher, keyboard, mouse, gamepad, preferences, window behavior, refresh rate | Fork | Build here, in the app target or in new files |
| Verification: probe, golden packet tests, perf harness, GUI smoke run | Fork | Build here, under `Tools/` and `scripts/` |
| Bugs in upstream code found by those tools | Fork finds, upstream owns | Fix here, list in [patches.md](patches.md), offer upstream as a pull request |
| Multiplayer windows already built | Fork | Frozen. Keep the tests green through merges |

Exception: an item inside the content cap that the v1.0 definition needs and
that upstream has not started four weeks after gate G3 is built here, in new
files, and offered upstream. Upstream's pace on effects has been slow (23
skills had an effect when the parity list was written on 2026-09-30 and still
at the fork point), so this exception is likely to be used for them.

New code goes into new files (`PlaySession+Guild.swift` is the pattern).
Edits to upstream files stay small hooks. Today 69 upstream files are
modified; that number should fall as fixes land upstream, not rise.

### Two servers, two jobs

- **Embedded rAthena** (in the app): what the player uses.
- **Docker rAthena** (`ro-backend`, pinned commit, see [DOCKER.md](DOCKER.md)):
  a stock reference the headless probe runs against, with real accounts and
  two-client scenarios. Development only.

They are different rAthena snapshots. A result measured on one is not proof
for the other until P7-01 records the embedded server's base and repeats the
core scenario on it.

### Verification ladder

Evidence so far stops at step 2. A feature counts as done only at step 4.

1. Unit and golden packet tests (`swift test` per package).
2. Headless probe against a live server: the real `GameSession` and
   `PlaySession`, no window ([core-verification.md](probe-runs/core-verification.md)).
3. Scripted GUI run of the real app: auto login, one screenshot per window.
   Window capture and UI scripting work on this Mac (checked 2026-11-09).
4. A person plays.

## 5. Definition of v1.0

All of these, on this Mac, against the embedded server:

- Play is one click from the launcher: the server starts, the account exists
  or is created, the character list appears.
- A Novice reaches job level 10, changes job through the job NPC, and plays
  on. Checked for all six 1st jobs; the change to each 2nd job checked with a
  character raised by commands.
- Every active skill of the 1st and 2nd jobs can be cast and shows that it
  was cast: animation, damage or heal numbers, and for a status the player
  can see that it is on. A skill specific effect is wanted, not required.
- Inventory, equipment, NPC shops, storage and Kafra services work by mouse
  and keyboard. A Merchant can use a cart.
- Settings, key bindings and the saved login persist.
- One hour of play with no crash, no disconnect and no window that cannot be
  closed. The bug list from that hour is written down and has no blocking
  entry.
- Frame rate at the display's refresh rate, RSS under 4 GB, first map frame
  in under 10 s. Already met ([perf.md](perf.md)).

## 6. Gates

Feature work is frozen until G3. The gates are in order.

| Gate | Passes when | Task |
| --- | --- | --- |
| G1 Embedded baseline | The fork's build starts the embedded server, logs in, and the probe's core scenario passes against it | P7-01 |
| G2 GUI smoke | A script launches the app and saves a screenshot of the map and of each core window, and each screenshot has been looked at | P7-04, P7-05 |
| G3 Playtest | The developer plays one hour and writes the bug list | P3-15 |

If G1 fails for a reason that is not a small fix, the player keeps using the
Docker server and the launcher keeps its address field. Nothing else in this
plan changes.

## 7. Work, in order

Task ids are in [TASKS.md](TASKS.md), Phase 7.

1. **Safety.** Decide public or private, then push `integrate-m2`. Remove
   the merged agent worktrees and branches. (P7-07, P7-13)
2. **G1.** Embedded baseline. (P7-01)
3. **Play path.** Launcher Play starts the embedded server and logs in; the
   external address becomes an advanced option. (P7-02, P7-03)
4. **G2.** GUI smoke script, then fix what the screenshots show. (P7-04,
   P7-05)
5. **G3.** Playtest. Fix blocking bugs. (P3-15)
6. **Upstream.** First weekly merge. CI green. Divergence list. Pull requests
   for the fixes. (P7-08 to P7-12)
7. **Content inside the cap,** only where the playtest or the v1.0 list shows
   a gap and the ownership rule allows it: job change walk-through, statuses
   the player cannot see, cart window, remaining skill effects. (P7-14)
8. **Performance** only for a spike seen while playing. (P5-01 to P5-03,
   P5-07)

## 8. Frozen work

Built before the direction changed. Each has unit tests and a live probe run
or a live check. They stay, they are kept compiling and passing through
merges, and nothing is added to them.

- Party, friends, whisper, party and guild chat.
- Guild window: info, members, positions, skills, notice, emblem.
- Trade, vending, buying stores, chat rooms.
- RODEX mail, achievements, attendance.
- Map-server hand-off, reconnect, pincode.

This is about half of the source the fork added (10,800 of 21,600 lines
outside tests, tools and docs). Upstream ranks the multiplayer part last and
has not built it, so it is the part of the fork most worth offering upstream
(P7-12).

## 9. Milestones

| Milestone | Scope | Status 2026-11-09 |
| --- | --- | --- |
| M0 | Build upstream, log in to Docker rAthena | Done |
| M1 | Walk, chat, attack on rAthena | Done |
| M2 | Playable core, proven by a person | Headless proof complete. Open: gates G1 to G3 |
| M3 | Content for 1st and 2nd jobs | Skills cast and show numbers; 83 of 224 have a skill specific effect, 2 of 89 statuses are visible beyond an icon. Job changes not walked |
| M4 | v1.0 as defined in section 5 | Performance met. The rest follows M2 and M3 |

No week estimates. The original ones (11 to 18 weeks to a playable core) did
not describe the pace: Phases 0 to 4 took four days of agent work. What is
slow is not building but looking: nothing has been seen by a person yet.

## 10. Licensing

- Upstream is GPL-3.0. The fork stays GPL-3.0.
- Gravity assets are never committed.
- Code or data taken from `roBrowserLegacy` (GPL-3.0) or `Korangar` (MIT) is
  recorded in `NOTICE`.
- No distribution is planned. If that changes, the GPL source and asset rules
  of the original plan apply again.

## 11. Maintenance

- Weekly upstream merge ([UPSTREAM_SYNC.md](UPSTREAM_SYNC.md)).
- Golden packet tests after every rAthena change, embedded or Docker.
- [COMPATIBILITY.md](COMPATIBILITY.md) records both servers.
- Push after every merged piece of work. Work that exists on one disk is the
  largest avoidable risk this project carries ([RISKS.md](RISKS.md) R18).

## 12. Progress

Status on 2026-11-09. Work is on the local branch `integrate-m2`, more than
50 commits ahead of `main`. `main` equals `origin/main`: upstream at the fork
point plus PR #1 (`github.com/fabianwgl/ro-mac-arm`). It does not mirror
`upstream/master`; the `upstream/master` ref does that.
Per-task status with evidence is in [TASKS.md](TASKS.md); open content in
[KNOWN_GAPS.md](KNOWN_GAPS.md).

### Done

- Phase 0: upstream builds on macOS 27 / Xcode 27 after installing the Metal
  toolchain. The rAthena Docker stack runs as `ro-backend` at the pinned commit.
  A headless probe (`Tools/ROProbe`) drives the real `GameSession`. A 10-minute
  login, create, walk, chat and attack run passed with 0 disconnects.
  Packet coverage is in [packet-coverage.md](packet-coverage.md).
- Phase 1:
  - The app is renamed `RO Mac Client` (`tech.thecapy.ro-mac-client`) and opens
    on a launcher; the upstream tools sit behind View > Developer Tools.
  - Fork files: NOTICE, an asset-safe `.gitignore`, issue templates, the
    compatibility manifest, `scripts/provision-assets.sh`, the upstream sync
    doc and `patches.md`.
  - CI on `macos-26` builds the app and runs the package tests. The app build
    and ten of the eleven test jobs pass; the RagnarokGame job does not (see
    Open problems).
- Phase 2:
  - Packet handling: a packet-date guard, decoder hardening (hex logging,
    bounded buffer, fragmented and coalesced read tests) and a replay recorder.
  - Golden tests compiled from the rAthena headers.
  - Pincode, character delete, reconnect after a server restart, all verified
    against the live server.
  - A 60-minute soak with 0 errors.
  - Obfuscation needs no work: rAthena's keys are zero at 20211103.
  - Client bugs fixed:
    - `CZ_ENTER` shared a TCP write with the next packet.
    - Eight server packets had no length.
    - `RANKLIST` had the wrong size.
    - The friend reply packet had the wrong size.
    - The account id read dropped bytes on a short TCP read.
    - Login required 6-character credentials.
- Phase 3:
  - Clicking warps and NPCs. NPC dialogs close on a map change.
  - macOS keyboard controls with rebinding, WASD walking, game controller.
  - Sound and display preferences. The saved password lives in the Keychain.
  - A crash marker and log export.
  - Map changes, experience, loot, inventory, NPC shops and storage, Kafra,
    skills, ground skills and audio verified by the probe's core scenario:
    66 of 66 checks ([core-verification.md](probe-runs/core-verification.md)).
- Phase 4:
  - An inventory of the Docker server's content ([server-content.md](server-content.md)).
  - Pets and homunculus windows, quest log.
  - Item appraisal and cart moves.
  - English names for every server item, skill and monster
    ([localization.md](localization.md)).
  - Skill effects: an audit of the 224 active skills of the 1st and 2nd jobs,
    83 with a skill specific effect, ground units for three skills
    ([skill-effects.md](skill-effects.md)).
  - The systems in section 8.
- Phase 5:
  - `scripts/perf-run.sh` measures fps, memory and cold start unattended. On
    the developer Mac (M4, 144 Hz, 2560x1440): 143.9 fps, peak RSS under
    600 MB, 1.1 to 2.8 s to the first map frame ([perf.md](perf.md)). The map
    view draws at the display's refresh rate instead of 60 fps.

### Open problems

- No person has played the client. Every check is headless: the probe calls
  the same entry points as the UI but draws nothing. The first screenshot of
  the real window (2026-11-09) already showed one defect the probe cannot
  see: the status window and the window's close, minimize and zoom buttons
  overlap.
- The play path the plan now depends on, the embedded server, has never been
  run in this fork.
- CI is red. `swift test` for RagnarokGame does not compile on the runner's
  Xcode 26.6: the `#bundle` macro in the UI sources finds no resource bundle.
  It compiles with Xcode 27 on the developer Mac. CI has not run since
  2026-11-06 because nothing was pushed.
- The work since PR #1 exists only on this Mac.
- Upstream moved three commits past the fork point on 2026-11-09. A trial
  merge has one conflict, in `project.pbxproj`.
- Half of the fork's source is the frozen work of section 8. It costs merge
  effort and gives a solo player nothing unless upstream takes it.

### Server notes found during the work

- Attendance: no period is active in `db/re/attendance.yml`. Add one to
  `db/import/attendance.yml` to use the feature.
- The `openmail` NPC fails at this packet date after it takes 130 zeny.
  Use the menu or `@mail`.
