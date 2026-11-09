# Local Patches

Changes the fork made inside upstream's own files, with the reason. See
[UPSTREAM_SYNC.md](UPSTREAM_SYNC.md) for the sync procedure.

This table is incomplete: 69 upstream files are modified and the rows below
cover the ones that change upstream's behavior. The full list is
`git diff --diff-filter=M --numstat upstream/master...HEAD`; bringing this
table up to it is TASKS.md P7-10. Files the fork added (295 of them) are not
listed: they do not conflict.

| File or area | Reason | Upstreamable? |
| --- | --- | --- |
| App display name and bundle identifier (xcconfig) | Fork identity and a separate sandbox container: `tech.thecapy.ro-mac-client` | No, fork specific |
| `NOTICE`, `.github/` CI, issue templates, `scripts/provision-assets.sh` | Fork-only licensing, build, and asset provisioning files | No, fork specific |
| `RagnarokOffline/Launcher/` (`LauncherView`, `MainWindowView`, `LauncherModel`), `macOSApp.swift` (`MainWindowView` replaces `ContentView` as main window content, View > Developer Tools command, `requestReview()` removed), `GameClientView.testConnection` made `static`, `AboutView` repository URL, `Localizable.xcstrings` "Welcome to RagOff" | macOS opens on a launcher (server, asset check, Play); upstream tool sidebar kept behind `app.showsDeveloperTools`; no App Store review prompt; fork branding | No, fork specific |
| `Generated/packets.swift` `RANKLIST` | Generator emits `char names[10][NAME_LENGTH]` as one 10-byte string; hand-fixed to ten 24-byte names (golden test caught it) | Yes: fix 2-D char arrays in `RagnarokOfflineGenerator` `PacketStructConverter` |
| `PlaySession.connect(to:)` | Removed the keepalive start right after `CZ_ENTER`: rAthena rejects the connect packet when `CZ_REQUEST_TIME` shares its TCP read (found by `Tools/ROProbe`) | Yes |
| `README.md` | Rewritten for the fork (goal, status, run steps); upstream README content is in upstream | No |
| `Packages/DataCompression` `Zlib+Deflate.swift` | `Zlib.deflate` (zlib `compress2`) for the guild emblem upload; upstream only inflates. Kept in its own file so `Zlib.swift` merges cleanly | Yes |
