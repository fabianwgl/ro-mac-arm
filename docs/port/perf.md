# Performance measurements

Covers plan tasks P5-04 (120 fps), P5-05 (RSS under 4 GB) and P5-06 (cold start under 10 s).
The targets in [PLAN.md](PLAN.md) were set for an M1 on a 120 Hz ProMotion display. These runs are on
an **Apple M4** (10 GPU cores, 16 GB) driving a **2560x1440 Dell S2725DC at 144 Hz**, so they show what the
client does on this Mac, not on an M1. Nothing here was measured on M1 or on a ProMotion panel.

Measured 2026-11-08, git `d4f62f19` plus the automation change, macOS 27.0.1, Release build,
rAthena in the `ro-backend` Docker stack, full 3.1 GB kRO `data.grf`, game window in full screen.

## Result

| Target | Result on this Mac |
| --- | --- |
| P5-04 120 fps | **Pass since the refresh rate fix.** The map view now follows the screen's `maximumFramesPerSecond`: 143.9 fps average, p95 7.08 ms in Prontera at 2560x1440 on the 144 Hz display with no override (run `native-refresh`). Before the fix it ran at 48 fps (see finding 1). |
| P5-05 RSS under 4 GB | **Pass.** Peak RSS 418 to 557 MB, peak physical footprint 449 to 594 MB. |
| P5-06 cold start under 10 s | **Pass.** Process start to first map frame 1.1 to 2.8 s, including login and character select. |

## Table

Run labels: `cold` is the first launch in the series, `warm` the second. `fps120` and `fps144` ask the view for that
rate with `RO_PERF_FPS`. `effects` repeats `@effect` GM commands (89, 92, 113, 83, 30, 77, 96, 25) four times a
second at the player in Prontera to keep several effects on screen.

Window: 30 s measured after a 5 s warm-up, drawable 2560x1440, display 144 Hz for every row.
"Start to map" is process start to the first drawn map frame (launcher skipped, auto login). "fps at p95" is the
frame rate of the 95th percentile frame time, which is the worst 5 percent of frames.

| Map | Run | Start to map (s) | Launcher shown (s) | fps avg / at p95 | Frame ms avg / p95 | CPU draw / GPU ms avg | RSS peak (MB) | Footprint peak (MB) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| prontera | cold | 2.8 | 1.5 | 48.0 / 47.0 | 20.84 / 21.27 | 1.48 / 1.66 | 440 | 568 | default pacing; max frame 32 ms |
| prontera | warm | 1.9 | 0.5 | 48.0 / 47.9 | 20.84 / 20.87 | 1.02 / 1.33 | 460 | 578 | default pacing |
| prontera | fps120 | 1.4 | 0.4 | 72.0 / 70.5 | 13.89 / 14.18 | 1.27 / 2.45 | 540 | 576 | 120 requested, 72 delivered (finding 1) |
| prontera | fps144 | 1.2 | 0.4 | 143.9 / 141.2 | 6.95 / 7.08 | 1.06 / 2.11 | 544 | 579 | display-limited; GPU p95 3.5 ms |
| prontera | effects | 1.9 | 0.5 | 47.9 / 46.8 | 20.87 / 21.38 | 2.01 / 2.15 | 421 | 594 | default pacing; p99 24 ms, max 34 ms |
| prontera | effects, fps144 | 1.2 | 0.4 | 143.6 / 138.2 | 6.96 / 7.24 | 0.98 / 2.60 | 557 | 594 | GPU p95 4.0 ms, p99 frame 9.2 ms |
| geffen | cold | 1.3 | 0.5 | 48.0 / 48.0 | 20.84 / 20.85 | 0.26 / 1.25 | 421 | 450 | host load 15.9 |
| geffen | warm | 1.2 | 0.4 | 48.0 / 48.0 | 20.84 / 20.85 | 0.25 / 1.25 | 423 | 452 | host load 11.5 |
| geffen | fps120 | 1.3 | 0.5 | 72.0 / 68.8 | 13.89 / 14.53 | 1.11 / 2.15 | 418 | 449 | 120 requested, 72 delivered |
| geffen | fps144 | 1.1 | 0.4 | 143.9 / 136.6 | 6.95 / 7.32 | 1.06 / 2.51 | 418 | 450 | display-limited; GPU p95 3.8 ms |
| prontera | native-refresh | 2.5 | | 143.9 / | 6.95 / 7.08 | | 552 | 586 | after the fix, no `--fps`; follows the 144 Hz display |

Start-up breakdown of the Prontera cold run (seconds since process start): launcher shown 1.49, login sent 1.72,
character select shown 1.84, map loading 1.89, map loaded 2.76, first frame 2.82. The warm run is the same
sequence shifted by about 1 s (launcher shown 0.54, first frame 1.85). The map load itself (character select to
loaded) takes 0.5 to 1.1 s in every run.

