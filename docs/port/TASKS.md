# Tasks

Checklist for the port. IDs are stable; add new work at the end of the matching
phase. Mark a task done only when its acceptance check passes.

The direction changed on 2026-11-09 ([PLAN.md](PLAN.md) section 2): solo play
on this Mac, 1st and 2nd jobs, a thin fork. **Phase 7 is the current work, in
the order of PLAN.md section 7.** Phases 0 to 6 are the record of the original
plan; their open tasks carry a note saying what happens to them.

## Phase 0: Validation

- [x] P0-01 Install the Xcode Metal Toolchain, clone upstream with submodules,
  and build on macOS 27 arm64 with current Xcode.
- [x] P0-02 Extract `~/Downloads/kRO_FullClient_20210406.zip` and copy `data.grf`
  and `BGM` into the app's Local Client Files directory.
- [ ] P0-03 (reopened as P7-01: the embedded server is now the play path) Start the embedded local server and log in as a baseline.
- [x] P0-04 Confirm `GameClientView` exposes `serverAddress` and `serverPort` and
  passes them to `GameSession.Configuration`.
- [x] P0-05 Create a Docker test stack: rAthena master + MariaDB. See
  [DOCKER.md](DOCKER.md).
  - [x] P0-05a Clone rAthena and pin commit
    `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`.
  - [x] P0-05b Keep `BUILDER_CONFIGURE: "--enable-packetver=20211103"`.
  - [x] P0-05c Set `pincode_enabled: no`, `char_name_option: 0`, and
    `char_del_delay: 0` in `tools/docker/asset/char_conf.txt`.
  - [x] P0-05d (superseded: not needed, see P2-01) Add `#undef PACKET_OBFUSCATION` and
    `#undef PACKET_OBFUSCATION_WARN` to `src/custom/defines_post.hpp`, then
    rebuild.
  - [x] P0-05e Start `db`, run `builder` to completion, then start `login`,
    `char`, and `map`.
  - [x] P0-05f Verify ports 6900, 6121, and 5121 answer on `127.0.0.1`, and all
    three services stay running.
  - [x] P0-05g Insert the `test` account into the `login` table.
  - [x] P0-05h Record the rAthena commit and server config in the compatibility
    manifest.
- [x] P0-06 Point the client at `127.0.0.1:6900` and log in as `test`.
- [x] P0-07 Create a character and enter a map.
- [x] P0-08 Walk, chat, and attack for 10 minutes.
- [x] P0-09 Record unknown packets, disconnects, and missing UI.
- [x] P0-10 Count implemented packets against the 20211103 table.
- [x] P0-11 Write a go or no-go note in `RESEARCH.md`.

Acceptance: character spawns on the rAthena map and plays for 10 minutes.

## Phase 1: Fork hygiene

