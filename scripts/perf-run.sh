#!/usr/bin/env bash
# Measure frame rate, memory and cold start of the game client without a person clicking (P5-04..P5-06).
#
# It builds the app with the automation hook, launches it with RO_AUTOLOGIN_* so it skips the launcher, logs in,
# picks a character and enters the map, waits for the in-app frame statistics (RO_PERF_LOG), samples the process
# RSS and footprint from outside, quits the app and merges everything into docs/port/perf/<date>-<map>.json.
#
# Build choice: a Release build (optimized, what the player runs) with the RO_AUTOMATION compilation condition
# passed on the xcodebuild command line. The hook is not in the project settings, so a normal Release or
# archive build does not contain it. --debug builds the Debug configuration instead, which has the hook built in
# but runs unoptimized code and is not representative for fps, memory or start-up.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/perf-run.sh --map <name> [options]

Required:
  --map <name>        Map name used for the output file name and the report (for example prontera).
                      The map is reached through the character: pick one whose last_map is this map,
                      or warp with --cmd.

Options:
  --char <name|slot>  Character name or slot (RO_AUTOLOGIN_CHAR). Default: slot 0.
  --run <label>       Run label stored in the result, for example cold or warm. Default: run1.
  --user <name>       Account (default perf1).
  --pass <password>   Password (default perf1). Never printed or logged.
  --server <host:port>  Login server (default: the address saved in the app settings, 127.0.0.1:6900).
  --cmd "<a;b>"       Chat lines sent after the map loads, separated by ';' (for example "@warp geffen").
                      Frames are measured only after the last command and the map reload it causes.
  --loop "<a;b>"      Chat lines sent over and over after the commands, one every 250 ms, to keep effects on
                      screen (for example "@effect 89;@effect 92;@effect 113").
  --seconds <n>       Measured window in seconds (default 30).
  --warmup <n>        Seconds dropped before the window (default 5).
  --fps <n>           Ask the view for n frames per second (RO_PERF_FPS). Default: not set, so the
                      MTKView default of 60 applies.
  --windowed          Do not switch the game window to full screen.
  --debug             Build and run the Debug configuration.
  --no-build          Reuse the app already built in the derived data folder.
  --app <path>        Run this .app instead of building.
  --timeout <n>       Give up after n seconds (default 300).
  --out-dir <dir>     Result folder (default docs/port/perf).
  --purge             Run `sudo -n purge` first to drop the OS file cache (needs passwordless sudo).
  -h, --help          This text.

Result: <out-dir>/<date>-<map>.json, one entry per run appended to "runs".
Exit codes: 0 ok, 1 usage, 2 build or launch failure, 3 timeout or app failure.
EOF
}

fail() {
  echo "Error: $1" >&2
  exit "${2:-2}"
}

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

map=""
char=""
run_label="run1"
user="perf1"
password="perf1"
server=""
cmd=""
loop=""
seconds=30
warmup=5
fps=""
fullscreen=1
configuration="Release"
build=1
app=""
timeout=300
out_dir="$repo/docs/port/perf"
purge=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map) map=${2:?--map needs a value}; shift 2 ;;
    --char) char=${2:?}; shift 2 ;;
    --run) run_label=${2:?}; shift 2 ;;
    --user) user=${2:?}; shift 2 ;;
    --pass) password=${2:?}; shift 2 ;;
    --server) server=${2:?}; shift 2 ;;
    --cmd) cmd=${2:?}; shift 2 ;;
    --loop) loop=${2:?}; shift 2 ;;
    --seconds) seconds=${2:?}; shift 2 ;;
    --warmup) warmup=${2:?}; shift 2 ;;
    --fps) fps=${2:?}; shift 2 ;;
    --windowed) fullscreen=0; shift ;;
    --debug) configuration="Debug"; shift ;;
    --no-build) build=0; shift ;;
    --app) app=${2:?}; build=0; shift 2 ;;
    --timeout) timeout=${2:?}; shift 2 ;;
    --out-dir) out_dir=${2:?}; shift 2 ;;
    --purge) purge=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$map" ] || { usage >&2; exit 1; }

derived_data="${RO_PERF_DERIVED_DATA:-$repo/build/perf-$configuration}"

