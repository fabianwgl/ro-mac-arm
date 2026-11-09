# Plan: Native macOS Client for rAthena

## 1. Goal

Build a native macOS client for a private rAthena server. Swift 6, Metal, arm64,
macOS 15 or newer. It must log in, create and select a character, enter a map,
move, chat, fight, loot, use NPCs, manage inventory and equipment, and stay
connected for at least one hour without a protocol error.

Target server: rAthena pinned at the commit in [DOCKER.md](DOCKER.md), with the
default `PACKETVER 20211103`. The same date is already hardcoded in the upstream
client at `Packages/RagnarokPackets/Sources/RagnarokPackets/PacketVersion.swift`.

## 2. Non-goals

- Official Ragnarok Online servers. Their anti-cheat blocks third-party clients.
- iOS or visionOS releases. Upstream supports them; this port only ships macOS
  arm64.
- Bundling Gravity assets. The user supplies kRO files.
- Full kRO parity across every episode, job, and cash shop system in v1.0.
- App Store distribution.
- Signing, notarization and DMG distribution for now: this is a local-only
  project (decided 2026-11-06). `scripts/release.sh` stays for later.
- A clean-Mac install test by a second person.
- A new renderer, new engine, or new UI framework.

## 3. Strategy

Fork `arkadeleon/ragnarok-offline`. It is the closest existing base:

- Swift 6, macOS 15+, native Metal (`import Metal`, `MTLDevice`).
- Separate Swift packages for GRF, file formats, resources, rendering, shaders,
  sprites, effects, packets, network sessions, game logic, and localization.
- `PACKET_VERSION = 20211103`, matching the pinned rAthena server.
- `RagnarokNetwork` already has `LoginSession`, `CharSession`, `MapSession`,
  `PacketFactory`, and packet handlers for NPC, item, player, chat, and mail.
- Active development. Pushed on 2026-11-05.
- GPL-3.0.

Keep upstream mergeable:

- `upstream` remote points at `arkadeleon/ragnarok-offline`.
- `main` tracks `upstream/master`; upstream has no release branch. Cut fork
  releases from `main` and use upstream version tags only as references.
- Work happens in short branches: `feat/...`, `fix/...`, `chore/...`.
- Rebase or merge upstream monthly.
- Local patches stay small and behind flags where possible.

Use `roBrowserLegacy` as a behavioral reference for protocol and rendering, and
`rAthena` as the source of truth for packets. Use `Korangar` as a second
reference for formats and macOS behavior.

The development server is the official rAthena Docker stack, pinned to one
commit. Setup, ports, database initialization, obfuscation changes, and test
accounts are in [DOCKER.md](DOCKER.md).

## 4. Phases

### Phase 0: Validation (1-2 weeks)

Prove the upstream app can connect to a real rAthena server on this Mac.

- Install the Xcode Metal Toolchain:
  `xcodebuild -downloadComponent MetalToolchain`.
- Clone upstream with submodules:
  `git clone --recurse-submodules https://github.com/arkadeleon/ragnarok-offline.git`.
- Build upstream on macOS 27 arm64 with current Xcode.
- Extract `~/Downloads/kRO_FullClient_20210406.zip` and copy `data.grf` and
  `BGM` into the app's Local Client Files directory. Launch the app and start
  the embedded local server as a baseline check.
- Confirm the game client screen exposes `serverAddress` and `serverPort` and
  passes them to `GameSession.Configuration`.
- Clone rAthena and pin commit `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`.
- Configure the official Docker stack from `tools/docker` and build with
  `--enable-packetver=20211103`.
- Disable `PACKET_OBFUSCATION` in `src/custom/defines_post.hpp` for development.
- Start MariaDB, login, char, and map. Verify ports 6900, 6121, and 5121.
- Insert a test account and create a character.
- Point the client at `127.0.0.1:6900`. Verify login, char list, map entry.
- Record every unknown packet, disconnect, and missing UI path.
- Count implemented packets against the rAthena packet table for 20211103.

Exit criteria: a character spawns on an rAthena map and can walk and chat for
10 minutes without a disconnect.

### Phase 1: Fork hygiene and CI (1 week)

- Fork the repository, rename the app, set a new bundle identifier.
- Keep GPL-3.0 notices and upstream attribution in About and source headers.
- Add `upstream` remote and document the sync procedure.
- Add GitHub Actions on `macos-15`: checkout with submodules, build, unit
  tests, arm64 only.
- Add a local asset provisioning script that copies `data.grf` and `BGM` from a
  user-supplied kRO directory into the app's sandbox Documents directory. No
  assets in git.
- Add a smoke script that launches the app headlessly if upstream supports it.

Exit criteria: a clean clone builds in CI and launches locally.

### Phase 2: Protocol correctness (3-5 weeks)

- Decide obfuscation policy. Stock rAthena enables `PACKET_OBFUSCATION`, and
  upstream does not implement it. For development, add
  `#undef PACKET_OBFUSCATION` and `#undef PACKET_OBFUSCATION_WARN` to
  `src/custom/defines_post.hpp` and rebuild. That header is included after
  `src/config/packets.hpp`, so it overrides the default without editing the
  main packet configuration. `defines_post.hpp` is tracked upstream but is the
  designated override file. For v1.0, implement obfuscation or document the
  server requirement.
