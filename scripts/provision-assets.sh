#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/provision-assets.sh <kro-client-dir> [--dest <dir>] [--with-rdata] [--dry-run]

Copies data.grf, optional rdata.grf, and BGM/ from a user-supplied kRO client
directory into the app sandbox Documents directory. The source is never
modified.

Arguments:
  <kro-client-dir>  Directory holding data.grf and BGM/.

Options:
  --dest <dir>      Destination directory. Overrides RO_ASSET_DEST.
  --with-rdata      Also copy rdata.grf.
  --dry-run         Print actions without copying.
  -h, --help        Show this help.

Environment:
  RO_ASSET_DEST     Destination when --dest is not given.
                    Default:
                    ~/Library/Containers/tech.thecapy.ro-mac-client/Data/Documents

Exit codes: 0 ok, 1 usage, 2 validation failure, 3 copy or verify failure.
EOF
}

usage_error() {
  echo "Error: $1" >&2
  echo >&2
  usage >&2
  exit 1
}

validation_error() {
  echo "Validation failed: $1" >&2
  exit 2
}

copy_error() {
  echo "Copy failed: $1" >&2
  exit 3
}

file_size() {
  stat -f%z "$1"
}

file_mtime() {
  stat -f%m "$1"
}

grf_version() {
  local bytes b0 b1 b2 b3
  bytes=$(od -An -tx1 -j 42 -N 4 "$1") || return 1
  set -- $bytes
  if [ "$#" -ne 4 ]; then
    return 1
  fi
  b0=$1
  b1=$2
  b2=$3
  b3=$4
  echo $((16#$b0 + 16#$b1 * 256 + 16#$b2 * 65536 + 16#$b3 * 16777216))
}

count_mp3() {
  local count
  count=$(find "$1" -type f -name '*.mp3' -print | wc -l) || return 1
  echo "$count" | tr -d ' '
}

copy_file() {
  local source=$1
  local target=$2
  local source_size source_mtime target_size target_mtime

  if [ ! -f "$source" ]; then
    copy_error "source file not found: $source"
  fi

  source_size=$(file_size "$source") || copy_error "cannot stat $source"
  source_mtime=$(file_mtime "$source") || copy_error "cannot stat $source"

  if [ -f "$target" ]; then
    target_size=$(file_size "$target") || copy_error "cannot stat $target"
    target_mtime=$(file_mtime "$target") || copy_error "cannot stat $target"
    if [ "$source_size" -eq "$target_size" ] && [ "$source_mtime" -eq "$target_mtime" ]; then
      echo "Skip $target (size and mtime match)"
      return 0
    fi
  fi

  echo "Copy $source -> $target"
  if [ "$dry_run" -eq 1 ]; then
    return 0
  fi

  if command -v rsync >/dev/null 2>&1; then
    if ! rsync -a "$source" "$target"; then
      copy_error "rsync failed for $target"
    fi
  else
    if ! cp -p "$source" "$target"; then
      copy_error "cp failed for $target"
    fi
  fi
}

copy_bgm() {
  local source=$1
  local target=$2

  echo "Copy $source/ -> $target/"
  if [ "$dry_run" -eq 1 ]; then
    return 0
  fi

  if ! mkdir -p "$target"; then
    copy_error "cannot create $target"
  fi

  if command -v rsync >/dev/null 2>&1; then
    if ! rsync -a "$source/" "$target/"; then
      copy_error "rsync failed for $target"
    fi
  else
    if ! cp -R "$source/." "$target/"; then
      copy_error "cp -R failed for $target"
    fi
  fi
}

verify_file() {
  local source=$1
  local target=$2
  local source_size target_size

  source_size=$(file_size "$source") || copy_error "cannot stat $source"
  if [ ! -f "$target" ]; then
    copy_error "destination file missing: $target"
  fi
  target_size=$(file_size "$target") || copy_error "cannot stat $target"

  if [ "$source_size" -ne "$target_size" ]; then
    copy_error "size mismatch for $target: source $source_size, destination $target_size"
  fi
  echo "Verified $target ($target_size bytes)"
}

source_dir=""
dest=""
with_rdata=0
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        usage_error "--dest requires a directory"
      fi
      dest=$2
      shift 2
      ;;
    --with-rdata)
      with_rdata=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage_error "unknown option: $1"
      ;;
    *)
      if [ -n "$source_dir" ]; then
        usage_error "only one <kro-client-dir> is allowed"
      fi
      source_dir=$1
      shift
      ;;
  esac
