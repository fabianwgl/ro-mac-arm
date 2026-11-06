# Releasing RO Mac Client

Releases are built outside the App Store with `scripts/release.sh`. The script
archives, signs with Developer ID, notarizes, staples, builds the DMG, writes the
compatibility manifest, creates the GPL source archive, and writes checksums.

Do not use App Store, TestFlight, or Sparkle for these builds.

## One-time notary setup

Create a notarytool keychain profile on the build Mac. Use an Apple ID
app-specific password, not your account password:

```sh
xcrun notarytool store-credentials "ro-notary" \
  --apple-id "you@example.com" \
  --team-id "4RGKC487ZB" \
  --password "app-specific-password"
```

The profile name is local to the keychain. It is not stored in the repository.

Check that the Developer ID identity is present:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `RO_TEAM_ID` | `4RGKC487ZB` | Developer ID team id |
| `RO_NOTARY_PROFILE` | unset | notarytool keychain profile. Required unless `--skip-notarize` is passed |
| `RO_RATHENA_COMMIT` | `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39` | rAthena commit recorded in the manifest |
| `RO_PACKET_OBFUSCATION` | `false` | Packet obfuscation recorded in the manifest |

Example:

```sh
export RO_NOTARY_PROFILE=ro-notary
export RO_TEAM_ID=4RGKC487ZB
```

## Before running

- Commit every change. The script refuses a dirty tree unless `--allow-dirty`
  is passed, and the source archive is always built from `HEAD`.
- Check out the submodule so it is included in the source archive:

  ```sh
  git submodule update --init --recursive
  ```

- Make sure the app version in the build settings is the version you want to
  ship. The script reads `CFBundleShortVersionString` from the exported app when
  `--version` is omitted.

## Run the release

```sh
scripts/release.sh --version 1.0.0 --output dist/
```

Options:

- `--version <x.y.z>`: Release version. Omit it to use the built app version.
- `--skip-notarize`: Build a signed but unnotarized DMG for local testing. Use
  this when `RO_NOTARY_PROFILE` is not available.
- `--output <dir>`: Output directory. Default `dist/`.
- `--allow-dirty`: Allow uncommitted changes. Do not use this for a real release.

The script stops at the first failing step with a non-zero exit status.

## Output

The output directory contains:

- `RO-Mac-Client-<version>.dmg`: Signed, notarized, and stapled app plus
  `LICENSE`, `NOTICE`, `INSTALL.md`, `compatibility-manifest.json`, and an
  `/Applications` symlink.
- `RO-Mac-Client-<version>-source.tar.gz`: Exact `HEAD` source, including the
  `swift-rathena` submodule when checked out, plus `LICENSE`, `NOTICE`, and the
  same manifest.
- `SHA256SUMS.txt`: SHA-256 checksums for the DMG and source archive.
- `compatibility-manifest.json`: standalone copy of the manifest that is also
  inside the DMG and the source archive.

## What to upload

Upload all of these to the release page:

- The DMG.
- The source archive.
- `SHA256SUMS.txt`.
- `compatibility-manifest.json`, also included inside the DMG and the source
  archive.

Never upload `data.grf`, `rdata.grf`, `BGM`, or any other Gravity files.

## GPL source obligation

RO Mac Client is GPL-3.0. Every binary release must publish the complete
corresponding source for the exact commit that produced it. The source archive
from the script satisfies this for `HEAD`, including the `swift-rathena`
submodule, provided the submodule was checked out before running. Keep the
source archive available for as long as the binary is distributed.

## Tag naming

Tag the released commit with `vX.Y.Z-romac`, for example `v1.0.0-romac`. Tag the
commit used for the binary, not a later commit.
