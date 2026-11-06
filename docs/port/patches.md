# Local Patches

Every divergence from `arkadeleon/ragnarok-offline` is listed here. See
[UPSTREAM_SYNC.md](UPSTREAM_SYNC.md) for the sync procedure.

| File or area | Reason | Upstreamable? |
| --- | --- | --- |
| App display name and bundle identifier (xcconfig) | Fork identity and a separate sandbox container: `tech.thecapy.ro-mac-client` | No, fork specific |
| `NOTICE`, `.github/` CI, issue templates, `scripts/provision-assets.sh` | Fork-only licensing, build, and asset provisioning files | No, fork specific |
| `RagnarokOffline/Launcher/` (`LauncherView`, `MainWindowView`, `LauncherModel`), `macOSApp.swift` (`MainWindowView` replaces `ContentView` as main window content, View > Developer Tools command, `requestReview()` removed), `GameClientView.testConnection` made `static`, `AboutView` repository URL, `Localizable.xcstrings` "Welcome to RagOff" | macOS opens on a launcher (server, asset check, Play); upstream tool sidebar kept behind `app.showsDeveloperTools`; no App Store review prompt; fork branding | No, fork specific |
| `Generated/packets.swift` `RANKLIST` | Generator emits `char names[10][NAME_LENGTH]` as one 10-byte string; hand-fixed to ten 24-byte names (golden test caught it) | Yes: fix 2-D char arrays in `RagnarokOfflineGenerator` `PacketStructConverter` |
| `PlaySession.connect(to:)` | Removed the keepalive start right after `CZ_ENTER`: rAthena rejects the connect packet when `CZ_REQUEST_TIME` shares its TCP read (found by `Tools/ROProbe`) | Yes |
| `README.md` | Rewritten for the fork (goal, status, run steps); upstream README content is in upstream | No |
