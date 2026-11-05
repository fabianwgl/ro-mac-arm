# Risk Register

Scoring: likelihood and impact are low, medium, or high. Review at every
milestone.

## R1: Upstream assumes a bundled local server

Likelihood: medium. Impact: high.

`arkadeleon/ragnarok-offline` ships an embedded Swift rAthena server and a
`ServerManager`. The game client screen does expose server address and port and
passes them to `GameSession.Configuration`, so external mode looks present, but
it is untested against a real rAthena process.

Mitigation:

- Phase 0 proves login to an external rAthena before any fork work.
- If settings cannot reach an external host, patch the smallest possible layer.
- Do not rewrite `RagnarokNetwork` unless P0 proves it cannot work.

Trigger: no external connection after one week of Phase 0.

## R2: Packet obfuscation

Likelihood: high. Impact: high.

Stock rAthena enables `PACKET_OBFUSCATION`. Upstream does not implement it.

Mitigation:

- Disable it on the development server with `#undef PACKET_OBFUSCATION` in
  `src/custom/defines_post.hpp`, then rebuild.
- Document the requirement in the install guide.
- Implement it before v1.0 if the target server must stay stock.
- Add golden tests for obfuscated and plain packets.

Trigger: client disconnects immediately after login on a stock server.

## R3: UI and content gaps

Likelihood: high. Impact: medium.

Upstream may not cover every window, skill, or NPC flow used by the server.

Mitigation:

- Scope v1.0 to the target server's enabled content.
- Keep a known-gaps list from Phase 0.
- Prefer server-side feature flags over client-side guesses.

Trigger: a required daily flow has no UI after Phase 3.

## R4: Upstream churn

Likelihood: high. Impact: medium.

Upstream is active and changes `RagnarokNetwork` and `RagnarokGame` often.

Mitigation:

- Monthly sync, small local patches, no long-lived forks of core files.
- Contribute reusable fixes upstream when possible.
- Keep a `patches/` note for every local divergence.

Trigger: merge conflicts block work for more than two days.

## R5: GPL and distribution

Likelihood: high. Impact: high.

Upstream is GPL-3.0. App Store DRM is incompatible. Shipping binaries requires
source distribution.

Mitigation:

- Distribute outside the App Store.
- Publish the exact source archive with every binary.
- Keep attribution and license files in the app and DMG.
- Do not copy GPL code into a differently licensed component.

Trigger: any plan to ship through the App Store.

## R6: Gravity assets and legal exposure

Likelihood: medium. Impact: high.

The client reads proprietary data and speaks a proprietary protocol. Gravity may
object to distribution.

Mitigation:

- No assets in git or in the DMG.
- Require the user to supply their own kRO client.
- Keep the project non-commercial.
- Respond quickly to takedown requests.

Trigger: public release with assets or a commercial plan.

## R7: Swift 6 concurrency and memory bugs

Likelihood: medium. Impact: medium.

Network, asset loading, and rendering cross actor boundaries.

Mitigation:

- Follow upstream patterns first.
- Add actors only where a measured race exists.
- Use thread sanitizer and address sanitizer in CI.
- Keep the render loop free of allocation in steady state.

Trigger: intermittent crash or hang under load.

## R8: Metal performance

Likelihood: low. Impact: medium.

RO is a 2002 workload. The GPU should be idle. The risk is frame spikes from
asset decode and UI, not shader cost.

Mitigation:

- Profile before optimizing.
- Cap caches by bytes.
- Stream textures and models.
- Use a fixed benchmark scene per release.

Trigger: frame time above 8.3 ms on M1.

## R9: Packet version drift

Likelihood: medium. Impact: high.

rAthena changes its default `PACKETVER` over time.

Mitigation:

- Pin the target server commit.
- Keep `PACKET_VERSION` configurable.
- Add support only when the target server changes.
- Re-run golden tests after every rAthena update.

Trigger: server update changes the default packet date.

## R10: GRF and format edge cases

Likelihood: medium. Impact: medium.

Encrypted GRFs, RSM2 models, custom effects, and malformed files can crash the
client.

Mitigation:

- Fail closed with a visible error, never crash.
- Add fixture tests for encrypted and malformed files.
- Keep a diagnostics window with the failing path.

Trigger: a valid kRO client fails to load.

## R11: Input and UI feel

Likelihood: medium. Impact: low.

A native client that feels wrong will not replace the Windows client for daily
play.

Mitigation:

- Match keyboard defaults from kRO.
- Support window layout and scale.
- Test with a real player for one hour per milestone.

Trigger: playtesters return to the Windows client for UI reasons.

## R12: Scope creep

Likelihood: high. Impact: high.

Full kRO parity is a multi-year project.

Mitigation:

- v1.0 is defined by the target server's content, not by kRO.
- Every new feature needs a server-side use case.
- Keep the non-goals list visible in `PLAN.md`.

Trigger: work starts on a system the target server does not enable.

## R13: Upstream abandonment

Likelihood: medium. Impact: high.

The project depends on one active upstream maintainer.

Mitigation:

- Keep the fork buildable at all times.
- Mirror releases and source archives.
- Document every local patch so the fork can continue alone.

Trigger: upstream has no commits for three months.

## R14: Docker stack drift and host port conflicts

Likelihood: medium. Impact: low.

The official rAthena Docker files and `sql-files` change with `master`. Port 3306
may already be taken by a local MySQL or MariaDB. A stale database volume keeps
an old schema after `sql-files` changes.

Mitigation:

- Pin the rAthena commit and record it in the compatibility manifest.
- Check port 3306 before starting; move the host side to 3307 if needed.
- Reset with `docker compose down --volumes` after schema changes.
- Treat the stack as development-only; never expose it to the internet.

Trigger: the stack fails to start, or the schema does not match the pinned code.

## R15: Docker architecture mismatch

Likelihood: low. Impact: low.

An x86 image under emulation would be slow and may fail to compile.

Mitigation:

- Use Docker Desktop for Apple Silicon.
- Check `docker image inspect ... --format '{{.Architecture}}'` prints `arm64`.
- Rebuild with `docker compose build --no-cache` if it does not.

Trigger: build times are extreme or the builder crashes with an exec format
error.

## R16: Stale Docker database volume

Likelihood: medium. Impact: low.

MariaDB imports `sql-files` only when the volume is empty. Schema changes or a
failed import leave the stack on old tables.

Mitigation:

- Inspect `docker compose logs db` after the first start.
- Reset with `docker compose down --volumes` and start `db` again.
- Keep test data disposable.

Trigger: missing tables, login failures after a server update, or SQL import
errors in the db log.

## Assumptions

- The target server stays on `PACKETVER 20211103` for the first release.
- Upstream remains GPL-3.0 and keeps the current package split.
- External server mode works or needs only a thin patch.
- Docker Desktop works on the development Mac with arm64 images.
- The developer has Swift and Metal experience.
- The user has the legal 2021 kRO archive at
  `~/Downloads/kRO_FullClient_20210406.zip`.

## Kill criteria

- P0 cannot connect to an external server and the fix requires a network rewrite.
  Reassess and consider `Korangar` as the base.
- Packet obfuscation cannot be implemented within Phase 2 and the server cannot
  disable it. Stop and re-plan.
- Upstream relicenses or becomes closed. Freeze the current fork and maintain it
  internally.
