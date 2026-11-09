# RO Mac Client

Native Apple Silicon client for rAthena. Swift 6 and Metal. Fork of
[arkadeleon/ragnarok-offline](https://github.com/arkadeleon/ragnarok-offline).

Status 2026-11-09: the core game loop is verified headless against a Docker
rAthena; nobody has played the client yet. The direction was revised that day:
solo play on this Mac against the embedded server, 1st and 2nd jobs, a thin
fork that merges upstream weekly. Start with [PLAN.md](PLAN.md); the current
work is Phase 7 in [TASKS.md](TASKS.md).

## Documents

- [PLAN.md](PLAN.md): goals, phases, milestones, estimates.
- [ARCHITECTURE.md](ARCHITECTURE.md): target design and reuse map.
- [DOCKER.md](DOCKER.md): local rAthena test stack, ports, accounts, reset.
- [TASKS.md](TASKS.md): phased checklist.
- [RISKS.md](RISKS.md): risk register and mitigations.
- [KNOWN_GAPS.md](KNOWN_GAPS.md): what works, what is missing, what is out of scope.
- [COMPATIBILITY.md](COMPATIBILITY.md): client build against each server.
- [agent-brief-g1-g2.md](agent-brief-g1-g2.md): prompt for the agent that takes the next tasks (P7-01 to P7-05).
- [RESEARCH.md](RESEARCH.md): prior art, kRO sources, and source facts.
- [INSTALL.md](INSTALL.md), [RELEASING.md](RELEASING.md), [UPSTREAM_SYNC.md](UPSTREAM_SYNC.md), [patches.md](patches.md): install, release, sync, local divergences.

## Decisions

- Base: `arkadeleon/ragnarok-offline`, GPL-3.0, Swift 6, Metal, PACKETVER 20211103.
- Audience: one player, this Mac. No friends server, no release.
- Content: Novice, 1st and 2nd jobs.
- Play server: the rAthena embedded in the app (`swift-rathena`), once gate G1
  passes. Reference server for tests: the official rAthena Docker stack pinned
  to `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`.
- Upstream: merged weekly. Upstream owns single-player content; the fork owns
  the macOS shell, the verification tools and fixes, and offers fixes back.
- No Gravity assets in the repository. The user supplies kRO client files.
- macOS 15+, arm64 only.

## Why this base

Upstream already has the hard parts: Metal renderer, GRF and file format readers,
sprite and effect pipelines, login/char/map network sessions, packet definitions
for PACKETVER 20211103, and a macOS 15 app target. The port is mostly protocol
compatibility, UI coverage, macOS packaging, and maintenance.

## Related projects

- rAthena server: https://github.com/rathena/rathena
- roBrowserLegacy reference client: https://github.com/MrAntares/roBrowserLegacy
- Korangar Rust client: https://github.com/vE5li/korangar

## Client files

kRO files are not part of this project. Source links, the MEGA decryption key,
and the required file list are in [RESEARCH.md](RESEARCH.md).

The 2021-04-06 kRO archive is downloaded at
`~/Downloads/kRO_FullClient_20210406.zip` (3.4 GB). Extract it and copy
`data.grf` and `BGM` into the app's Local Client Files directory before Phase 0.
