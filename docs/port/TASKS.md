# Tasks

Checklist for the port. IDs are stable; add new work at the end of the matching
phase. Mark a task done only when its acceptance check passes.

## Phase 0: Validation

- [ ] P0-01 Install the Xcode Metal Toolchain, clone upstream with submodules,
  and build on macOS 27 arm64 with current Xcode.
- [ ] P0-02 Extract `~/Downloads/kRO_FullClient_20210406.zip` and copy `data.grf`
  and `BGM` into the app's Local Client Files directory.
- [ ] P0-03 Start the embedded local server and log in as a baseline.
- [ ] P0-04 Confirm `GameClientView` exposes `serverAddress` and `serverPort` and
  passes them to `GameSession.Configuration`.
- [ ] P0-05 Create a Docker test stack: rAthena master + MariaDB. See
  [DOCKER.md](DOCKER.md).
  - [ ] P0-05a Clone rAthena and pin commit
    `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`.
  - [ ] P0-05b Keep `BUILDER_CONFIGURE: "--enable-packetver=20211103"`.
  - [ ] P0-05c Set `pincode_enabled: no`, `char_name_option: 0`, and
    `char_del_delay: 0` in `tools/docker/asset/char_conf.txt`.
  - [ ] P0-05d Add `#undef PACKET_OBFUSCATION` and
    `#undef PACKET_OBFUSCATION_WARN` to `src/custom/defines_post.hpp`, then
    rebuild.
  - [ ] P0-05e Start `db`, run `builder` to completion, then start `login`,
    `char`, and `map`.
  - [ ] P0-05f Verify ports 6900, 6121, and 5121 answer on `127.0.0.1`, and all
    three services stay running.
  - [ ] P0-05g Insert the `test` account into the `login` table.
  - [ ] P0-05h Record the rAthena commit and server config in the compatibility
    manifest.
- [ ] P0-06 Point the client at `127.0.0.1:6900` and log in as `test`.
- [ ] P0-07 Create a character and enter a map.
- [ ] P0-08 Walk, chat, and attack for 10 minutes.
- [ ] P0-09 Record unknown packets, disconnects, and missing UI.
- [ ] P0-10 Count implemented packets against the 20211103 table.
- [ ] P0-11 Write a go or no-go note in `RESEARCH.md`.

Acceptance: character spawns on the rAthena map and plays for 10 minutes.

## Phase 1: Fork hygiene

- [ ] P1-01 Fork the repository and rename the app.
- [ ] P1-02 Set a new bundle identifier and development team.
- [ ] P1-03 Keep GPL-3.0 and upstream attribution in About and headers.
- [ ] P1-04 Add `upstream` remote and document the sync procedure.
- [ ] P1-05 Add a minimal `NOTICE` file for upstream and third-party code.
- [ ] P1-06 Add GitHub Actions build on `macos-15`, arm64, with submodules.
- [ ] P1-07 Add unit test job and cache Swift packages.
- [ ] P1-08 Add an asset provisioning script that copies `data.grf` and `BGM`
  into the sandbox Documents directory and validates both.
- [ ] P1-09 Add `.gitignore` rules for client assets and build output.
- [ ] P1-10 Add issue templates for protocol, renderer, and UI bugs.
- [ ] P1-11 Add a compatibility manifest template.

Acceptance: clean clone builds in CI and launches locally.

## Phase 2: Protocol

- [ ] P2-01 Reproduce the obfuscation failure on stock rAthena.
- [ ] P2-02 Document and apply the `#undef PACKET_OBFUSCATION` change in
  `src/custom/defines_post.hpp` for the test server.
- [ ] P2-03 Add a runtime `PACKET_VERSION` override with 20211103 default.
- [ ] P2-04 Add a guard that rejects unsupported packet dates at startup.
- [ ] P2-05 Extend unknown-packet logging with length and hex. The existing
  logger in `PacketDecoder` records the opcode and remaining bytes, then throws.