- Make `PACKET_VERSION` a runtime setting with 20211103 as the default. The
  current global `let` and single generated `packetdb.swift` need a per-version
  table and Swift 6 global-state handling.
- Extend the existing unknown-packet logger in `PacketDecoder` with length and
  hex payload. It currently logs the opcode and remaining bytes, then throws.
- Add packet golden tests generated from rAthena headers.
- Implement and verify the pincode flow. Upstream only receives
  `PACKET_HC_SECOND_PASSWD_LOGIN` and does not reply.
- Verify login, char, and map handoff, character creation, and reconnect.
- Verify packet size limits and fragmented TCP reads.
- Add a replay harness that feeds recorded packets into the sessions.

Exit criteria: 60 minute session on rAthena with only obfuscation disabled, no
unknown packet that blocks gameplay.

### Phase 3: Playable core (6-10 weeks)

- Movement, pathfinding, map transitions, and teleports.
- Chat channels, whispers, party and guild chat.
- Basic combat, damage, death, respawn, and experience.
- Loot, item drops, inventory, equipment, and weight.
- NPC dialog, shops, storage, and Kafra services.
- Skill window, skill use, cooldowns, and ground targeting.
- Save and load settings, keybinds, and window layout.

Exit criteria: one hour of normal play on the test server without a blocking bug.

### Phase 4: Content coverage (6-10 weeks)

Prioritize the content actually enabled on the target server. Do not chase full
kRO parity.

- Skills and effects for the jobs in use.
- Item DB and localization from the server's YAML and SQL tables and the kRO
  client's `System/*.lub` files.
- Party, guild, mail, and friends.
- Pets, mounts, and costumes if enabled.
- Quest log and NPC script dialogs used by the server.
- Cash shop and achievement UI only if enabled.

Exit criteria: the target server's daily content is usable. Known gaps are
listed in the release notes.

### Phase 5: Performance and release (3-5 weeks)

- Profile Metal frames with Xcode GPU capture.
- Target 120 fps on ProMotion, frame time under 8.3 ms on M1.
- Memory target under 4 GB RSS with a full kRO data set.
- Cold start under 10 seconds after the first cache warm.
- Retina scaling, fullscreen, window restore, and input remapping.
- Signing, notarization and the DMG are deferred (local-only project).
- Publish the GPL source for the exact binary.
- Write install docs: kRO files, server address, packet version, obfuscation.

Exit criteria: the local build meets the performance targets on the developer Mac.

## 5. Milestones

| Milestone | Scope | Solo full-time | Status 2026-11-09 |
| --- | --- | --- | --- |
| M0 | Build upstream, Docker rAthena login | 1-2 weeks | Done |
| M1 | Login to rAthena, walk, chat | 5-8 weeks | Done |
| M2 | Playable core | 11-18 weeks | Every task verified headless against the live server; the one-hour playtest by a person (P3-15) is the only open item |
| M3 | Target-server content | 17-28 weeks | Most enabled systems usable; open: skill effects (P4-02) and the systems in KNOWN_GAPS.md |
| M4 | v1.0 (local build) | 20-33 weeks | fps, memory and cold start measured and inside the targets on the developer Mac; GPU capture and display handling open |

Solo at 20 hours per week: double the ranges. Two developers full-time: roughly
60 percent of the ranges.

These numbers assume the upstream base keeps working and no protocol rewrite is
needed. From scratch the same scope is 18-36 person-months for a playable client
and 36-60 for broad kRO parity.

## 6. Definition of done

v0.1:

- Builds from a clean clone with submodules on macOS 15+ arm64.
- Logs in to a test rAthena server.
- Enters a map, walks, and chats.

v0.5:

- Core loop in Phase 3 works.
- No known crash in a one hour session.
- Settings persist.

v1.0:

- Phase 4 content complete for the target server.
- GPL source published for the binary.
- One hour playtest by the developer with a written bug list.

## 7. Success metrics

- Login success above 99 percent on the test server.
- 60 minute session with zero disconnects caused by the client.
- 120 fps average on M1 at 1440p with effects enabled.
- Under 4 GB RSS with `data.grf` loaded.
- Cold start under 10 seconds after cache warm.
- Zero Gravity assets in the repository or the DMG.

## 8. Licensing and distribution

- Upstream is GPL-3.0. The fork must stay GPL-3.0 and publish source.
- Gravity assets are not distributable. Require the user to own a kRO client.
- GPL-3.0 and App Store DRM are incompatible. Distribute outside the App Store.
- Keep the rAthena GPL notice for any copied packet definitions or constants.
- Do not copy code from `roBrowserLegacy` (GPL-3.0) or `Korangar` (MIT) without
  recording the source and license in `NOTICE`.

## 9. Maintenance

- Monthly upstream sync. Resolve conflicts in `RagnarokNetwork` and `RagnarokGame`
  first because they change most.
- Re-run the packet golden tests after every rAthena update.
- Track rAthena's default `PACKETVER`. Add support only when the target server
  changes; do not chase every date.