- [x] P1-01 Fork the repository and rename the app.
- [x] P1-02 Set a new bundle identifier and development team.
- [x] P1-03 Keep GPL-3.0 and upstream attribution in About and headers.
- [x] P1-04 Add `upstream` remote and document the sync procedure.
- [x] P1-05 Add a minimal `NOTICE` file for upstream and third-party code.
- [x] P1-06 (on `macos-26`: no macOS 15 image has the toolchain upstream needs) Add GitHub Actions build on `macos-15`, arm64, with submodules.
- [ ] P1-07 (continues as P7-08; job written; RagnarokGame does not compile on the runner's Xcode 26.6, the other ten packages pass) Add unit test job and cache Swift packages.
- [x] P1-08 Add an asset provisioning script that copies `data.grf` and `BGM`
  into the sandbox Documents directory and validates both.
- [x] P1-09 Add `.gitignore` rules for client assets and build output.
- [x] P1-10 Add issue templates for protocol, renderer, and UI bugs.
- [x] P1-11 Add a compatibility manifest template.

Acceptance: clean clone builds in CI and launches locally.

## Phase 2: Protocol

- [x] P2-01 Reproduce the obfuscation failure on stock rAthena.
- [x] P2-02 (not needed: zero keys at 20211103, stock server verified) Document and apply the `#undef PACKET_OBFUSCATION` change in
  `src/custom/defines_post.hpp` for the test server.
- [x] P2-03 Add a runtime `PACKET_VERSION` override with 20211103 default.
- [x] P2-04 Add a guard that rejects unsupported packet dates at startup.
- [x] P2-05 Extend unknown-packet logging with length and hex. The existing
  logger in `PacketDecoder` records the opcode and remaining bytes, then throws.
- [x] P2-06 Add a packet size sanity check and bounded read buffer.
- [x] P2-07 Add fragmented and coalesced TCP read tests.
- [x] P2-08 Generate golden packet fixtures from rAthena headers.
- [x] P2-09 Add golden tests for login, char, and map sessions.
- [x] P2-10 Implement and verify the pincode flow. Upstream only receives
  `PACKET_HC_SECOND_PASSWD_LOGIN` and does not reply.
- [x] P2-11 Verify character creation and deletion.
- [x] P2-12 Verify reconnect after a forced server restart.
- [x] P2-13 Add packet replay harness.
- [x] P2-14 Record a 60 minute session and count errors.

Acceptance: 60 minute session, no blocking unknown packet.

## Phase 3: Playable core

- [x] P3-01 Movement and pathfinding on GAT walkability.
- [x] P3-02 Map transitions, portals, and teleports.
- [x] P3-03 Chat: public, party, guild, whisper.
- [x] P3-04 Basic attack, damage, death, and respawn.
- [x] P3-05 Experience, level up, and stat points.
- [x] P3-06 Loot, drops, and item pickup.
- [x] P3-07 Inventory, equipment, and weight.
- [x] P3-08 NPC dialog, shops, and storage.
- [x] P3-09 Kafra save, teleport, and storage.
- [x] P3-10 Skill window, skill use, cooldowns.
- [x] P3-11 Ground targeting and area skills.
- [x] P3-12 Settings, keybinds, and window layout persistence.
- [x] P3-13 Audio: BGM and sound effects.
- [x] P3-14 Crash handling and local logs.
- [ ] P3-15 (gate G3; after P7-01 to P7-05) One hour playtest with a written bug list.

Evidence for P3-02 and P3-05..P3-13: headless `ro-probe --scenario core`, see
[core-verification.md](probe-runs/core-verification.md).

Acceptance: one hour of normal play with no blocking bug.

## Phase 4: Content

- [x] P4-01 List the target server's enabled jobs, maps, and systems.
- [ ] P4-02 (scope is now the 1st and 2nd jobs; effects are upstream's to build, see P7-14) Implement skills and effects for enabled jobs.
- [x] P4-03 (names from the server YAML as a generated snapshot; the kRO lub
  files are Korean only and not needed, see [localization.md](localization.md))
  Load item and skill DBs from the server's YAML and SQL tables and
  the kRO client's `System/*.lub` files.
- [x] P4-04 Localization for item, skill, and monster names.
- [x] P4-05 Party and guild windows.
- [x] P4-06 Friends and mail.
- [x] P4-07 (pets and homunculus; mounts and costumes not built) Pets, mounts, and costumes if enabled.
- [x] P4-08 Quest log and script dialogs used by the server.
- [x] P4-09 Cash shop and achievements only if enabled.
- [x] P4-10 Write a known-gaps list for release notes.

Acceptance: target server's daily content usable; gaps documented.

## Phase 5: Performance and release

- [ ] P5-01 (only for a spike seen while playing; no M1 is available, the developer Mac is an M4) Capture Metal frames on M1 for Prontera, Geffen, and an effect map.
- [ ] P5-02 (only for a spike seen while playing) Fix asset decode stalls and frame spikes.
- [ ] P5-03 (not planned: frame times are inside the target without it) Tune command buffers, state changes, and argument buffers.
- [x] P5-04 (M4, 144 Hz, 2560x1440: 143.9 fps after the refresh rate fix; see [perf.md](perf.md)) Verify 120 fps target and record results.
- [x] P5-05 (peak RSS 418 to 557 MB) Measure RSS with full kRO data; target under 4 GB.
- [x] P5-06 (1.1 to 2.8 s process start to first map frame) Measure cold start; target under 10 seconds.
- [ ] P5-07 Retina, fullscreen, window restore, display change.
- [x] P5-08 Input remapping and optional gamepad.
- [~] P5-09 (deferred: local-only project) Developer ID signing and hardened runtime.
- [~] P5-10 (deferred: local-only project) Notarize and staple the app.
- [~] P5-11 (deferred: local-only project) Build DMG with compatibility manifest.
- [~] P5-12 (deferred: local-only project) Publish GPL source archive for the exact binary.
- [x] P5-14 Write install guide: kRO files, server, PACKETVER, obfuscation.

Acceptance: local build meets the performance targets on the developer Mac. Signing and distribution are deferred.

## Phase 6: Maintenance

- [ ] P6-01 (weekly now, see P7-09. Checked 2026-11-09: upstream is 3 commits past the fork point `fe04817b`) Monthly upstream sync.
- [ ] P6-02 Re-run packet golden tests after every rAthena update.
- [ ] P6-03 Track rAthena default `PACKETVER`.
- [ ] P6-04 Keep the compatibility table current.
- [ ] P6-05 Triage crash reports and protocol regressions.

## Phase 7: Solo play on a thin fork (2026-11-09)

In working order. Feature work is frozen until gate G3 (P3-15).

Safety:

- [ ] P7-07 Push `integrate-m2` to `origin` and open a pull request into
  `main`. From then on push after every merged piece of work. `origin`
  (`fabianwgl/ro-mac-arm`) is a public repository, so a push publishes; decide
  first whether it stays public (PLAN.md section 2).
- [ ] P7-13 Remove the agent worktrees and branches whose commits are in
  `integrate-m2` (`git cherry` shows them as applied), and the two
  `backup/*-before-rewrite` branches once the push is confirmed. Check each
  worktree for uncommitted files first: one held the guild emblem work.

Gate G1, embedded baseline:

- [ ] P7-01 In the fork's build, start the embedded rAthena (Developer Tools,
  Server), create an account and a character, enter a map. Then run the probe
  against it (`--host 127.0.0.1` while the app is open): the 10-minute walk,
  chat and attack run, and as much of the core scenario as the embedded
  server's command set allows (its group 0 has `@item`, `@jobchange`,
  `@monster` and `@zeny` but not every command the scenario uses). Record
  in [COMPATIBILITY.md](COMPATIBILITY.md): the rAthena base of `swift-rathena`,
  Renewal or Pre-Renewal, and how its config differs from the Docker stack
  (group 0 has GM commands, `new_account: yes`, no pincode).

