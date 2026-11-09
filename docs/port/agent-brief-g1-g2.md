# Agent brief: gates G1 and G2

Prompt for a software engineer agent that continues the work after the
direction review of 2026-11-09. It covers TASKS.md P7-01, P7-02, P7-04 and
P7-05 and stops before the developer's playtest (gate G3). Written
2026-11-09; check the "Things I learned" section against the tree before
reusing it later.

Not in this brief, on purpose: the push (P7-07, waits for the public or
private decision), the worktree cleanup (P7-13, it deletes things), and the
upstream merge, CI and pull requests (P7-08 to P7-12).

Two points to settle before sending it:

- Input focus. The brief lets the agent send keystrokes and clicks when the
  app is frontmost. If the developer is using the Mac at the time, restrict
  it to the debug hook only.
- The embedded server. The brief treats it as the plan. If it is rejected,
  drop tasks 1 and 2 and point the smoke run at Docker.

## Prompt

```text
Continue the RO Mac Client work in /Users/fwgl/dev/ro-mac-client, branch
integrate-m2. You are picking up after a direction review; the plan was
rewritten on 2026-11-09 and nothing in it has been started.

## Read first
- docs/port/PLAN.md sections 2 and 4 to 7 (decisions, ownership split, v1.0,
  gates, order of work)
- docs/port/TASKS.md, Phase 7 (your tasks, with ids)
- docs/port/ARCHITECTURE.md section 10 (the two servers)
- Tools/ROProbe/README.md (headless probe and its scenarios)

## What this project is now
One person plays Ragnarok Online alone on this Mac, 1st and 2nd jobs only.
The fork of arkadeleon/ragnarok-offline stays thin: it owns the macOS shell,
the verification tools and bug fixes. Upstream owns the renderer, effects and
single-player game windows. Multiplayer code already in the tree is frozen.

Everything so far was verified headless against a Docker rAthena. No person
has seen the UI, and the server the player is meant to use, the rAthena
embedded in the app, has never been run in this fork. Your job is to close
that gap up to the point where a person can sit down and play.

## Tasks, in this order
1. P7-01, gate G1. Run the embedded server in the fork's build, create an
   account and a character, enter a map. Then run the probe against it and
   record the result. Fill the embedded row in docs/port/COMPATIBILITY.md.
2. P7-02. Launcher Play starts the embedded servers, waits until they accept
   connections, then opens the login. Server address and port move to an
   advanced section and must keep working for Docker.
3. P7-04, gate G2. Write scripts/gui-smoke.sh: launch the app, capture the
   game window, open each core window in turn and capture each.
4. P7-05. Look at every screenshot yourself and fix what is wrong in the
   fork's own area. One defect is already known: the status window and the
   window's close, minimize and zoom buttons overlap.

Stop after task 4. Gate G3 is a one-hour playtest by the developer.

If G1 fails for a reason that is not a small fix, stop there and report. Do
not start task 2: the plan falls back to Docker and the developer decides.

## Things I learned that the docs do not say
- Build with ad-hoc signing, or the app is unsandboxed and finds no client
  files:
  xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
  The kRO data is already in
  ~/Library/Containers/tech.thecapy.ro-mac-client/Data/Documents.
- The embedded server is started by ServerManager.startAllServers()
  (RagnarokOffline/Server/ServerManager.swift), today only from the sidebar
  behind View > Developer Tools. Its config is inline in that file:
  registration on, no pincode, group 0 has some GM commands but not all the
  ones the probe's core scenario uses. Renewal or Pre-Renewal is the
  server.mode setting. Stay on Renewal; that choice is the developer's.
- The Docker stack (containers ro-backend-db, -login, -char, -map) may be
  running and holds ports 6900, 6121 and 5121. The embedded server needs
  the same ports. Stop the three server containers first.
- Debug builds skip the launcher and log in when RO_AUTOLOGIN_USER,
  RO_AUTOLOGIN_PASS, RO_AUTOLOGIN_CHAR and RO_AUTOLOGIN_SERVER are set
  (Packages/RagnarokGame/Sources/RagnarokGame/Engine/Diagnostics/AutoLogin.swift).
  Launch the binary directly; scripts/perf-run.sh shows the pattern.
- Window capture works: the process is named RagnarokOffline, its windows
  are found with CGWindowListCopyWindowInfo(.optionAll) filtered by owner pid
  (they are not flagged on-screen while the app is in the background, so do
  not filter on that), and screencapture -x -o -l <window id> saves one.
  Screen Recording and Accessibility are granted to the terminal.
- Inventory, equipment, skills, status and options have key bindings
  (Core/Models/KeyBindings.swift). The other windows are menu buttons.

## Constraints
- Keystrokes and clicks sent through System Events go to whatever app is
  frontmost, and bringing the app forward takes focus on a Mac the developer
  may be using. Never send input without checking in the same call that
  RagnarokOffline is frontmost. If a route that needs no global input exists,
  such as extending the debug auto-login hook to open a window, prefer it.
- Do not push. origin is a public repository and whether it stays public is
  undecided.
- Never commit a screenshot. docs/port/gui-runs/ is gitignored for that.
- No new game features. No work on the frozen multiplayer systems. Nothing
  in upstream's area (effects, renderer, game windows) beyond a fix for a
  defect you can show in a screenshot.
- New code goes into new files; edits inside upstream's files stay small
  hooks. Add a row to docs/port/patches.md for each upstream file you change.
- Leave the agent worktrees and backup branches alone, and open no pull
  requests upstream.
- Commits are authored and committed as Fabian General <fabianwgl@gmail.com>.
  The repo's git config has a different address, so set GIT_AUTHOR_* and
  GIT_COMMITTER_* yourself. No Co-Authored-By or generated-by lines.

## Done means
- G1: the probe run against the embedded server is saved under
  docs/port/probe-runs/ and COMPATIBILITY.md says what passed and what the
  embedded command set did not allow.
- P7-02: from a cold start, one click on Play reaches the character list
  with Docker stopped. Shown by a screenshot you looked at, not by a unit
  test alone.
- G2: scripts/gui-smoke.sh runs unattended and produces one screenshot per
  core window; you have looked at each.
- Package tests still pass: swift test --package-path Packages/RagnarokGame
  (448 tests on 2026-11-09), RagnarokPackets, RagnarokNetwork.
- TASKS.md checkboxes, PLAN.md section 12 and KNOWN_GAPS.md match what is
  true. Mark a task done only with evidence.

## Report back
Short. Per task: passed, failed or not reached, and the evidence path. Then
the commits, a list of every defect the screenshots showed with fixed or not
fixed, and anything you could not verify. End with a section
"## Open Questions", each tagged [user] if only the developer can answer.
```