Raw data, including milestones, GPU and CPU percentiles, RSS series and host load: `docs/port/perf/2026-11-08-prontera.json`
and `docs/port/perf/2026-11-08-geffen.json`.

## Findings

1. **The client never asks for more than the `MTKView` default of 60 fps.** `MapView.swift` leaves
   `preferredFramesPerSecond` at 60. On the 144 Hz display the display link only fires at integer divisors of the
   refresh rate, so 60 becomes 48 fps (144 / 3). A request of 120 gives 72 (144 / 2); a request of 144 gives 144.
   On a 120 Hz ProMotion panel the default would give 60 fps. To meet P5-04 the map view has to set
   `preferredFramesPerSecond` to the screen's `maximumFramesPerSecond`. Fixed on 2026-11-08: the macOS
   `MapViewController` sets it when the view appears and again on `NSWindow.didChangeScreenNotification`; the
   `native-refresh` run holds 143.9 fps. The renderer has the headroom: CPU draw under 2.1 ms, GPU 1.2 to 2.6 ms on
   average and 4.0 ms at worst p95, against an 8.3 ms budget.
2. **Memory is far under the target.** The loader reads `data.grf` instead of mapping it (no mapped reads in the code), so RSS stays at
   418 to 557 MB. Physical footprint (`footprint`, includes compressed and GPU-shared memory) peaks at 594 MB.
   This is a short single-map session; map changes and long sessions were not measured here.
3. **Cold start is dominated by process launch and the launcher, not by data loading.** The first launch of a
   fresh build spends about 1.5 s before the launcher shows; later launches 0.4 to 0.5 s. Login to character
   select is about 0.1 s and the map load 0.5 to 1.1 s.
4. **`NSApp.terminate` hung for more than 40 s in an unattended run** (the app delegate returns `terminateLater`
   and waits for `serverManager.stopAllServers()`). The cause was not investigated. The automation avoids it by
   removing the session marker and calling `exit(0)` once the summary is written, so there is no "did not quit
   cleanly" alert on the next launch. Worth a look as a possible real quit bug.

## Not measured, and why

- **M1 and ProMotion.** Only the M4 and a 144 Hz external display are available.
- **True cold disk cache.** The OS file cache was not dropped: `purge` needs root. `cold` means first launch of
  the series, not an uncached read of `data.grf`. Geffen's assets had not been read before its cold run, Prontera's
  had (trial runs). Host load from other builds was between 3.6 and 15.9 during the runs, which adds noise to the
  start-up numbers. Frame pacing is set by the display and is not affected.
- **Crowded scenes.** One player, a still camera, and effects from a GM loop (about four per second). No walking,
  no monsters, no other players, no hundred-sprite town. Treat the fps numbers as the floor for rendering cost
  being low, not as a stress result.
- **Windowed numbers.** Runs use full screen 2560x1440. A 900x707 window in a trial run paced the same (48 fps).
- **Xcode GPU capture, Metal System Trace, input latency** (P5-01 to P5-03, P5-07, P5-08).
- **Long sessions.** No memory growth check over an hour or across map changes.

## Method

### The automation hook

`scripts/perf-run.sh` builds the app, launches it with environment variables, and the app does the rest. The hook is
in `Packages/RagnarokGame/Sources/RagnarokGame/Engine/Diagnostics/`:

- `AutoLogin.swift` (`#if DEBUG || RO_AUTOMATION`, so absent from a normal Release build). The launcher opens the game
  window by itself and a task drives the same `GameSession` calls the screens use: `login`, `selectCharServer`,
  `selectCharacter`. It never logs the password; its description redacts it and a unit test checks that.
- `PerfProbe.swift` (always compiled, active only when `RO_PERF_LOG` is set; otherwise every call is one optional
  check). `MapView.swift` calls `beginFrame` and `endFrame` around each presented frame. It records the frame
  interval, the CPU time spent in `draw`, and the GPU time from the command buffer's `gpuStartTime` and `gpuEndTime`.

Environment variables:

