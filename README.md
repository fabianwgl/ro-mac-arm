# RO Mac Client

A native macOS client for Ragnarok Online on Apple silicon, for playing alone
on your own Mac. Swift 6, SwiftUI and Metal, arm64 only, macOS 15 or newer.

This is a fork of [Ragnarok Offline](https://github.com/arkadeleon/ragnarok-offline)
by Leon Li (GPL-3.0). Upstream is a toolkit with a game client and a built-in
[rAthena](https://github.com/rathena/rathena) server. The fork stays thin: it
adds a Mac launcher, keyboard and controller input, preferences, tools that
verify the client against a real rAthena, and the fixes those tools found. It
merges upstream every week (`upstream` remote); changes to upstream's own files
are logged in [docs/port/patches.md](docs/port/patches.md).

No Gravity assets are included. You need your own kRO client files.

## Goal

One person plays on one Mac: start the app, press Play, and take a Novice
through the 1st and 2nd jobs. Walk, fight, loot, use skills and NPCs, manage
gear. No Docker and no database to set up: the server is the rAthena built
into the app.

Not goals: multiplayer, 3rd jobs and later, a release for other people,
official servers. This is a personal project.

The full plan is in [docs/port/PLAN.md](docs/port/PLAN.md).

## Status (2026-11-09)

| Milestone | State |
| --- | --- |
| M0 Build upstream, Docker rAthena login | Done |
| M1 Log in to rAthena, walk, chat | Done |
| M2 Playable core, proven by a person | Verified headless. Not yet played by a person, and not yet run against the built-in server |
| M3 Content for 1st and 2nd jobs | Skills cast and show numbers; 83 of 224 have their own effect |
| M4 v1.0 | Frame rate, memory and start-up measured and inside the targets |

What works today, against a stock rAthena in Docker:

- **Account:** login (including pincode), character create, select and delete,
  and reconnect after a server restart.
- **Movement:** walking, map changes, the hand-off between map servers, and
  warp portals.
- **Core game:** combat, experience, skills and ground skills, inventory,
  equipment, loot, NPC dialogs, shops, storage and Kafra.
- **Companions and quests:** pet and homunculus windows, quest log.
- **macOS:** keyboard controls with rebinding, WASD, game controller, sound
  and display preferences, the saved password in the Keychain, crash detection
  and log export, and a launcher window. The upstream tools (GRF browser,
  databases, viewers, the built-in server) sit behind View > Developer Tools.
- **Built before the project became solo, kept but frozen:** chat channels,
  party, friends, guild, trade, vending, buying stores, chat rooms, RODEX
  mail, achievements and attendance.

Proof:

- A 60-minute session against stock rAthena with 0 disconnects and 0 unknown
  packets ([probe report](docs/port/phase0-probe-report.md)).
- A scripted run of the core game loop, 66 of 66 checks
  ([core verification](docs/port/probe-runs/core-verification.md)).
- Golden packet tests compiled from the rAthena headers.
- [Packet coverage](docs/port/packet-coverage.md) and
  [performance measurements](docs/port/perf.md).

All of that proof is headless: a probe drives the real game session without a
window. What is missing is listed in
[docs/port/KNOWN_GAPS.md](docs/port/KNOWN_GAPS.md).

## Next

1. Run the built-in server in this fork and make Play start it.
2. A scripted run of the real app with a screenshot of every window, then a
   one-hour playtest by a person. No new features before that.
3. Merge upstream weekly, get CI green, offer the fixes upstream.
4. Then the gaps for 1st and 2nd jobs: job changes, visible statuses, the
   cart window, skill effects.

## Run it

These steps use the Docker server, which is what has been tested. Play
against the built-in server is the plan but is not wired into the launcher
yet.

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
