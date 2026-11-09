# Risk Register

Scoring: likelihood and impact are low, medium, or high. Review at every gate
([PLAN.md](PLAN.md) section 6).

Reviewed 2026-11-09 with the change of direction (solo play, 1st and 2nd jobs,
thin fork). The order below is by how much each risk matters now.

| Risk | Likelihood | Impact | State |
| --- | --- | --- | --- |
| R17 Nothing has been seen by a person | high | high | open, new |
| R18 The work exists on one disk | medium | high | open, new |
| R19 Building what upstream builds | high | medium | open, new |
| R4 Upstream churn | high | medium | open, measured |
| R11 Input and UI feel | high | medium | open, raised |
| R20 Two servers, one set of evidence | medium | medium | open, new |
| R12 Scope creep | medium | high | open, now bounded |
| R21 CI lags the local toolchain | high | low | open, new |
| R22 Frozen code rots | medium | low | open, new |
| R3 UI and content gaps | medium | medium | open, narrowed |
| R7 Swift 6 concurrency and memory bugs | medium | medium | open |
| R10 GRF and format edge cases | low | medium | open |
| R13 Upstream abandonment | low | high | open |
| R6 Gravity assets and legal exposure | low | high | open, lower |
| R9 Packet version drift | low | medium | open, lower |
| R14 to R16 Docker stack | low | low | open, development only |
| R1 Upstream assumes a bundled server | | | closed |
| R2 Packet obfuscation | | | closed |
| R5 GPL and distribution | | | dormant |
| R8 Metal performance | | | closed for this Mac |

## R17: Nothing has been seen by a person

Likelihood: high. Impact: high.

Every check so far is a unit test or a headless probe run. The probe calls the
same entry points as the UI but draws nothing, so a window that is laid out
wrong, an effect in the wrong place or controls that feel wrong pass every
check. The first screenshot of the real window found a defect in one look.
None of the windows the fork added has been on a screen in front of a person.

Mitigation:

- Feature freeze until a person has played for an hour (gate G3).
- A scripted GUI run with a screenshot per window before that (gate G2).
- A feature is done at step 4 of the verification ladder, not at step 2.

Trigger: any new window or effect merged without a screenshot.

## R18: The work exists on one disk

Likelihood: medium. Impact: high.

Everything since PR #1 is local: one branch, not pushed, plus agent worktrees.
One worktree held a finished commit that was not merged, with uncommitted
work on top of it; it was found by accident.

Mitigation:

- Push after every merged piece of work.
- One integration branch. An agent worktree is removed when its commits are
  merged, after a check for uncommitted files.
- The public or private question is settled first so pushing is not put off.

Trigger: more than a day of commits not on `origin`.

## R19: Building what upstream builds

Likelihood: high. Impact: medium.

Upstream works toward the same solo game with a written list
([ROBROWSER_PARITY.md](../ROBROWSER_PARITY.md)): skill effects, cart, pets,
quests, settings, then homunculus, refine and navigation. The fork has
already built some of these its own way (66 skill effects, pet and
homunculus windows, preferences, the quest log). When upstream ships its
version, one of the two is thrown away and the merge is the price.

Mitigation:

- The ownership table in PLAN.md section 4: single-player content is
  upstream's.
- What the fork already built in upstream's area is offered upstream early,
  so there is one version.
- At each weekly merge, read what upstream added and prefer it over the local
  version (UPSTREAM_SYNC.md).

Trigger: a weekly merge conflicts in a file where both sides added the same
feature.

## R4: Upstream churn

Likelihood: high. Impact: medium.

Measured 2026-11-09: 16 commits in the last 7 days, 156 in 30, 437 in 90,
most of them in `RagnarokGame`, where the fork changes 31 upstream files.
The fork is 365 files and 68,000 lines away from upstream. A monthly merge
would meet about 150 commits at once.

Mitigation:

- Weekly merge. Small conflicts often, not large ones rarely.
- New code in new files; hooks in upstream files stay small.
- Every modified upstream file is listed in [patches.md](patches.md).
- Fixes go upstream so the patch list shrinks.

Trigger: a weekly merge takes more than half a day.

## R11: Input and UI feel

Likelihood: high. Impact: medium.

The windows are upstream's: SwiftUI, fixed layout, round touch buttons for
sit, attack and pick up, made for iOS and visionOS as much as for the Mac.
The fork added keyboard bindings, WASD and a controller, but nobody has
judged how it feels. A solo player with no server to keep them will stop
playing a client that feels wrong.

Mitigation:

- The playtest decides, not the plan.
- After it: one decision on the look of the windows (PLAN.md section 2).
- Shell work (keyboard, mouse, window behavior) is the fork's own area and
  comes before content.

Trigger: the playtest bug list is mostly about feel.

## R20: Two servers, one set of evidence

Likelihood: medium. Impact: medium.

All protocol evidence is from the Docker rAthena at `d4b8e7b8`. The player
will use the embedded `swift-rathena`, a different rAthena snapshot (last
merged from rAthena in September 2026) with SQLite, another config and
another command set. It has never been run in this fork.

Mitigation:

- Gate G1 before anything else depends on it.
- COMPATIBILITY.md records both servers.
- The packet structs come from upstream's generator, which reads rAthena
  headers, so the client and the embedded server should agree; the fork's
  hand-written packets (`PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY` and others) are
  the ones to recheck.

Trigger: the probe passes on Docker and fails on the embedded server.

