# Architecture

## 1. Shape

Fork of `arkadeleon/ragnarok-offline`. Keep the upstream package split. Add a
thin macOS application layer, verification tools and fixes. Do not rewrite
working packages, and do not build what upstream is building
([PLAN.md](PLAN.md) section 4).

```
RagnarokOffline.app (SwiftUI + AppKit shell)
  AppModel, settings, server manager
        |
        +-- RagnarokGame        game state, scene, input, UI model
        +-- RagnarokNetwork     login, char, map sessions, packets
        +-- RagnarokResources   asset lookup and caching
        +-- RagnarokRendering   Metal renderer
        +-- RagnarokShaders     Metal shaders
        +-- RagnarokGRF         GRF archive reader
        +-- RagnarokFileFormats GND, GAT, RSW, RSM, SPR, ACT, STR
        +-- RagnarokSprite      sprite composition
        +-- RagnarokEffects     effect playback
        +-- RagnarokModels      domain models
        +-- RagnarokConstants   protocol and game constants
        +-- RagnarokDatabase    item, job, skill data
        +-- RagnarokLocalization
        +-- RagnarokScript      NPC script support
        +-- RagnarokReality     world and scene helpers
        +-- RagnarokPackets     packet structs and PACKET_VERSION
        +-- RagnarokRenderAssets
        +-- BinaryIO, DataCompression, RagnarokCore
```

Upstream entry points to preserve:

- `RagnarokOffline/App/macOSApp.swift`
- `RagnarokOffline/App/AppModel.swift`
- `RagnarokOffline/Server/ServerManager.swift`

## 2. Data flow

Startup:

```
Settings -> client resource provider -> GRF index -> resource cache
        -> database tables -> game scene -> Metal renderer
```

Network:

```
TCP -> NetworkClient -> PacketFactory -> session decoder
    -> typed events -> game state -> scene and UI
```

Render:

```
Game state snapshot -> render asset lookup -> Metal command buffer
    -> shaders -> drawable
```

The renderer should consume immutable per-frame snapshots, as upstream already
does with `MapSceneRenderSnapshot`. Keep network and asset loading off the main
thread.

## 3. Protocol

- `PACKET_VERSION` is 20211103. Keep it as the default.
- Add a runtime override for testing other dates. Do not scatter date checks.
- Packet structs must match rAthena `src/map/packets_struct.hpp` and the packet
  tables for the selected date.
- Stock rAthena compiles `PACKET_OBFUSCATION` in, but its keys are zero at
  PACKETVER 20211103, so the client needs no support for it. Verified on a
  stock server.
- Add an unknown-packet path that logs opcode, length, and payload, and never
  crashes on a short or long packet.
- Handle fragmented and coalesced TCP reads explicitly. Do not assume one read
  equals one packet.

## 4. Renderer

- Metal 3, arm64 only, macOS 15+.
- One render thread, triple buffering, frame pacing for ProMotion.
- Terrain: GND mesh, GAT height and walkability, lightmaps, water.
- Models: RSM and RSM2, per-vertex animation.
- Sprites: SPR and ACT, palettes, paperdoll composition.
- Effects: STR playback with pooled buffers.
- Text: glyph atlas, Retina-aware, cached.
- Sorting: stable draw order for transparency and sprites.
- Culling: frustum and map-cell based. RO maps are small; do not over-engineer.
- Memory: memory-map GRF files, stream textures, cap caches by bytes not count.

Optimization order:

1. Fix frame spikes from asset decode.
2. Reduce command buffer count and state changes.
3. Tune shader constant layouts and argument buffers.
4. Profile on M1, not only on the newest machine.

The GPU is not the expected bottleneck. Asset decoding, UI layout, and packet
handling are more likely to limit frame time.

## 5. macOS shell

- SwiftUI for settings, server list, and launcher.
- AppKit or SwiftUI window for the game surface.
- Keyboard and mouse first, gamepad optional.
- Retina scale, fullscreen, window restore, and display change handling.
- Keychain for saved passwords if the app stores them.
- Crash reporter writes a local log; no telemetry by default.
- Bundle identifier, icon, About window with GPL notices and upstream credits.

## 6. Asset policy