- Keep a one-page compatibility table: client build, rAthena commit, PACKETVER,
  obfuscation on or off, known gaps.

## 10. Progress

Status on 2026-11-09. Work is on the local branch `integrate-m2`. It is more
than 50 commits ahead of `main` and `feat/port-phase0-5` (PR #1, merged on
`github.com/fabianwgl/ro-mac-arm`) and has not been pushed.
Per-task status with evidence is in [TASKS.md](TASKS.md); open content in
[KNOWN_GAPS.md](KNOWN_GAPS.md).

### Done

- Phase 0: upstream builds on macOS 27 / Xcode 27 after installing the Metal
  toolchain. The rAthena Docker stack runs as `ro-backend` at the pinned commit.
  A headless probe (`Tools/ROProbe`) drives the real `GameSession`. A 10-minute
  login, create, walk, chat and attack run passed with 0 disconnects.
  Packet coverage is in [packet-coverage.md](packet-coverage.md). The go
  decision is in RESEARCH.md.
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
  - Pincode, verified against the live server.
  - Character delete, and reconnect after a server restart.
  - A 60-minute soak with 0 errors.
  - Obfuscation needs no work: rAthena's keys are zero at 20211103, verified on
    a stock server.
  - Client bugs fixed:
    - `CZ_ENTER` shared a TCP write with the next packet.
    - Eight server packets had no length.
    - `RANKLIST` had the wrong size.
    - The friend reply packet had the wrong size.
    - The account id read dropped bytes on a short TCP read.
    - Login required 6-character credentials.
- Phase 3:
  - Chat: whisper, party and guild.
  - The quit acknowledgement and the hand-off between map servers.
  - Clicking warps and NPCs. NPC dialogs close on a map change.
  - macOS keyboard controls with rebinding, WASD walking, game controller.
  - Sound and display preferences.
  - The saved password lives in the Keychain.
  - A crash marker and log export.
  - Map changes, experience, loot, inventory, NPC shops and storage, Kafra,
    skills, ground skills and audio verified by the probe's core scenario:
    66 of 66 checks ([core-verification.md](probe-runs/core-verification.md)).
- Phase 4:
  - An inventory of the server's content ([server-content.md](server-content.md)).
  - Party, friends, quest log, pets, homunculus, RODEX mail, achievements and
    attendance.
  - Guild window with skills and emblem.
  - Trade, vending, buying stores, chat rooms, item appraisal and cart moves,
    each verified live with one or two probes (`probe-runs/`).
  - English names for every server item, skill and monster
    ([localization.md](localization.md)).
  - Skill effects: an audit of the 224 active skills of the 1st and 2nd jobs,
    83 with a skill specific effect, ground units for three skills
    ([skill-effects.md](skill-effects.md)).
- Phase 5:
  - Install and release docs. `scripts/release.sh` builds a signed DMG
    without notarization. Signing and distribution are deferred because the
    project is local-only.
  - `scripts/perf-run.sh` measures fps, memory and cold start unattended. On
    the developer Mac (M4, 144 Hz, 2560x1440): 143.9 fps, peak RSS under
    600 MB, 1.1 to 2.8 s to the first map frame ([perf.md](perf.md)). The map
    view now draws at the display's refresh rate instead of 60 fps.

### Open problems

- No person has played the client yet. Every check so far is headless: the
  probe calls the same `PlaySession` and `MapScene` entry points as the UI,
  but it draws nothing, so a SwiftUI window or a Metal frame that looks wrong
  is not caught. P3-15 is the gate for M2 and for most of the work below.
- CI is red. `swift test` for RagnarokGame does not compile on the runner's
  Xcode 26.6: the `#bundle` macro in the UI sources needs a resource bundle
  the package does not have. It compiles with Xcode 27 on the developer Mac.
  CI has not run since 2026-11-06 because nothing was pushed.
- The work since PR #1 exists only on this Mac.
- [server-content.md](server-content.md) lists every job and system of a
  stock rAthena as enabled, so "the content the target server enables" does
  not narrow the scope. Which jobs and systems are played decides the order
  of the rest of Phase 4.
- The week ranges in section 5 no longer describe the pace: Phases 0 to 4
  took days. They are kept as the original estimate.

### Next

1. The developer's one-hour playtest (P3-15) with a written bug list. Fix
   what turns up, then run the soak again.
2. Push `integrate-m2` and make the RagnarokGame test job compile on CI
   (P1-07).
3. Skill effects (P4-02), in the order of [skill-effects.md](skill-effects.md):
   status pictures for other players, ground units (Warp Portal and Safety
   Wall first), the ground cast circle.
4. The remaining systems in [KNOWN_GAPS.md](KNOWN_GAPS.md). First: refine and
   enchant, the cart window, guild position editing and alliances.
5. Phase 5: GPU capture (P5-01 to P5-03) and display handling (P5-07).

### Server notes found during the work

- Attendance: no period is active in `db/re/attendance.yml`. Add one to
  `db/import/attendance.yml` to use the feature.
- The `openmail` NPC fails at this packet date after it takes 130 zeny.
  Use the menu or `@mail`.