done

if [ -z "$source_dir" ]; then
  usage_error "missing <kro-client-dir>"
fi

if [ -z "$dest" ]; then
  if [ -n "${RO_ASSET_DEST:-}" ]; then
    dest=$RO_ASSET_DEST
  else
    dest="$HOME/Library/Containers/tech.thecapy.ro-mac-client/Data/Documents"
  fi
fi

if [ ! -d "$source_dir" ]; then
  validation_error "source directory not found: $source_dir"
fi

data_grf="$source_dir/data.grf"
if [ ! -f "$data_grf" ]; then
  validation_error "data.grf not found in $source_dir"
fi

data_size=$(file_size "$data_grf") || validation_error "cannot read $data_grf"
if [ "$data_size" -le 104857600 ]; then
  validation_error "data.grf is $data_size bytes, expected more than 104857600"
fi

header=$(dd if="$data_grf" bs=1 count=15 2>/dev/null) || validation_error "cannot read header from $data_grf"
if [ "$header" != "Master of Magic" ]; then
  validation_error "data.grf does not start with the GRF magic 'Master of Magic'"
fi

version=$(grf_version "$data_grf") || validation_error "cannot read GRF version from $data_grf"
echo "GRF version: 0x$(printf '%x' "$version") ($version)"
if [ "$version" -eq 768 ]; then
  echo "GRF v3 is not supported, use the 2021-04-06 kRO archive" >&2
  exit 2
fi
if [ "$version" -ne 512 ]; then
  validation_error "unsupported GRF version 0x$(printf '%x' "$version"), expected 0x200"
fi

bgm_dir="$source_dir/BGM"
if [ ! -d "$bgm_dir" ]; then
  validation_error "BGM directory not found: $bgm_dir"
fi
first_mp3=$(find "$bgm_dir" -type f -name '*.mp3' -print -quit) || validation_error "cannot read $bgm_dir"
if [ -z "$first_mp3" ]; then
  validation_error "BGM directory has no .mp3 files: $bgm_dir"
fi

rdata_grf=""
if [ "$with_rdata" -eq 1 ]; then
  rdata_grf="$source_dir/rdata.grf"
  if [ ! -f "$rdata_grf" ]; then
    validation_error "rdata.grf not found in $source_dir (required with --with-rdata)"
  fi
fi

if [ ! -d "$dest" ]; then
  echo "Note: launch the app once so its sandbox container exists."
  echo "Creating destination directory: $dest"
  if [ "$dry_run" -eq 0 ]; then
    if ! mkdir -p "$dest"; then
      copy_error "cannot create $dest"
    fi
  fi
fi

copy_file "$data_grf" "$dest/data.grf"
if [ -n "$rdata_grf" ]; then
  copy_file "$rdata_grf" "$dest/rdata.grf"
fi
copy_bgm "$bgm_dir" "$dest/BGM"

source_mp3_count=$(count_mp3 "$bgm_dir") || copy_error "cannot count BGM files in $bgm_dir"

if [ "$dry_run" -eq 0 ]; then
  verify_file "$data_grf" "$dest/data.grf"
  if [ -n "$rdata_grf" ]; then
    verify_file "$rdata_grf" "$dest/rdata.grf"
  fi
  if [ ! -d "$dest/BGM" ]; then
    copy_error "destination directory missing: $dest/BGM"
  fi
  dest_mp3_count=$(count_mp3 "$dest/BGM") || copy_error "cannot count BGM files in $dest/BGM"
  if [ "$source_mp3_count" -ne "$dest_mp3_count" ]; then
    copy_error "BGM file count mismatch: source $source_mp3_count, destination $dest_mp3_count"
  fi
fi

echo
echo "Summary"
echo "  Source:      $source_dir"
echo "  Destination: $dest"
echo "  data.grf:    $(file_size "$data_grf") bytes"
if [ -n "$rdata_grf" ]; then
  echo "  rdata.grf:   $(file_size "$rdata_grf") bytes"
fi
echo "  BGM:         $source_mp3_count mp3 file(s)"
if [ "$dry_run" -eq 1 ]; then
  echo "  Mode:        dry run, nothing was copied"
fi
echo "Done."
