# RO Mac Client

Native Apple Silicon client for rAthena. Swift 6 and Metal. Fork of
[arkadeleon/ragnarok-offline](https://github.com/arkadeleon/ragnarok-offline).

Status: planning. No code in this folder yet.

## Documents

- [PLAN.md](PLAN.md): goals, phases, milestones, estimates.
- [ARCHITECTURE.md](ARCHITECTURE.md): target design and reuse map.
- [DOCKER.md](DOCKER.md): local rAthena test stack, ports, accounts, reset.
- [TASKS.md](TASKS.md): phased checklist.
- [RISKS.md](RISKS.md): risk register and mitigations.
- [RESEARCH.md](RESEARCH.md): prior art, kRO sources, and source facts.

## Decisions

- Base: `arkadeleon/ragnarok-offline`, GPL-3.0, Swift 6, Metal, PACKETVER 20211103.
- Target: rAthena at the pinned commit below on a private server, macOS 15+,
  arm64 only.
- Test server: official rAthena Docker stack, pinned to commit
  `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`, obfuscation disabled in development.
- No Gravity assets in the repository. The user supplies kRO client files.
- No App Store distribution. GPL-3.0 conflicts with App Store DRM terms.
- Keep the upstream remote and rebase monthly. Do not rewrite working packages.
- Estimate: 11-18 weeks solo full-time to a playable core, 20-33 weeks to a
  signed v1.0 for one server.

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