## R12: Scope creep

Likelihood: medium. Impact: high.

The old rule, "the content the target server enables", allowed everything,
and work went into guilds, vending and mail for a player who turns out to be
alone. The cap is now explicit: 1st and 2nd jobs, solo.

Mitigation:

- The non-goals list in PLAN.md section 3 and the frozen list in section 8.
- Every new task names the line of the v1.0 definition it serves.

Trigger: work starts on something in the non-goals or the frozen list.

## R21: CI lags the local toolchain

Likelihood: high. Impact: low.

The developer Mac runs Xcode 27. The hosted runner has Xcode 26.6, where
`swift test` for RagnarokGame does not compile (`#bundle` without a resource
bundle). CI has been red since the first run and nothing has been pushed
since 2026-11-06, so it guards nothing.

Mitigation:

- Run that package's tests through `xcodebuild test` on the runner (P7-08).
- Until CI is green, the local test run before each merge is the only check;
  say so in the merge.

Trigger: a second package fails on the runner only.

## R22: Frozen code rots

Likelihood: medium. Impact: low.

Half of the fork's source is multiplayer code no one will use. Each upstream
merge can break it, and its tests are the only users.

Mitigation:

- Keep its unit tests in the normal test run.
- Offer it upstream (P7-12). If upstream declines and it starts to cost merge
  time, delete it; git keeps it.

Trigger: a merge is blocked by a frozen file twice.

## R3: UI and content gaps

Likelihood: medium. Impact: medium.

Inside the cap, known gaps are: 141 of 224 active skills without a skill
specific effect, statuses that only show as an icon, no cart window, job
changes not walked.

Mitigation: PLAN.md section 5 says which of these v1.0 needs; P7-14 orders
them; [KNOWN_GAPS.md](KNOWN_GAPS.md) marks each gap as in or out of scope.

Trigger: the playtest cannot continue because of a missing window.

## R7: Swift 6 concurrency and memory bugs

Likelihood: medium. Impact: medium.

Network, asset loading and rendering cross actor boundaries. The embedded
server adds four servers in the app's own process.

Mitigation:

- Follow upstream patterns first.
- Add actors only where a measured race exists.
- A thread sanitizer run of the package tests before v1.0.

Trigger: intermittent crash or hang during play.

## R10: GRF and format edge cases

Likelihood: low. Impact: medium.

One kRO data set is in use (2021-04-06) and loads. Upstream owns the format
readers.

Mitigation: fail closed with a visible error; report format bugs upstream.

Trigger: a file the client needs fails to load.

## R13: Upstream abandonment

Likelihood: low. Impact: high.

The thin-fork strategy leans on one maintainer. Today that maintainer is the
most active part of the project.

Mitigation:

- The fork builds on its own at every commit.
- If upstream stops, the ownership table is dropped and the fork builds what
  it needs.

Trigger: no upstream commits for a month.

## R6: Gravity assets and legal exposure

Likelihood: low. Impact: high.

No release is planned, which removes most of this. What remains: the
repository is public, so nothing derived from Gravity files may be committed.
Screenshots of the game count.

Mitigation:

- `.gitignore` covers client files and the GUI run folder.
- The name tables in the tree are generated from rAthena's YAML, not from
  kRO files ([localization.md](localization.md)).

Trigger: a commit contains a game screenshot or an extracted asset.

## R9: Packet version drift

Likelihood: low. Impact: medium.

Both servers are at PACKETVER 20211103 and both are pinned: the Docker stack
by commit, the embedded one by submodule.

Mitigation: rerun the golden tests when either pin moves.

Trigger: an upstream merge moves the `swift-rathena` submodule.

## R14 to R16: Docker stack

Likelihood: low. Impact: low.

Port conflicts, architecture mismatch and stale database volumes. The stack
is a development reference now and the player does not need it. Fixes are in
[DOCKER.md](DOCKER.md): check port 3306, check the image is `arm64`, reset
with `docker compose down --volumes`.

## Closed or dormant

- **R1 Upstream assumes a bundled local server.** Closed. The external server
  path works (Phases 0 to 3). The bundled server is now wanted, not feared.
- **R2 Packet obfuscation.** Closed for PACKETVER 20211103: rAthena's keys
  are zero after 2018-03-07 and the client works against a stock server.
- **R5 GPL and distribution.** Dormant. Nothing is distributed. The source is
  public under GPL-3.0 already. Returns if a binary is ever handed to someone.
- **R8 Metal performance.** Closed for this Mac: 143.9 fps at 2560x1440 on a
  144 Hz display, GPU time 2 to 3 ms on average ([perf.md](perf.md)). The M1 target of
  the original plan was never measured and no longer applies.

## Assumptions

- One player, this Mac, no release.
- The embedded server works in the fork's build (unproven, gate G1).
- Upstream stays GPL-3.0, active, and keeps the current package split.
- Upstream accepts at least the bug fixes. If it accepts nothing, the fork
  carries its patches and R4 gets worse.
- The kRO 2021-04-06 data stays the data set.

## Kill criteria

- The playtest shows the client is not something the developer wants to play
  and the reasons are upstream's design (windows, controls), not bugs. Then
  stop feature work and either wait for upstream or reconsider the base.
- Weekly merges cost more than the fork's own work for a month. Then cut the
  frozen systems, and if that is not enough, reduce the fork to the shell and
  the tools.
- Upstream relicenses or goes closed. Freeze at the last GPL commit.
