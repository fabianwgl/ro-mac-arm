# Upstream Sync

The fork tracks `arkadeleon/ragnarok-offline` and stays thin
([PLAN.md](PLAN.md) section 4). Merge upstream every week: it makes about 150
commits a month, most of them in `RagnarokGame`.

## Remotes and branches

| Name | What it is |
| --- | --- |
| `upstream` | `https://github.com/arkadeleon/ragnarok-offline.git`. `upstream/master` is the mirror of upstream; no local branch copies it |
| `origin` | `git@github.com:fabianwgl/ro-mac-arm.git`. Public, and not a GitHub fork of upstream |
| `main` | The fork: upstream plus the fork's work. Releases, if there ever are any, are cut from it |
| `integrate-m2` | Current integration branch, to be merged into `main` (TASKS.md P7-07) |
| `chore/upstream-sync-YYYY-MM-DD` | One per weekly merge |

Pull requests to upstream cannot come from `origin`, because it is outside
upstream's fork network. They need a GitHub fork of
`arkadeleon/ragnarok-offline` and one branch per fix, cut from
`upstream/master`, not from `main`.

## Who builds what

The rule that keeps merges small is in PLAN.md section 4. In short: upstream
owns the renderer, the effects and the single-player windows; the fork owns
the macOS shell, the verification tools and bug fixes. Before starting
anything in upstream's area, read
[ROBROWSER_PARITY.md](../ROBROWSER_PARITY.md) and the last week of upstream
commits.

## Weekly procedure

1. Fetch: `git fetch upstream`.
2. Read what came in:
   `git log --stat <last merged upstream commit>..upstream/master`.
   Note anything that overlaps a local feature.
3. Try the merge without touching the tree:
   `git merge-tree --write-tree --name-only HEAD upstream/master`.
   It prints the conflicting files.
4. Create the branch and merge:
   `git switch -c chore/upstream-sync-YYYY-MM-DD` then
   `git merge upstream/master`.
5. Update submodules: `git submodule update --init --recursive`. If
   `swift-rathena` moved, the embedded server changed: rerun the golden packet
   tests and update [COMPATIBILITY.md](COMPATIBILITY.md).
6. Resolve conflicts. Where upstream added a feature the fork also has, keep
   upstream's and reapply the smallest local delta, or delete the local
   version. In `project.pbxproj` the fork took the display name out of the
   build settings (it is in the xcconfig); when upstream edits that line,
   keep the fork's side. That is the one conflict of the 2026-11-09 trial
   merge.
7. Build:
   `xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`.
8. Run the package tests (`swift test --package-path Packages/<Name>` for
   RagnarokPackets, RagnarokNetwork, RagnarokGame, DataCompression) and the
   golden packet tests. The frozen multiplayer systems are covered by the
   RagnarokGame tests.
9. Run the probe for ten minutes against the server the player uses.
10. Merge into the integration branch and push.
11. Update [patches.md](patches.md) if a local patch went away or a new one was
    needed.

The first build on a fresh machine needs
`xcodebuild -downloadComponent MetalToolchain`.

## Local divergence

Measured 2026-11-09 against `upstream/master`: 365 files changed, 68,684 lines
added, 295 files new, 69 upstream files modified. By area: docs and run
records 19,000 lines, tests 17,200, `RagnarokGame` sources 16,800, tools
7,500, other packages 4,100, app shell 650.

New files do not conflict. The 69 modified upstream files do. List them with:

```sh
git diff --diff-filter=M --numstat upstream/master...HEAD | sort -rn
```

The largest today: `PacketFactory.swift` (+748, builders only),
`MapSceneView.swift` (+297), `PlaySession.swift` (+248 -75),
`SkillEffectTable.swift` (+219), `GameSession.swift` (+107).

Rules:

- New code goes into a new file, as an extension where it needs upstream
  types (`PlaySession+Guild.swift`).
- A change inside an upstream file is a hook: a `case` that forwards to the
  new file, a call, a parameter. Keep it to a few lines.
- Every modified upstream file has a row in [patches.md](patches.md) with the
  reason and whether it can go upstream.
- A fix to upstream's own behavior is offered upstream.

## What to offer upstream

In this order (TASKS.md P7-11 and P7-12). Each pull request needs the
developer's go.

1. Bug fixes, one per pull request: the `RANKLIST` generator bug, the eight
   packets without a length, the friend reply size, the account id read on a
   short TCP read, the keepalive sharing a TCP read with `CZ_ENTER`, the
   6-character login minimum, the 60 fps cap, NPC dialogs staying open after
   a map change.
2. Decoder hardening and its tests.
3. The skill effect reference table and the audit script.
4. The multiplayer systems and the probe, if upstream wants them.
