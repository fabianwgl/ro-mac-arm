# ROProbe

`ro-probe` is a headless client for the Phase 0, Phase 2 and Phase 3 checks against a live rAthena server. It drives the
real `GameSession` and `PlaySession` of `Packages/RagnarokGame` with no window: login, char server, character
create or select, map server, then walk, chat and attack through the same `MapScene` and `PlaySession` entry
points the UI uses. It counts every packet by opcode and writes a summary to stdout and, with `--json`, to a file.

It is a standalone SwiftPM package. It depends on the repo packages by relative path and does not change them.

## How it works

- `GameSession` is `@MainActor` and its login, character and map calls are internal, so the probe uses
  `@testable import RagnarokGame` and `@testable import RagnarokPackets`. This needs a debug build, which is what
  `swift build` makes. Do not build it with `-c release`.
- The resource manager reads a kRO client directory like the app does: loose files, then `rdata.grf`, then
  `data.grf`. BGM and sound effects answer "not found" unless `--with-audio` is given, so the run is silent.
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
| `--with-audio` | Let the client load (and, with `--audible`, play) BGM and sound effects; every audio request and whether it resolved goes into `audioRequests` in the JSON | off |
| `--audible` | With `--with-audio`, leave the BGM and sound effect preferences on. Without it the run turns them off so it stays silent while still loading and decoding the files | off |
| `--trace-packets` | With `--scenario`, print every packet to stderr as it passes | off |
| `--scenario core` | Run the scripted core gameplay checks (see below) instead of wandering | off |
| `--tasks P3-05,P3-06` | With `--scenario`, run only these tasks (`05,06` also works) | all |
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

### Core scenario (P3-02, P3-05..P3-11, P3-13)

```sh
# once: an admin account (group_id 99, needed for the @ commands the setup uses)
docker exec ro-backend-db mariadb -uragnarok -pragnarok ragnarok -e \
  "INSERT INTO login (userid, user_pass, sex, email, group_id, pincode) VALUES ('probecore','probecore','M','probecore@example.com',99,'');"

Tools/ROProbe/.build/debug/ro-probe --user probecore --pass probecore --char-name ProbeCore \
  --scenario core --with-audio --json docs/port/probe-runs/core-2026-11-08.json
```

The scenario logs in, creates the character if it is missing, waits for the map and then runs the tasks below in
this order: P3-07, P3-05, P3-06, P3-10, P3-11, P3-08, P3-09, P3-02, P3-13. Run it on a fresh character: it changes
job (Novice, Swordman, Mage), spends skill points and moves the save point. A run takes about 100 s. Wait 15 s or so
between two runs on one account, or the login server answers "Server still recognizes your last log-in". The exit code is 0 when every task that
ran passed (a task skipped for a missing flag does not count).

Each check goes through the entry point the UI uses and then waits for the server's answer packet and for the client
state that packet changes: `PlaySession.useItem`, `equipItem`, `unequipItem`, `throwItem`, `incrementStatusProperty`,
`upgradeSkillLevel`, `useShortcut` (which is what the skill list calls), `selectDealType`, `purchaseItems`,
`sellItems`, `selectMenu`, `moveItemToStorage`, and `MapScene.handleInteraction` / `attackMonster` for taps on
monsters, NPCs, floor items and the ground. Chat GM commands (`@item`, `@blvl`, `@skillpoint`, `@jobchange`,
`@monster`, `@zeny`, `@storage`, `@heal`, `@warp`) only set a situation up, or are the thing under test (`@warp`).
While it waits the scenario calls `MapSceneRuntime.update` every 100 ms like the render loop, and asks for the save
point respawn if the character dies.