Play path:

- [ ] P7-02 Launcher: Play starts the embedded servers, waits until they
  accept connections and opens the login. The server address and port move to
  an advanced section and keep working for the Docker stack.
- [ ] P7-03 Decide Renewal or Pre-Renewal for play after trying both for a few
  minutes each. Record it in COMPATIBILITY.md. If Pre-Renewal: regenerate the
  name tables from `db/pre-re` (`scripts/gen-server-names.py`) and rerun the
  skill audit against `db/pre-re`.

Gate G2, GUI smoke:

- [ ] P7-04 `scripts/gui-smoke.sh`: launch the app with `RO_AUTOLOGIN_*`,
  capture the game window (`screencapture -l <window id>`), open each core
  window in turn (inventory, equipment, skills, status, options through their
  key bindings; an NPC dialog, a shop and storage through `RO_AUTOLOGIN_CMD`
  and clicks) and capture each. Screenshots go to `docs/port/gui-runs/<date>/`,
  which is gitignored: they show Gravity art and the repository is public.
- [ ] P7-05 Look at every screenshot and fix what is wrong. Known from the
  first capture: the status window and the window's close, minimize and zoom
  buttons overlap.

Gate G3 is P3-15.

Upstream:

- [ ] P7-08 Make the RagnarokGame test job pass on CI (was P1-07). First try
  `xcodebuild test` for that package instead of `swift test`: the app build
  already compiles the same sources on the runner.
- [ ] P7-09 First weekly merge of `upstream/master`
  ([UPSTREAM_SYNC.md](UPSTREAM_SYNC.md)). Three commits, one conflict in a
  trial merge: the display name line in `project.pbxproj`, keep the fork's
  side.
- [ ] P7-10 [patches.md](patches.md) lists every modified upstream file with a
  reason, generated from `git diff --diff-filter=M --numstat
  upstream/master...HEAD` and checked by hand. 69 files today, 7 rows.
