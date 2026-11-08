# RO Mac Client

A native macOS client for Ragnarok Online on Apple silicon, built for a private
[rAthena](https://github.com/rathena/rathena) server. Swift 6, SwiftUI and Metal,
arm64 only, macOS 15 or newer.

This is a fork of [Ragnarok Offline](https://github.com/arkadeleon/ragnarok-offline)
by Leon Li (GPL-3.0). Upstream is a toolkit with a built-in single-player server;
this fork turns it into a game client for an external rAthena server and keeps
upstream mergeable (`upstream` remote, monthly sync, local changes logged in
[docs/port/patches.md](docs/port/patches.md)).

No Gravity assets are included. You need your own kRO client files.

## Goal

Play a private rAthena server (pinned commit `d4b8e7b8`, `PACKETVER 20211103`)
from a native Mac app: log in, pick a character, enter maps, move, chat, fight,
loot, use NPCs, manage gear, and stay connected for hours without protocol
errors. Full kRO parity is not a goal. The target is the content this server
actually enables. This is a local-only project for now: no App Store, no signed
distribution.

The full plan is in [docs/port/PLAN.md](docs/port/PLAN.md).

## Status (2026-11-06)

| Milestone | State |
| --- | --- |
| M0 Build upstream, Docker rAthena login | Done |
| M1 Log in to rAthena, walk, chat | Done |
| M2 Playable core | In progress: core loop coded, per-item verification and a playtest left |
| M3 Target-server content | About half of the enabled systems usable |
| M4 v1.0 local build | Not started |

What works today:

- **Account:** login (including pincode), character create, select and delete,
  and reconnect after a server restart.
- **Movement:** walking, map changes, the hand-off between map servers, and
  warp portals.
- **Chat:** public, whisper (`/w`), party (`%`) and guild (`$`).
- **Core game from upstream:** combat, skills, inventory, equipment, NPC
  dialogs, shops, storage and Kafra.
- **Social:** party, friends, guild, quest log, RODEX mail, achievements and
  attendance.
- **Companions:** pet and homunculus windows.
- **macOS:** keyboard controls with rebinding, sound and display preferences,
  the saved password in the Keychain, crash detection and log export, and a
  launcher window. The upstream tools (GRF browser, databases, viewers) sit
  behind View > Developer Tools.

Proof:

- A 60-minute session against stock rAthena with 0 disconnects and 0 unknown
  packets ([probe report](docs/port/phase0-probe-report.md)).
- Golden packet tests compiled from the rAthena headers.
- [Packet coverage](docs/port/packet-coverage.md).

Open systems are listed in [docs/port/KNOWN_GAPS.md](docs/port/KNOWN_GAPS.md):
trade, vending, refine and enchant, clan, chat rooms, mercenaries, navigation
and others.

## Next

1. Finish M2:
   - Verify every Phase 3 item against the local server.
   - Do a GUI run of the real app with screenshots.
   - Fix what turns up.
   - Re-run the soak test.
   - Then a one-hour playtest.
2. Plan and build the remaining systems in KNOWN_GAPS.md, starting with
   trade, vending, buying store, refine and enchant.
3. Performance work: 120 fps, memory under 4 GB, cold start under 10 s.

## Run it

Requirements: an Apple silicon Mac, macOS 15+, Xcode 27, Docker Desktop, and
the 2021-04-06 kRO full client.

1. Start the server. Follow [docs/port/DOCKER.md](docs/port/DOCKER.md): rAthena
   at the pinned commit, compose project `ro-backend`, ports 6900, 6121 and 5121.
2. Get the code and the Metal toolchain:
   ```sh
   git clone --recurse-submodules https://github.com/fabianwgl/ro-mac-arm.git
   cd ro-mac-arm
   xcodebuild -downloadComponent MetalToolchain
   ```
3. Build a sandboxed debug app:
   ```sh
   xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline \
     -destination 'platform=macOS,arch=arm64' \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
   ```
   Or open `RagnarokOffline.xcodeproj` in Xcode and run the `RagnarokOffline`
   scheme.
4. Launch the app once, then copy the client files into its sandbox:
   ```sh
   scripts/provision-assets.sh ~/path/to/kRO/client
   ```
5. In the launcher, check that `data.grf` shows as supported, keep
   `127.0.0.1:6900`, and press Play.

The [install guide](docs/port/INSTALL.md) covers troubleshooting.

## Development

- Package tests: `swift test --package-path Packages/<Name>`.
  `RagnarokResources` and `RagnarokScript` need upstream's local asset server
  on port 8080.
- Headless client for protocol checks:
  `swift build --package-path Tools/ROProbe`, then
  `Tools/ROProbe/.build/debug/ro-probe --help`.
- Performance run without a person clicking (fps, RSS, cold start):
  `scripts/perf-run.sh --map prontera --char PerfPront`. Method and results in
  [docs/port/perf.md](docs/port/perf.md).
- Golden packet data: `Tools/packet-golden/generate.sh <rathena-dir>`.
  Coverage: `Tools/packet-golden/coverage.sh`.
- Task board with per-task status: [docs/port/TASKS.md](docs/port/TASKS.md).
  Architecture: [docs/port/ARCHITECTURE.md](docs/port/ARCHITECTURE.md).
  Risks: [docs/port/RISKS.md](docs/port/RISKS.md).

## License

GPL-3.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Based on Ragnarok Offline
by Leon Li and contributors. Packet definitions are derived from rAthena
(GPL-3.0). Ragnarok Online and its assets belong to Gravity Co., Ltd.; this
project is not affiliated with or endorsed by Gravity.