# --- Build ---------------------------------------------------------------------------------------------------

if [ -z "$app" ]; then
  if [ "$build" -eq 1 ]; then
    echo "Building $configuration into $derived_data"
    extra=()
    if [ "$configuration" = "Release" ]; then
      extra=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RO_AUTOMATION')
    fi
    (cd "$repo" && xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline \
      -configuration "$configuration" -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$derived_data" \
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
      "${extra[@]+"${extra[@]}"}" build) > "$derived_data.build.log" 2>&1 \
      || { tail -n 30 "$derived_data.build.log" >&2; fail "build failed, see $derived_data.build.log"; }
  fi
  app=$(find "$derived_data/Build/Products/$configuration" -maxdepth 1 -name '*.app' ! -name '*Thumbnail*' | head -n 1)
fi
[ -d "$app" ] || fail "app not found (run without --no-build): $app"

plist="$app/Contents/Info.plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
executable="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
[ -x "$executable" ] || fail "no executable at $executable"

# The app is sandboxed: client files come from, and the summary is written to, its container.
container="$HOME/Library/Containers/$bundle_id/Data"
[ -f "$container/Documents/data.grf" ] || fail "no data.grf in $container/Documents; run scripts/provision-assets.sh first"
mkdir -p "$container/tmp"

nc -z 127.0.0.1 6900 2>/dev/null || fail "login server 127.0.0.1:6900 is not reachable (start the ro-backend Docker stack)"

if [ "$purge" -eq 1 ]; then
  sudo -n purge || echo "Warning: purge failed, the OS file cache stays as it is" >&2
fi

# --- Launch --------------------------------------------------------------------------------------------------

run_id="$$-$(date +%s)"
perf_json="$container/tmp/perf-$run_id.json"
app_log="$derived_data.app-$run_id.log"
mkdir -p "$(dirname "$app_log")"
rm -f "$perf_json"

env_args=(
  "RO_AUTOLOGIN_USER=$user"
  "RO_AUTOLOGIN_PASS=$password"
  "RO_PERF_LOG=$perf_json"
  "RO_PERF_SECONDS=$seconds"
  "RO_PERF_WARMUP=$warmup"
  "RO_PERF_LABEL=$map $run_label"
  "RO_PERF_EXIT=1"
)
[ -n "$char" ] && env_args+=("RO_AUTOLOGIN_CHAR=$char")
[ -n "$server" ] && env_args+=("RO_AUTOLOGIN_SERVER=$server")
[ "$fullscreen" -eq 1 ] && env_args+=("RO_AUTOLOGIN_FULLSCREEN=1")
[ -n "$fps" ] && env_args+=("RO_PERF_FPS=$fps")
if [ -n "$cmd" ]; then
  env_args+=("RO_AUTOLOGIN_CMD=$cmd")
fi
[ -n "$loop" ] && env_args+=("RO_AUTOLOGIN_LOOP=$loop")
if [ -n "$cmd" ] || [ -n "$loop" ]; then
  env_args+=("RO_PERF_AFTER=commandsDone")
fi

load_at_launch=$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')
echo "Launching $(basename "$app") ($configuration) for $map, run $run_label"
env "${env_args[@]}" "$executable" > "$app_log" 2>&1 &
pid=$!
caffeinate -d -i -w "$pid" &
caffeinate_pid=$!

cleanup() {
  kill "$caffeinate_pid" 2>/dev/null || true
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- Sample from outside while the app runs ------------------------------------------------------------------

samples=$(mktemp -t perf-samples)
launched=$SECONDS
tick=0
while kill -0 "$pid" 2>/dev/null; do
  [ -s "$perf_json" ] && break
  elapsed=$((SECONDS - launched))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timed out after ${timeout}s without a summary" >&2
    echo "--- app output ---" >&2
    tail -n 20 "$app_log" >&2 || true
    echo "--- app log (RagnarokGame, last 3 min) ---" >&2
    log show --last 3m --info --predicate 'subsystem == "RagnarokGame"' 2>/dev/null | tail -n 20 >&2 || true
    fail "no result" 3
  fi
  rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)
  footprint_bytes=""
  if [ $((tick % 5)) -eq 0 ]; then
    footprint_bytes=$(footprint -f bytes --noCategories -p "$pid" 2>/dev/null | awk '/phys_footprint:/ {print $2; exit}' || true)
  fi
  echo "$elapsed ${rss_kb:-0} ${footprint_bytes:-0}" >> "$samples"
  tick=$((tick + 1))
  sleep 1