- [ ] P7-11 Offer the fixes upstream, one pull request each, smallest first:
  the `RANKLIST` generator bug, the eight packets without a length, the friend
  reply size, the account id read on a short TCP read, the keepalive that
  shares a TCP read with `CZ_ENTER`, the 6-character login minimum, the 60 fps
  cap, NPC dialogs staying open after a map change. Each needs the developer's
  go before it is opened: it is a public pull request under the developer's
  account. `origin` is not a GitHub fork of upstream, so this also needs a
  real fork of `arkadeleon/ragnarok-offline` to push the branches to.
- [ ] P7-12 Ask upstream whether it wants the multiplayer systems (PLAN.md
  section 8) and the probe. If yes, split them into reviewable pull requests.
  If no, they stay frozen here.

Content inside the cap, after G3:

- [ ] P7-14 Close the v1.0 gaps in PLAN.md section 5, in this order and only
  where upstream has not done it (ownership rule, PLAN.md section 4):
  - [ ] P7-14a Job change walk-through: a Novice to each of the six 1st jobs
    through the job NPCs; each 2nd job with a character raised by commands.
    Probe scenario first, then by hand.
  - [ ] P7-14b Statuses the player cannot see: the option bits already stored
    on the object (stone, freeze, stun, poison, curse) and the buffs of the
    1st and 2nd jobs ([skill-effects.md](skill-effects.md) gap 2).
  - [ ] P7-14c Cart window for the Merchant.
  - [ ] P7-14d Remaining skill effects of the 1st and 2nd jobs, ground units
    first (Warp Portal, Safety Wall, traps), from the audit.

## Backlog

Not planned. Kept so the ideas are not lost.

- [ ] Implement `PACKET_OBFUSCATION` if the target server needs it.
- [ ] Add a packet editor or inspector window.
- [ ] Add a benchmarking scene.
- [ ] Multiplayer work that was next before 2026-11-09: guild position editing
  and alliances, clan, battlegrounds, search store, NPC chat rooms, mercenary
  window, refine and enchant windows (upstream ranks refine as its own work).

Dropped: a map viewer mode and a character simulator mode (upstream has
both), multi-client support for local testing (the probe does it).


## Status 2026-11-09

Evidence: [phase0-probe-report.md](phase0-probe-report.md), [packet-coverage.md](packet-coverage.md),
[core-verification.md](probe-runs/core-verification.md), the scenario runs in `probe-runs/`, [perf.md](perf.md),
[skill-effects.md](skill-effects.md), [KNOWN_GAPS.md](KNOWN_GAPS.md), package tests (`swift test` per package) and the
golden suite (`Packages/RagnarokPackets/Tests/RagnarokPacketsTests/GoldenPacketTests.swift`).

Nothing in Phase 7 is started. Open tasks of the earlier phases, with the reason:

- P0-03 embedded-server baseline: skipped in Phase 0 because the Docker server was the target. It is the play path
  now, so it is the first gate (P7-01).
- P1-07 CI unit tests: the last run (2026-11-06, `main`) built the app and passed ten test jobs. RagnarokGame fails to
  compile there: `#bundle` in the UI sources finds no resource bundle under `swift test` with Xcode 26.6. It compiles
  and passes with Xcode 27 locally. Nothing has been pushed since, so CI has not seen the later work.
- P3-15 one-hour playtest: needs a person at the app. Everything in Phase 3 is verified headless only.
- P4-02 skills and effects: 83 of the 224 active 1st and 2nd job skills have a skill specific effect, 3 of 45 ground
  unit skills are drawn, 2 of 89 statuses show more than an icon. Upstream's to build under the split; see P7-14.
- P5-01..P5-03 GPU capture, decode stalls, command buffer tuning: not started and not planned unless play shows a
  spike; the measured frame times are inside the target without them.
- P5-07 Retina, fullscreen, window restore, display change: not checked; part of the GUI smoke run and the playtest.
- P5-09..P5-12 signing, notarization, DMG, source archive: a non-goal now; `scripts/release.sh` works unnotarized.
- Attendance needs a server-side period in `db/import/attendance.yml`; the `openmail` NPC is broken server-side at this
  PACKETVER (menu and `@mail` work). Both are frozen systems.
