# ROProbe

`ro-probe` is a headless client for the Phase 0 and Phase 2 checks against a live rAthena server. It drives the
real `GameSession` and `PlaySession` of `Packages/RagnarokGame` with no window: login, char server, character
create or select, map server, then walk, chat and attack through the same `MapScene` and `PlaySession` entry
points the UI uses. It counts every packet by opcode and writes a summary to stdout and, with `--json`, to a file.

It is a standalone SwiftPM package. It depends on the repo packages by relative path and does not change them.

## How it works

- `GameSession` is `@MainActor` and its login, character and map calls are internal, so the probe uses
  `@testable import RagnarokGame` and `@testable import RagnarokPackets`. This needs a debug build, which is what
  `swift build` makes. Do not build it with `-c release`.
- The resource manager reads a kRO client directory like the app does: loose files, then `rdata.grf`, then
  `data.grf`. BGM and sound effects answer "not found", so the run is silent.
- `GameSession` owns its `NetworkClient`s and their packet streams are private. To tally packets without editing
  the client, the probe starts a loopback TCP relay (the "tap") and gives `GameSession` its ports. The relay
  forwards bytes unchanged. It rewrites only the char server address in `AC_ACCEPT_LOGIN` and the map server
  address in `HC_NOTIFY_ZONESVR` so the next connection goes through the relay too. Framing mirrors
  `PacketDecoder.decode`: registered struct size, else packet database length, else unknown.
- Every received packet is classified as decoded, unimplemented (known length, no struct), unknown (no length,
  the real decoder throws and drops its buffer) or decode failure (struct init threw). A registered fixed size
  that disagrees with the length field on the wire is counted as a size mismatch.
- `--no-tap` skips the relay and connects `GameSession` straight to the server. There are no per-opcode counts
  then.
- The map loop calls `MapSceneRuntime.update(at:renderTime:)` every 100 ms, which is what the app's render loop
  calls each frame without drawing. Without it the player never advances and arrival actions never fire.

## Build

```sh
swift build --package-path Tools/ROProbe
```

The first build compiles all the repo packages (about 4 minutes). Later builds take seconds. The binary is
`Tools/ROProbe/.build/debug/ro-probe`. Run it from the repo root so the packet name table can find
`Packages/RagnarokPackets/.../Generated/packets.swift`; without that file names fall back to struct names.

## Usage

```sh
Tools/ROProbe/.build/debug/ro-probe \
  --host 127.0.0.1 --port 6900 --user test --pass test \
  --char-name ProbeOne --duration 600 \
  --chat-interval 30 --walk-interval 3 \
  --json docs/port/probe-runs/run-10min.json
```

| Flag | Meaning | Default |
| --- | --- | --- |
| `--host`, `--port` | Login server | `127.0.0.1`, `6900` |
| `--user`, `--pass` | Account | `test`, `test` |
| `--char-name` | Character to select, created as a novice if missing | `ProbeOne` |
| `--duration` | Seconds on the map, counted from the first map entry | `60` |
| `--chat-interval` | Public chat period in seconds, first line after 5 s | `30` |
| `--walk-interval` | Walk request period | `3` |
| `--attack-interval` | Attack request period, used only when a monster is in view | `5` |
| `--json` | Write the summary as JSON | none |
| `--client-dir` | kRO client directory with `data.grf` | `/Users/fwgl/Games/kRO_20210406/client` |
| `--delete-test` | Create a throwaway character, delete it, confirm it is gone after a fresh login | off |
| `--reconnect` | On disconnect or failure, back off 1, 2, 4 .. 15 s and redo login to map | off |
| `--route map:x,y;..` | On a listed map walk to that cell (for example a warp) instead of wandering | none |
| `--no-tap` | No relay, no per-opcode tally | off |
| `--no-enter-workaround` | Do not split the map `CZ_ENTER` from the packet after it (shows the client bug) | off |
| `--stage-timeout`, `--map-load-timeout` | Waits in seconds | `120`, `300` |
| `--with-audio` | Let the client play BGM and sound effects | off |
| `--coverage` | Print packet table coverage (P0-10) and exit; `--json` writes it too | |

Exit code is 0 when the map was reached (or, with `--delete-test`, when the test passed), 1 otherwise, 2 for bad
arguments. `SIGINT` and `SIGTERM` stop the run and still print and write the summary; a second signal exits at once.
Steps are logged with timestamps to stderr. The summary goes to stdout.

### Delete test

```sh
Tools/ROProbe/.build/debug/ro-probe --user test2 --pass test2 --delete-test --json docs/port/probe-runs/delete-test.json
```

It sends `CH_MAKE_CHAR`, then `CH_DELETE_CHAR3_RESERVED`, then `CH_DELETE_CHAR3` with an empty birthdate (what
`GameSession.deleteCharacter` does), checks that the client list dropped the character, then logs in again and
checks the server list.

### Reconnect test

```sh
Tools/ROProbe/.build/debug/ro-probe --user test --pass test --char-name ProbeOne --duration 240 --reconnect \
  --json docs/port/probe-runs/reconnect.json
# after about 60 s, in another shell:
cd ~/dev/rathena/tools/docker && docker compose restart map char login
```

The summary counts the disconnect, each failed attempt while the servers are down, and the reconnect that reaches
the map again. `GameSession` has no reconnect of its own, so the probe builds a fresh `GameSession` per attempt.

### Packet coverage (P0-10)

```sh
Tools/ROProbe/.build/debug/ro-probe --coverage --json docs/port/probe-runs/coverage.json
```

## Output

The JSON has these keys: `durationSeconds`, `timeOnMapSeconds`, `lastStage`, `stageHistory`, `reachedMap`,
`mapsVisited`, `disconnects`, `reconnects`, `errors`, `chatLinesSent`, `walkRequestsSent`, `attacksSent`,
`monstersSeen`, `deaths`, `packetTotals`, `packetsReceivedByOpcode`, `unknownPackets`, `unimplementedPackets`,
`decodeFailures`, `registeredSizeVsWireLengthMismatches`, `packetsSentByOpcode`, `connectPacketCoalesced`,
`sessions`, `notes`, `deleteTest`.

`walkRequestsSent` and `attacksSent` count calls the probe made. `packetsSentByOpcode` counts what went on the
wire (`0x035f` is `CZ_REQUEST_MOVE`, `0x0089`/`0x0437` `CZ_REQUEST_ACT` depending on the packet version).

## Known limits

- Attacks happen only if a monster is in view. A new character starts in `iz_int`, a safe room. Walking onto the
  `#ship_out` warp at (56, 15) leads to `int_land`, which has Porings. `--route iz_int:56,15` goes there.
- No pincode flow. The server must have `pincode_enabled: no`.
- Login, char and map must advertise a host the probe can reach (the Docker setup advertises `127.0.0.1`).
- Debug builds only, because of `@testable`.