done

if [ ! -s "$perf_json" ]; then
  echo "--- app output ---" >&2
  tail -n 20 "$app_log" >&2 || true
  fail "the app exited without writing $perf_json" 3
fi
wall=$((SECONDS - launched))

# RO_PERF_EXIT=1 makes the app terminate itself; give it a few seconds, then stop it.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
cleanup
trap - EXIT
wait "$pid" 2>/dev/null || true

# --- Merge ---------------------------------------------------------------------------------------------------

mkdir -p "$out_dir"
date_stamp=$(date +%F)
out_file="$out_dir/$date_stamp-$map.json"
git_rev=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)

python3 -I - "$perf_json" "$samples" "$out_file" "$map" "$run_label" "$configuration" "$git_rev" "$wall" "${char:-slot 0}" "${fps:-default}" "$fullscreen" "$cmd" "$loop" "$load_at_launch" <<'PY'
import json, os, sys

perf_path, samples_path, out_path, map_name, run_label, configuration, git_rev, wall, char, fps, fullscreen, cmd, loop, load_at_launch = sys.argv[1:]

with open(perf_path) as f:
    app = json.load(f)

rss_mb, footprint_mb, series = [], [], []
with open(samples_path) as f:
    for line in f:
        t, rss_kb, fp = line.split()
        rss = int(rss_kb) / 1024
        fp_mb = int(fp) / 1048576 if int(fp) else None
        if int(rss_kb):
            rss_mb.append(rss)
            series.append([int(t), round(rss, 1)])
        if fp_mb is not None:
            footprint_mb.append(fp_mb)

m = app.get("milestonesSinceProcessStart", {})
def span(a, b):
    return round(m[b] - m[a], 2) if a in m and b in m else None

derived = {
    "processStartToLauncherShownS": m.get("launcherShown"),
    "processStartToMapFirstFrameS": m.get("mapFirstFrame"),
    "autologinToMapFirstFrameS": span("autologinStarted", "mapFirstFrame"),
    "loginToCharacterSelectS": span("loginSent", "characterSelectShown"),
    "characterSelectToMapLoadedS": span("characterSelectShown", "mapLoaded"),
    "mapLoadedToFirstFrameS": span("mapLoaded", "mapFirstFrame"),
}
mem = app.get("memory", {})
external = {
    "rssPeakMB": round(max(rss_mb), 1) if rss_mb else None,
    "rssLastMB": round(rss_mb[-1], 1) if rss_mb else None,
    "footprintPeakMB": round(max(footprint_mb), 1) if footprint_mb else None,
    "samples": len(series),
    "rssSeriesMB": series,
}

run = {
    "map": map_name,
    "run": run_label,
    "build": configuration,
    "gitRev": git_rev,
    "character": char,
    "requestedFps": fps,
    "fullscreen": fullscreen == "1",
    "commands": cmd,
    "loop": loop,
    "hostLoadAverage1mAtLaunch": float(load_at_launch),
    "wallSeconds": int(wall),
    "derived": derived,
    "external": external,
    "app": app,
}

doc = {"map": map_name, "runs": []}
if os.path.exists(out_path):
    with open(out_path) as f:
        doc = json.load(f)
doc["runs"].append(run)
with open(out_path, "w") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")

fm = app.get("frameMs", {})
fps_avg = app.get("fps", {}).get("average")
print(f"{map_name} {run_label}: start->map {derived['processStartToMapFirstFrameS']} s, "
      f"avg {fm.get('avg')} ms / {fps_avg} fps, p95 {fm.get('p95')} ms, "
      f"RSS peak {external['rssPeakMB']} MB, footprint {mem.get('physFootprintMB')} MB, "
      f"display {app.get('displayMaxHz')} Hz, drawable {app.get('drawable')}")
print(f"Wrote {out_path}")
PY

rm -f "$perf_json" "$samples"
