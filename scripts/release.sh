#!/bin/bash
#
# Build, sign, notarize, and package RO Mac Client for distribution outside the
# App Store. See docs/port/RELEASING.md.
#
# This script is intentionally bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

PROJECT=RagnarokOffline.xcodeproj
SCHEME=RagnarokOffline
APP_NAME=RagnarokOffline.app
VOLUME_NAME="RO Mac Client"

TEAM_ID=${RO_TEAM_ID:-4RGKC487ZB}
RATHENA_COMMIT=${RO_RATHENA_COMMIT:-d4b8e7b8f16061cc2496d377ac8f777ce72a4f39}
NOTARY_PROFILE=${RO_NOTARY_PROFILE:-}
PACKET_OBFUSCATION=${RO_PACKET_OBFUSCATION:-false}

VERSION=""
OUTPUT_DIR=dist
SKIP_NOTARIZE=0
ALLOW_DIRTY=0

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [options]

Build a signed, notarized, and stapled DMG of RagnarokOffline.app, then write a
GPL source archive, a compatibility manifest, and SHA256SUMS.txt.

Options:
  --version <x.y.z>  Release version. Defaults to the built app's
                     CFBundleShortVersionString.
  --skip-notarize    Build an unnotarized DMG for local testing. Requires the
                     signing identity but not RO_NOTARY_PROFILE.
  --output <dir>     Output directory. Default: dist/
  --allow-dirty      Allow a dirty git working tree.
  -h, --help         Show this help.

Environment:
  RO_TEAM_ID             Developer ID team id. Default: 4RGKC487ZB
  RO_NOTARY_PROFILE      notarytool keychain profile. Required unless
                         --skip-notarize is passed.
  RO_RATHENA_COMMIT      rAthena commit for the manifest.
                         Default: d4b8e7b8f16061cc2496d377ac8f777ce72a4f39
  RO_PACKET_OBFUSCATION  true or false. Default: false

The git submodule must be checked out so the source archive includes it:
  git submodule update --init --recursive
EOF
}

step() {
  printf '\n==> %s\n' "$1"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

populate_source_staging() {
  local staging=$1
  local name=$2
  local list="$TMP_ROOT/submodules.txt"
  local path
  local sha

  git archive --format=tar --prefix="$name/" HEAD | tar -xf - -C "$staging" \
    || return 1

  git config --file ".gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | sed 's/^[^ ]* //' > "$list" || true
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    sha=$(git ls-tree HEAD "$path" | awk '{print $3}')
    [ -n "$sha" ] || return 1
    if [ ! -e "$path/.git" ]; then
      printf 'Submodule is not checked out: %s\n' "$path" >&2
      return 1
    fi
    git -C "$path" archive --format=tar --prefix="$name/$path/" "$sha" \
      | tar -xf - -C "$staging" || return 1
  done < "$list"
}

source_has_submodules() {
  local list="$TMP_ROOT/submodules.txt"
  local path

  [ -f ".gitmodules" ] || return 0

  git config --file ".gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | sed 's/^[^ ]* //' > "$list" || true
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -e "$SOURCE_STAGING/$SOURCE_NAME/$path" ] || return 1
  done < "$list"

  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || fail "--version requires a value"
      VERSION=$2
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || fail "--output requires a directory"
      OUTPUT_DIR=$2
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1 (use --help)"
      ;;
  esac
done

if [ -n "$VERSION" ]; then
  if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "--version must be x.y.z, got: $VERSION"
  fi
fi

case "$PACKET_OBFUSCATION" in
  true|TRUE|1|yes|YES)
    OBFUSCATION_JSON=true
    ;;
  false|FALSE|0|no|NO)
    OBFUSCATION_JSON=false
    ;;
  *)
    fail "RO_PACKET_OBFUSCATION must be true or false, got: $PACKET_OBFUSCATION"
    ;;
esac

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ro-release.XXXXXX") || fail "cannot create temporary directory"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
step "1. Preflight"

[ -f "$PROJECT/project.pbxproj" ] || fail "run this script from the repository root"

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  fail "git working tree is dirty; commit your changes or pass --allow-dirty"
fi

for tool in xcodebuild xcrun hdiutil codesign spctl shasum security ditto lipo; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

IDENTITY_LINE=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -F "Developer ID Application" \
  | grep -F "$TEAM_ID" \
  | head -n 1 || true)
[ -n "$IDENTITY_LINE" ] || fail "no Developer ID Application identity for team $TEAM_ID"
IDENTITY=$(printf '%s\n' "$IDENTITY_LINE" | sed -n 's/.*"\(.*\)".*/\1/p')
[ -n "$IDENTITY" ] || fail "could not parse signing identity from: $IDENTITY_LINE"