- No `.grf`, `.gpf`, `BGM`, or extracted Gravity files in git.
- Upstream reads `data.grf` and optional loose files from the app's sandbox
  Documents directory (`URL.documentsDirectory`). The Local Client Files screen
  manages that directory. `rdata.grf` and `DATA.INI` are not read today.
- A provisioning script copies `data.grf` and `BGM` from a user-supplied kRO
  directory into that sandbox directory. A security-scoped directory picker is
  a later improvement.
- Cache extracted indexes under Application Support, not inside the app bundle.
- Never modify the source client files.

## 7. Testing

- Unit tests per file format with small fixture files.
- Golden packet tests generated from rAthena headers.
- Replay tests from recorded sessions.
- Integration test: Docker rAthena + MariaDB, client logs in and walks. Run it
  locally or on a self-hosted Mac runner; GitHub-hosted macOS runners cannot run
  Docker.
- GUI smoke run: a script launches the app with the debug auto login
  (`RO_AUTOLOGIN_*`), opens each core window and saves a screenshot of the
  game window (`screencapture -l`). Planned as `scripts/gui-smoke.sh`
  (TASKS.md P7-04). Screenshots are not committed.
- A person plays. No test replaces this (PLAN.md section 4, verification
  ladder).
- Performance test scene: Prontera, Geffen, and one effect-heavy map.

## 8. CI and release

- GitHub Actions `macos-26`, arm64. The runner's newest Xcode was 26.6 on
  2026-11-06, one major version behind the developer Mac (Xcode 27).
- Build the app, run the package tests and the packet golden tests.
- Cache Swift packages and DerivedData.
- No release job: nothing is distributed. `scripts/release.sh` builds a DMG
  locally if one is ever wanted.

## 9. Performance targets

| Metric | Target |
| --- | --- |
| Frame rate | 120 fps on M1 at 1440p |
| Frame time | under 8.3 ms |
| Cold start | under 10 s after cache warm |
| Memory | under 4 GB RSS with `data.grf` loaded |
| Login to map | under 15 s on LAN |
| Input latency | under 100 ms |

These were set for an M1 on a ProMotion panel. Measured on the developer Mac
(M4, 144 Hz, 2560x1440) with `scripts/perf-run.sh`: 143.9 fps, 6.95 ms, peak
RSS under 600 MB, 1.1 to 2.8 s from process start to the first map frame
([perf.md](perf.md)). Login to map and input latency were not measured on
their own.

## 10. Servers

Two rAthena servers, for two purposes.

**Embedded (`swift-rathena` submodule): the play server.** Upstream compiles
rAthena's login, char, map and web servers into the app and runs them in its
process, with SQLite save data under the app's Library folder and both a
Renewal and a Pre-Renewal build. `RagnarokOffline/Server/ServerManager.swift`
starts them; in the fork that screen is behind View > Developer Tools until
the launcher starts the servers itself (TASKS.md P7-02). Not yet run in the
fork (P7-01).

**Docker (`ro-backend`): the reference server.** Stock rAthena at a pinned
commit with MariaDB. The headless probe and the two-client scenarios run
against it. Development only.

```
Client (macOS, arm64)
  GameSession.Configuration(serverAddress: "127.0.0.1", serverPort: 6900)
        |
        v
Docker Desktop network
  login  :6900  -> char :6121 -> map :5121
       \             |            /
        +---------- db :3306 ----+
```

- The client talks only to the login server first. The login reply carries the
  char server address, and the char reply carries the map server address.
- The compose publishes 6900, 6121, and 5121 on the host. Source and database
  stay inside the Docker network.
- The char and map servers announce `127.0.0.1` by default. This works only for
  a client on the same Mac. A LAN client needs the announced addresses changed
  to the Mac LAN IP.
- The stack is pinned to one rAthena commit. The client must record that commit,
  the packet date, and the obfuscation state in its compatibility manifest.
- The two servers are different rAthena snapshots with different configs
  (the embedded one gives every account a set of GM commands, allows registration and
  has no pincode). [COMPATIBILITY.md](COMPATIBILITY.md) records both.

Full setup and reset commands are in [DOCKER.md](DOCKER.md).