- [ ] P2-06 Add a packet size sanity check and bounded read buffer.
- [ ] P2-07 Add fragmented and coalesced TCP read tests.
- [ ] P2-08 Generate golden packet fixtures from rAthena headers.
- [ ] P2-09 Add golden tests for login, char, and map sessions.
- [ ] P2-10 Implement and verify the pincode flow. Upstream only receives
  `PACKET_HC_SECOND_PASSWD_LOGIN` and does not reply.
- [ ] P2-11 Verify character creation and deletion.
- [ ] P2-12 Verify reconnect after a forced server restart.
- [ ] P2-13 Add packet replay harness.
- [ ] P2-14 Record a 60 minute session and count errors.

Acceptance: 60 minute session, no blocking unknown packet.

## Phase 3: Playable core

- [ ] P3-01 Movement and pathfinding on GAT walkability.
- [ ] P3-02 Map transitions, portals, and teleports.
- [ ] P3-03 Chat: public, party, guild, whisper.
- [ ] P3-04 Basic attack, damage, death, and respawn.
- [ ] P3-05 Experience, level up, and stat points.
- [ ] P3-06 Loot, drops, and item pickup.
- [ ] P3-07 Inventory, equipment, and weight.
- [ ] P3-08 NPC dialog, shops, and storage.
- [ ] P3-09 Kafra save, teleport, and storage.
- [ ] P3-10 Skill window, skill use, cooldowns.
- [ ] P3-11 Ground targeting and area skills.
- [ ] P3-12 Settings, keybinds, and window layout persistence.
- [ ] P3-13 Audio: BGM and sound effects.
- [ ] P3-14 Crash handling and local logs.
- [ ] P3-15 One hour playtest with a written bug list.

Acceptance: one hour of normal play with no blocking bug.

## Phase 4: Content

- [ ] P4-01 List the target server's enabled jobs, maps, and systems.
- [ ] P4-02 Implement skills and effects for enabled jobs.
- [ ] P4-03 Load item and skill DBs from the server's YAML and SQL tables and
  the kRO client's `System/*.lub` files.
- [ ] P4-04 Localization for item, skill, and monster names.
- [ ] P4-05 Party and guild windows.
- [ ] P4-06 Friends and mail.
- [ ] P4-07 Pets, mounts, and costumes if enabled.
- [ ] P4-08 Quest log and script dialogs used by the server.
- [ ] P4-09 Cash shop and achievements only if enabled.
- [ ] P4-10 Write a known-gaps list for release notes.

Acceptance: target server's daily content usable; gaps documented.

## Phase 5: Performance and release

- [ ] P5-01 Capture Metal frames on M1 for Prontera, Geffen, and an effect map.
- [ ] P5-02 Fix asset decode stalls and frame spikes.
- [ ] P5-03 Tune command buffers, state changes, and argument buffers.
- [ ] P5-04 Verify 120 fps target and record results.
- [ ] P5-05 Measure RSS with full kRO data; target under 4 GB.
- [ ] P5-06 Measure cold start; target under 10 seconds.
- [ ] P5-07 Retina, fullscreen, window restore, display change.
- [ ] P5-08 Input remapping and optional gamepad.
- [ ] P5-09 Developer ID signing and hardened runtime.
- [ ] P5-10 Notarize and staple the app.
- [ ] P5-11 Build DMG with compatibility manifest.
- [ ] P5-12 Publish GPL source archive for the exact binary.
- [ ] P5-13 Test install on a clean Mac without Xcode.
- [ ] P5-14 Write install guide: kRO files, server, PACKETVER, obfuscation.

Acceptance: signed and notarized DMG runs on a clean Mac.

## Phase 6: Maintenance

- [ ] P6-01 Monthly upstream sync.
- [ ] P6-02 Re-run packet golden tests after every rAthena update.
- [ ] P6-03 Track rAthena default `PACKETVER`.
- [ ] P6-04 Keep the compatibility table current.
- [ ] P6-05 Triage crash reports and protocol regressions.

## Backlog

- [ ] Implement `PACKET_OBFUSCATION` if the target server needs it.
- [ ] Add a packet editor or inspector window.
- [ ] Add a map viewer mode.
- [ ] Add a character simulator mode.
- [ ] Add a benchmarking scene.
- [ ] Add multi-client support for local testing.