if [ "$SKIP_NOTARIZE" -eq 0 ] && [ -z "$NOTARY_PROFILE" ]; then
  fail "RO_NOTARY_PROFILE is not set; create a notarytool profile or pass --skip-notarize for a local, unnotarized DMG"
fi

mkdir -p "$OUTPUT_DIR" || fail "cannot create output directory: $OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
BUILD_DIR="$OUTPUT_DIR/build"
ARCHIVE="$BUILD_DIR/RO.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME"
mkdir -p "$BUILD_DIR" || fail "cannot create build directory: $BUILD_DIR"

echo "Team:     $TEAM_ID"
echo "Identity: $IDENTITY"
echo "Output:   $OUTPUT_DIR"

# ---------------------------------------------------------------------------
step "2. Archive"

rm -rf "$ARCHIVE"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  || fail "xcodebuild archive failed"

# ---------------------------------------------------------------------------
step "3. Export signed app"

EXPORT_OPTIONS="$TMP_ROOT/ExportOptions.plist"
sed "s|__TEAM_ID__|$TEAM_ID|g" "scripts/ExportOptions.plist" > "$EXPORT_OPTIONS" \
  || fail "cannot prepare ExportOptions.plist"
if grep -q "__TEAM_ID__" "$EXPORT_OPTIONS"; then
  fail "team id placeholder was not replaced in ExportOptions.plist"
fi

rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  || fail "xcodebuild -exportArchive failed"

[ -d "$APP" ] || fail "exported app not found: $APP"

APP_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)
[ -n "$APP_VERSION" ] || fail "cannot read CFBundleShortVersionString from $APP"

if [ -z "$VERSION" ]; then
  VERSION=$APP_VERSION
elif [ "$VERSION" != "$APP_VERSION" ]; then
  warn "--version $VERSION does not match the built app version $APP_VERSION"
fi

echo "Version:  $VERSION"

# ---------------------------------------------------------------------------
step "4. Verify signature and architecture"

codesign --verify --deep --strict --verbose=2 "$APP" \
  || fail "codesign verification failed for $APP"

ENTITLEMENTS=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)
if [ -n "$ENTITLEMENTS" ]; then
  printf 'Entitlements:\n%s\n' "$ENTITLEMENTS"
else
  echo "Entitlements: none"
fi

CODE_SIGN_INFO=$(codesign -dvv "$APP" 2>&1 || true)
printf '%s\n' "$CODE_SIGN_INFO"
case "$CODE_SIGN_INFO" in
  *"flags=0x10000(runtime)"*)
    ;;
  *)
    fail "hardened runtime is not enabled (expected flags=0x10000(runtime))"
    ;;
esac

EXECUTABLE=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)
[ -n "$EXECUTABLE" ] || fail "cannot read CFBundleExecutable from $APP"
MAIN_BINARY="$APP/Contents/MacOS/$EXECUTABLE"
[ -f "$MAIN_BINARY" ] || fail "main binary not found: $MAIN_BINARY"
ARCHS=$(lipo -archs "$MAIN_BINARY" 2>/dev/null || true)
[ "$ARCHS" = "arm64" ] || fail "expected an arm64-only binary, got: ${ARCHS:-unknown}"

# ---------------------------------------------------------------------------
step "5. Notarize and staple the app"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  warn "skipping app notarization because --skip-notarize was passed"
else
  [ -n "$NOTARY_PROFILE" ] || fail "RO_NOTARY_PROFILE is not set; cannot notarize the app"
  APP_ZIP="$TMP_ROOT/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP" "$APP_ZIP" \
    || fail "cannot create app zip for notarization"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "notarytool rejected the app"
  xcrun stapler staple "$APP" \
    || fail "cannot staple the app"
fi

# ---------------------------------------------------------------------------
step "6. Build and sign the DMG"

UPSTREAM_COMMIT=""
if git remote get-url upstream >/dev/null 2>&1; then
  UPSTREAM_COMMIT=$(git merge-base HEAD upstream/master 2>/dev/null || true)
fi
CLIENT_COMMIT=$(git rev-parse HEAD)
TODAY=$(date +%Y-%m-%d)

MANIFEST="$OUTPUT_DIR/compatibility-manifest.json"
/usr/bin/python3 - \
  "docs/port/compatibility-manifest.template.json" \
  "$MANIFEST" \
  "$APP_VERSION" \
  "$CLIENT_COMMIT" \
  "$UPSTREAM_COMMIT" \
  "$RATHENA_COMMIT" \
  "$OBFUSCATION_JSON" \
  "$TODAY" <<'PY' || fail "cannot write compatibility manifest"
import json
import sys

(
    template,
    output,
    client_version,
    client_commit,
    upstream_commit,
    rathena_commit,
    obfuscation,
    date,
) = sys.argv[1:9]

with open(template, encoding="utf-8") as handle:
    manifest = json.load(handle)

