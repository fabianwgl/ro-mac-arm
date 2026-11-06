# Upstream Sync

The fork tracks `arkadeleon/ragnarok-offline` and keeps local divergence small.
Sync once a month, or sooner after a security or protocol fix.

## Remotes

| Remote | URL | Purpose |
| --- | --- | --- |
| `upstream` | `https://github.com/arkadeleon/ragnarok-offline.git` | Source of truth for the fork base |
| `origin` | the user's fork | Fork repository |

`main` tracks `upstream/master`. Upstream has no release branch; fork releases
are cut from `main`.

Set the remotes once:

```sh
git remote add upstream https://github.com/arkadeleon/ragnarok-offline.git
git remote set-url origin <fork-url>
git fetch upstream
```

## Monthly procedure

1. Fetch upstream: `git fetch upstream`.
2. Create a sync branch: `git switch -c chore/upstream-sync-YYYY-MM main`.
3. Merge upstream: `git merge upstream/master`.
4. Update submodules: `git submodule update --init --recursive`.
5. Resolve conflicts in `Packages/RagnarokNetwork` and `Packages/RagnarokGame`
   first. They change most often and the protocol work lives there.
6. Build:
   `xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`.
7. Run the package tests from `Packages/<Name>` with `swift test`, and run the
   golden packet tests.
8. Rerun the Docker smoke test in [DOCKER.md](DOCKER.md). Log in, enter a map,
   walk, and chat.
9. Open a pull request into `main`. Do not merge it until CI is green and the
   local smoke test passes.

The first build on a fresh machine needs
`xcodebuild -downloadComponent MetalToolchain`.

## Local divergence

Every local change that upstream does not have gets a row in
[patches.md](patches.md): the file or area, why the divergence exists, and
whether it could be upstreamed. Keep patches small and behind flags where
possible.

If upstream adds a file or feature that overlaps a local patch, prefer the
upstream version and reapply the smallest possible local delta.

## Release

Cut releases from `main` after a sync:

1. Confirm CI is green and the compatibility table is current.
2. Tag `vX.Y.Z-romac`, for example `v0.1.0-romac`.
3. Attach the DMG, checksum, compatibility manifest, and GPL source archive.

Upstream tags are references only. They do not name fork releases.