| Task | What it does |
| --- | --- |
| P3-07 | `@item` adds potions, a spare Knife and a Cotton Shirt; weight rises and falls by the item weight; use a potion; equip the spare knife; take the worn shirt off and put it on again |
| P3-05 | Kills Porings one at a time with `attackMonster`; experience, a level up from kill experience (falls back to `@blvl 1`), then one STR point |
| P3-06 | Taps a monster drop and a thrown potion stack on the ground and picks them up |
| P3-10 | `@skillpoint`, Basic Skill to 9 (the server wants it before any first-job skill, `player_skillup_limit`), `@jobchange 1`, Bash 5 and Magnum Break 1 through `upgradeSkillLevel`, Bash on a Poring, Magnum Break cooldown from `ZC_SKILL_POSTDELAY` |
| P3-11 | `@jobchange 2`, Cold Bolt, Lightning Bolt 4 and Thunderstorm 1, then Thunderstorm on a selected monster (walks into range, sends `CZ_USE_SKILL_TOGROUND` at the monster's cell) and with nothing selected (own cell); the cell is read from the sent frame |
| P3-08 | `@warp` to `prt_in`, taps the Tool Dealer, buy list, buys 5 Red Potions and 3 Fly Wings, checks the zeny against the list price, sell list, sells 2 potions, `@storage`, puts 3 potions in and takes them out |
| P3-09 | Prontera Kafra (151,29): dialog text, next, menu, cancel, then Save, Use Storage (put and take), Use Teleport Service to Geffen |
| P3-02 | Fly Wing (same map, new cell, walking works afterwards), Butterfly Wing (to the Kafra save point in Prontera, another map), `@warp` to a field map |
| P3-13 | Needs `--with-audio`. Reads the audio requests the whole run made, decodes the BGM of every visited map through `mp3nametable.txt` with `AVAudioPlayer` and the requested sound effects with the client's own `AVAudioPCMBuffer.buffer`. Playback is for a human (`--audible`) |

The summary gets a `scenario` object: per task `result` (`pass`, `fail`, `skipped`), `checks` (name, passed, detail),
`notes`, `packetsReceived` and `packetsSent` (counts by name for that task only) and `serverMessages` (what the
client's message log received, such as GM command answers). The run's own packet log is kept only while a scenario
runs.

### Chat room test

```sh
Tools/ROProbe/.build/debug/ro-probe --chatroom-test --json docs/port/probe-runs/chatroom-<date>.json
```

Two clients in one process (accounts `room1` in group 99 and `room2` in group 0, characters `RoomOne` and `RoomTwo`, both
created when missing) use chat rooms through the same `PlaySession` and `MapScene` calls the UI makes. Round 1 is a
public room (create, join by clicking the owner, a line each way, rename, leave, lines that only members get, close),
round 2 a private one (wrong and right password, expel, refused after the expel) and round 3 gives the room away. `room2`
must be a plain player: the administrator group has `join_chat` and `kick_chat`, which skip passwords and make a player
immune to expel. `room1` needs group 99 for `@warp`, `@skpoint` and `@recall`. Account setup is in `docs/port/DOCKER.md`.

### Appraisal test

```sh
Tools/ROProbe/.build/debug/ro-probe --appraisal-test --user ident1 --pass ident1 --char-name Ident \
  --json docs/port/probe-runs/appraisal-2026-11-08.json
```

One GM probe (group 99 account). It gets an unidentified Knife (`@item2 1201 1 0 0 0 0 0 0 0`) and Magnifiers
(`@item 611`), uses a Magnifier through `PlaySession.useItem`, checks the `ZC_ITEMIDENTIFY_LIST` picker, cancels once
(the second Magnifier use only works when the server left the menu), then picks the Knife and checks that the inventory
flag flips on `ZC_ACK_ITEMIDENTIFY`. It repeats the pick with the Item Appraisal skill (`@jobchange 5`, `@allskill`),
then puts a cart on and off with `@cart` to check `canMoveToCart` and moves potions into the cart and back. A Magnifier
is used up by a cancel as well, so a run needs five. Right after a run the server may answer "still recognizes your
last log-in"; wait about a minute before the next run.

### Packet coverage (P0-10)

```sh
Tools/ROProbe/.build/debug/ro-probe --coverage --json docs/port/probe-runs/coverage.json
```

## Output

The JSON has these keys: `durationSeconds`, `timeOnMapSeconds`, `lastStage`, `stageHistory`, `reachedMap`,
`mapsVisited`, `disconnects`, `reconnects`, `errors`, `chatLinesSent`, `walkRequestsSent`, `attacksSent`,
`monstersSeen`, `deaths`, `packetTotals`, `packetsReceivedByOpcode`, `unknownPackets`, `unimplementedPackets`,
`decodeFailures`, `registeredSizeVsWireLengthMismatches`, `packetsSentByOpcode`, `connectPacketCoalesced`,
`sessions`, `notes`, `deleteTest`, `scenario` (with `--scenario`), `audioRequests` (with `--with-audio`).

`walkRequestsSent` and `attacksSent` count calls the probe made. `packetsSentByOpcode` counts what went on the
wire (`0x035f` is `CZ_REQUEST_MOVE`, `0x0089`/`0x0437` `CZ_REQUEST_ACT` depending on the packet version).

## Known limits

- Attacks happen only if a monster is in view. A new character starts in `iz_int`, a safe room. Walking onto the
  `#ship_out` warp at (56, 15) leads to `int_land`, which has Porings. `--route iz_int:56,15` goes there.
- No pincode flow. The server must have `pincode_enabled: no`.
- Login, char and map must advertise a host the probe can reach (the Docker setup advertises `127.0.0.1`).
- Debug builds only, because of `@testable`.
