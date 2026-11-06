# Phase 0 and Phase 2 probe report

Date: 2026-11-05 and 2026-11-06. Client: `main` plus the uncommitted fork work in
this tree. Server: rAthena `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`, PACKETVER
20211103, Docker stack `ro-backend` ([DOCKER.md](DOCKER.md)). kRO data:
2021-04-06 full client.

All runs use `Tools/ROProbe` ([README](../../Tools/ROProbe/README.md)), which
drives the real `GameSession` and `PlaySession` headlessly through the same
entry points the UI uses, and tallies every packet through a loopback relay.
Raw summaries are in [probe-runs/](probe-runs/).

## Results

| Check | Plan task | Run | Result |
| --- | --- | --- | --- |
| Login, create character, select, enter map | P0-06, P0-07 | `run-10min.json` | Pass: `ProbeOne` created, map loaded in 1 s |
| Walk, chat, attack for 10 minutes | P0-08, Phase 0 exit | `run-10min.json` | Pass: 601 s on map, 197 walk requests (77 distinct cells), 20 chat lines, 71 attacks, 0 disconnects, 0 errors |
| Unknown packets | P0-09 | all runs | 0 unknown, 0 decode failures, 0 registered size mismatches |
| Character creation and deletion | P2-11 | `delete-test.json` | Pass: created, reserved, deleted, gone after re-login |
| Reconnect after server restart | P2-12 | `reconnect.json` | Pass: `docker compose restart` at 60 s, GM-disconnect notice, 4 retries while the map server loaded, back on the map |
| Stock rAthena, obfuscation compiled in | P2-01 | `stock-obfuscation.json` | Pass: map server logs `Packet Obfuscation: Enabled. Keys: 0x00000000 ...`; 120 s on map, 0 errors |
| 60-minute session | P2-14, Phase 2 exit | `soak-60min.json` | Pass: 3600 s on map against stock rAthena, 884 walks, 120 chat lines, 450 attacks, 3233 packets decoded, 0 unknown, 0 disconnects, 0 errors |
| Pincode create and enter | P2-10 | `pincode-1.json`, `pincode-2.json` | Pass with `pincode_enabled: yes`: run 1 created pin 1357 (rAthena stored `1357`, so the cipher matches), run 2 entered it; map reached both times |
| Packet coverage | P0-10 | [packet-coverage.md](packet-coverage.md) | 518 server packets rAthena can send; client frames 517, decodes 382 |

## Client bugs found and fixed

| Bug | Evidence | Fix |
| --- | --- | --- |
| `CZ_ENTER` and `CZ_REQUEST_TIME` left in one TCP write; rAthena's `clif_parse_WantToConnection_sub` requires the connect packet alone in its buffer and drops the session | probe `connect coalesced` counter, rAthena `src/map/clif.cpp` "FIXME: If the packet is not received at once" | `PlaySession.connect(to:)` no longer starts the keepalive before the map loads. Verified with `--no-enter-workaround`: coalesced 0 |
| 8 server packets had no length in the client table, so one of them (e.g. `ZC_UPDATE_CHARSTAT` 0x01f2 when a party member logs in) made the decoder drop the stream | golden tests + coverage report | Lengths added in `PacketDatabase.swift`; only 0x0b25 remains, and rAthena never sends it |
| `RANKLIST` sized 50 instead of 280 bytes | golden struct-size test | Hand fix in `Generated/packets.swift`, see [patches.md](patches.md) |
| `CZ_ACK_REQ_ADD_FRIENDS` flag was 1 byte; 0x0208 is 14 bytes at 20211103 | rAthena packet table | `flag` is `UInt32` |
| First 4-byte account-id read dropped bytes when the TCP segment was short | code review | `NetworkClient.receiveDataAndPacket` accumulates |

## Packets seen but not decoded

| Opcode | Name | Count (10 min) | Effect |
| --- | --- | --- | --- |
| 0x08e2 | `ZC_NAVIGATION_ACTIVE` (`clif_navigateTo`) | 10 | Framed and skipped; navigation UI is a known gap |

## Missing UI paths noticed

Listed in [KNOWN_GAPS.md](KNOWN_GAPS.md).

## Go or no-go

Go. The upstream base logs in, plays and reconnects against stock rAthena at the
pinned commit with no server patch. Kill criterion R1 (external server mode) and
R2 (obfuscation) are closed.