manifest["clientVersion"] = client_version
manifest["clientCommit"] = client_commit
manifest["upstreamCommit"] = upstream_commit
manifest["rathenaCommit"] = rathena_commit
manifest["packetVersion"] = 20211103
manifest["packetObfuscation"] = obfuscation == "true"
manifest["date"] = date

with open(output, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

STAGING="$TMP_ROOT/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING" || fail "cannot create DMG staging directory"
ditto "$APP" "$STAGING/$APP_NAME" || fail "cannot copy app into DMG staging"
ln -s "/Applications" "$STAGING/Applications" || fail "cannot create Applications symlink"
cp "LICENSE" "$STAGING/LICENSE" || fail "cannot copy LICENSE into DMG staging"
cp "NOTICE" "$STAGING/NOTICE" || fail "cannot copy NOTICE into DMG staging"
cp "docs/port/INSTALL.md" "$STAGING/INSTALL.md" || fail "cannot copy INSTALL.md into DMG staging"
cp "$MANIFEST" "$STAGING/compatibility-manifest.json" || fail "cannot copy manifest into DMG staging"

DMG="$OUTPUT_DIR/RO-Mac-Client-$VERSION.dmg"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" \
  || fail "hdiutil could not create the DMG"

codesign --timestamp -s "$IDENTITY" "$DMG" \
  || fail "cannot sign the DMG"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  warn "skipping DMG notarization because --skip-notarize was passed"
else
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "notarytool rejected the DMG"
  xcrun stapler staple "$DMG" \
    || fail "cannot staple the DMG"
fi

# ---------------------------------------------------------------------------
step "7. Gatekeeper assessment"

if spctl -a -vvv -t install "$DMG"; then
  echo "DMG accepted by Gatekeeper"
elif [ "$SKIP_NOTARIZE" -eq 1 ]; then
  warn "DMG rejected by Gatekeeper; expected with --skip-notarize"
else
  fail "DMG rejected by Gatekeeper"
fi

if spctl -a -vvv "$APP"; then
  echo "App accepted by Gatekeeper"
elif [ "$SKIP_NOTARIZE" -eq 1 ]; then
  warn "app rejected by Gatekeeper; expected with --skip-notarize"
else
  fail "app rejected by Gatekeeper"
fi

# ---------------------------------------------------------------------------
step "8. Source archive"

SOURCE_NAME="RO-Mac-Client-$VERSION-source"
SOURCE_ARCHIVE="$OUTPUT_DIR/$SOURCE_NAME.tar.gz"
SOURCE_TARBALL="$TMP_ROOT/$SOURCE_NAME.tar.gz"
SOURCE_STAGING="$TMP_ROOT/source"

rm -rf "$SOURCE_STAGING"
mkdir -p "$SOURCE_STAGING" || fail "cannot create source staging directory"

# git-archive-all.sh expects GNU tar and a newer bash. Fall back to git archive
# and a per-submodule archive when it is not usable on this Mac.
SOURCE_READY=0
if "./git-archive-all.sh" \
  --format tar.gz \
  --prefix "$SOURCE_NAME/" \
  --tree-ish HEAD \
  "$SOURCE_TARBALL" \
  && [ -s "$SOURCE_TARBALL" ]; then
  if tar -xzf "$SOURCE_TARBALL" -C "$SOURCE_STAGING"; then
    SOURCE_READY=1
  fi
fi

if [ "$SOURCE_READY" -eq 0 ] || ! source_has_submodules; then
  warn "git-archive-all.sh output is incomplete; falling back to git archive and submodule archives"
  rm -rf "$SOURCE_STAGING"
  mkdir -p "$SOURCE_STAGING" || fail "cannot create source staging directory"
  populate_source_staging "$SOURCE_STAGING" "$SOURCE_NAME" \
    || fail "git archive could not create the source archive"
  source_has_submodules \
    || fail "source archive is missing a submodule (run git submodule update --init --recursive)"
fi

cp "$MANIFEST" "$SOURCE_STAGING/$SOURCE_NAME/compatibility-manifest.json" \
  || fail "cannot add the manifest to the source archive"
tar -czf "$SOURCE_ARCHIVE" -C "$SOURCE_STAGING" "$SOURCE_NAME" \
  || fail "cannot create the final source archive"

# ---------------------------------------------------------------------------
step "9. Checksums"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$DMG")" "$(basename "$SOURCE_ARCHIVE")" > "SHA256SUMS.txt"
) || fail "cannot write SHA256SUMS.txt"

cat "$OUTPUT_DIR/SHA256SUMS.txt"

printf '\nRelease artifacts in %s:\n' "$OUTPUT_DIR"
printf '  %s\n' "$DMG"
printf '  %s\n' "$SOURCE_ARCHIVE"
printf '  %s\n' "$OUTPUT_DIR/SHA256SUMS.txt"
printf '  %s\n' "$MANIFEST"