| Variable | Meaning |
| --- | --- |
| `RO_AUTOLOGIN_USER`, `RO_AUTOLOGIN_PASS` | Account. Automation is off unless the user is set. |
| `RO_AUTOLOGIN_SERVER` | `host[:port]` of the login server. Default: the address saved in settings. |
| `RO_AUTOLOGIN_CHARSERVER` | Char server name or index if several are listed. Default: first. |
| `RO_AUTOLOGIN_CHAR` | Character name or slot. Default: slot 0. |
| `RO_AUTOLOGIN_CMD` | Chat lines sent once the map is loaded, separated by `;` (for example `@warp geffen`). |
| `RO_AUTOLOGIN_LOOP`, `RO_AUTOLOGIN_LOOP_MS` | Chat lines sent over and over, one per interval (default 250 ms). |
| `RO_AUTOLOGIN_FULLSCREEN` | `1` puts the game window in full screen after the map loads. |
| `RO_PERF_LOG` | Path of the JSON summary. Inside the sandbox container, because the app is sandboxed. |
| `RO_PERF_SECONDS`, `RO_PERF_WARMUP` | Measured window (default 30 s) and warm-up dropped before it (default 5 s). |
| `RO_PERF_AFTER` | Milestone to wait for before measuring. The script sets `commandsDone` with `--cmd` or `--loop`. |
| `RO_PERF_FPS` | Overrides `MTKView.preferredFramesPerSecond`. Not set: the default of 60. |
| `RO_PERF_EXIT` | `1` exits the app after the summary (clean-exit marker, then `exit(0)`). |
| `RO_PERF_LABEL` | Free text copied into the summary. |

The summary holds average, p50, p95, p99, min and max frame time, fps (average and at p95 and p99 frame time),
share of frames over 8.3, 16.7 and 33.3 ms, CPU draw and GPU time statistics, drawable size, the display's
maximum refresh rate, the memory at the first map frame and at the end, and milestone times in seconds since the
process started (read from the kernel's process start time). Milestones: `launcherShown`, `autologinStarted`,
`loginSent`, `characterSelectShown`, `playStage`, `mapLoading`, `mapLoaded`, `mapFirstFrame`, `commandsDone`.

### Build choice

The script builds **Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) RO_AUTOMATION'`** on the
`xcodebuild` command line, ad-hoc signed with the sandbox entitlements (`CODE_SIGN_IDENTITY=-`). Release is what the
player runs: optimized code, so fps, memory and start-up are representative. The condition is not in any project
setting, so a normal Release or archive build does not contain `AutoLogin`. `--debug` builds Debug instead (hook
built in, unoptimized, not representative). The sandboxed app finds its client files and writes its summary inside
`~/Library/Containers/tech.thecapy.ro-mac-client/Data`, so it has to be signed; `CODE_SIGNING_ALLOWED=NO` would run
it unsandboxed with no `data.grf`.

### Running it

```sh
scripts/perf-run.sh --map prontera --char PerfPront --run cold
scripts/perf-run.sh --map prontera --char PerfPront --run warm
scripts/perf-run.sh --map geffen   --char PerfGeff  --run cold --fps 144
scripts/perf-run.sh --map prontera --char PerfPront --run effects --loop "@effect 89;@effect 92;@effect 113"
```

The script checks the login port, runs the app from its executable (not through `open`, so the environment passes),
keeps the display awake with `caffeinate`, samples `ps` RSS every second and `footprint` every five seconds from
outside, waits for the summary, and appends one entry to `docs/port/perf/<date>-<map>.json` (`runs` array with the
app summary, derived start-up spans, the RSS series and host load). A Release build from scratch takes several minutes
(about 10 under load; the large generated `RagnarokConstants` module compiles on one core); later runs reuse the derived data
(`RO_PERF_DERIVED_DATA`, default `build/perf-Release`, or `--no-build`). It stops after `--timeout` seconds (default
300) and prints the app output and the `RagnarokGame` log.

### Test account and characters

Local rAthena, GM group 99 (see [DOCKER.md](DOCKER.md)). The characters are inserted directly so no UI is needed;
the map is picked by `last_map`, no `@warp` required.

```sh
docker compose exec db mariadb -uragnarok -pragnarok ragnarok -e "
INSERT INTO login (userid, user_pass, sex, email, group_id, pincode)
VALUES ('perf1', 'perf1', 'M', 'perf1@example.com', 99, '');
INSERT INTO \`char\` (char_id, account_id, char_num, name, class, base_level, job_level, zeny,
  str, agi, vit, \`int\`, dex, luk, max_hp, hp, max_sp, sp, hair, hair_color, body,
  last_map, last_x, last_y, save_map, save_x, save_y, sex)
VALUES
 (150020, <perf1 account_id>, 0, 'PerfPront', 0, 99, 1, 1000000, 9,9,9,9,9,9, 5000,5000,500,500, 2,0,2,
  'prontera', 156, 191, 'prontera', 156, 191, 'M'),
 (150021, <perf1 account_id>, 1, 'PerfGeff',  0, 99, 1, 1000000, 9,9,9,9,9,9, 5000,5000,500,500, 2,0,2,
  'geffen', 119, 59, 'geffen', 119, 59, 'M');"
```

Use a free `char_id` and the account id the first insert gave (`SELECT account_id FROM login WHERE userid='perf1'`).
