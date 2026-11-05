# Research Notes

Checked 2026-11-05. Re-check versions and licenses before release.

## Prior art

| Project | Stack | License | Status | Relevance |
| --- | --- | --- | --- | --- |
| [arkadeleon/ragnarok-offline](https://github.com/arkadeleon/ragnarok-offline) | Swift 6, Metal, SwiftUI | GPL-3.0 | 2,028 commits, pushed 2026-11-05 | Primary base |
| [MrAntares/roBrowserLegacy](https://github.com/MrAntares/roBrowserLegacy) | JavaScript, WebGL | GPL-3.0 | 4,775 commits, pushed 2026-11-05 | Protocol and format reference |
| [vE5li/korangar](https://github.com/vE5li/korangar) | Rust, wgpu 29, winit 0.30 | MIT | 820 commits, early | Second reference, permissive license |
| [Sziadan/open-midgard](https://github.com/Sziadan/open-midgard) | C++17, Qt 6, Vulkan/MoltenVK | GPL-3.0 | 1,318 commits | Pre-Renewal reference |
| [rathena/rathena](https://github.com/rathena/rathena) | C++ server | GPL-3.0 | Active | Protocol source of truth |
| [OpenKore/openkore](https://github.com/OpenKore/openkore) | Perl | GPL-2.0 | Active | Packet and bot reference |
| [Flux159/ragnarokoffline.app](https://github.com/Flux159/ragnarokoffline.app) | Electron, microVM, roBrowserLegacy | GPL-3.0 | Active | Packaging reference, not native |

## Why arkadeleon is the base

Source inspection on 2026-11-05:

- `Packages/RagnarokPackets/Sources/RagnarokPackets/PacketVersion.swift` sets
  `PACKET_VERSION = 20211103`, exactly the rAthena master default.
- `Packages/RagnarokGame/Sources/RagnarokGame/Engine/Rendering/MapSceneRenderer.swift`
  imports `Metal`, holds `MTLDevice`, and renders from a per-frame snapshot.
- `Packages/RagnarokNetwork` contains `NetworkClient`, `PacketFactory`,
  `LoginSession`, `CharSession`, `MapSession`, and handlers for NPC, item,
  player, chat, mail, and map objects.
- `RagnarokOffline/App/AppModel.swift` reads `settings.serverAddress` and
  `settings.serverPort`, and constructs `ServerManager`.
- Package set includes GRF, file formats, resources, render assets, rendering,
  shaders, sprites, effects, database, localization, and script support.
- Minimum platform is macOS 15. Packages declare macOS 13 and iOS 16, but the app
  target requires macOS 15.
- License is GPL-3.0. App Store distribution is incompatible with GPL-3.0.

Open questions for Phase 0:

1. Does external server mode work against a real rAthena process? The code path
   exists: `GameClientView` has address and port fields, defaults to
   `127.0.0.1:6900`, and builds `GameSession.Configuration`. It is untested.
2. Does the app send packets that match stock rAthena 20211103 end to end?
3. Is packet obfuscation implemented anywhere in `RagnarokNetwork`?
4. Which UI flows are stubs and which are complete?
5. Does the app handle a character with no pincode and no web auth token?

## rAthena facts

From `src/config/packets.hpp` on master:

- Default `PACKETVER` is `20211103`.
- `PACKETVER_RE` is enabled for 20200902 to 20211118.
- `PACKET_OBFUSCATION` is defined by default for `PACKETVER >= 20110817`.
- `WEB_SERVER_ENABLE` is on for `PACKETVER > 20200300`.
- `src/config/core.hpp` includes `src/config/packets.hpp` and then
  `src/custom/defines_post.hpp`.
- `src/custom/defines_post.hpp` is tracked and empty by default. Adding
  `#undef PACKET_OBFUSCATION` there disables it without editing the main packet
  configuration. The file is still a tracked upstream file.
- `conf/login_athena.conf` defaults to `new_account: no` and
  `use_MD5_passwords: no`.
- `conf/char_athena.conf` defaults to `pincode_enabled: yes` and
  `pincode_force: yes`.

Implication: stock rAthena and the upstream client agree on packet date but not
necessarily on obfuscation. This is the first protocol risk to test.

## roBrowserLegacy facts

From its getting started guide on 2026-11-05:

- Browsers tested: Chrome, Firefox, Safari, Edge, desktop and mobile.
- Supported game servers: rAthena and Hercules.
- Warning: disable `packet_obfuscation` on the server. It is not supported and
  causes invalid packets.
- Client date should match the server date. Older dates have more implemented
  features.
- Requires a WebSocket proxy because browsers cannot open raw TCP.
- Game files come from a kRO client or Nemo's Hercules assets.
- Recommended asset source: kRO full client from the rAthena board.

Use it to cross-check behavior when the Swift client and rAthena disagree.

## rAthena Docker facts

Checked 2026-11-05 against `rathena/rathena` `master`.

- Official stack: `tools/docker/docker-compose.yml`.
- Services: `db`, `builder`, `login`, `char`, `map`.
- Images: `mariadb:noble` and a locally built `rathena:local` from
  `tools/docker/Dockerfile` (`alpine:3.23`).
- The builder compiles with `BUILDER_CONFIGURE:
  "--enable-packetver=20211103"` by default. That matches the client.
- `builder.sh` runs `./configure $BUILDER_CONFIGURE` only when `/rathena/make`
  is absent, then runs `make clean server`.
- Login, char, and map start as separate containers and wait only for the
  database. They can race the builder on a first start. Build first, then start
  them.
- Host ports: 6900 login, 6121 char, 5121 map, 3306 MariaDB. The compose does
  not start or publish the web server on 8888.
- MariaDB imports `../../sql-files` into `/docker-entrypoint-initdb.d` on the
  first start of the `rathenadb` volume only.
- Development credentials: database `ragnarok`, user `ragnarok`, password
  `ragnarok`, root password `ragnarok`.
- `tools/docker/asset/inter_conf.txt` points every server at `db`.
- `tools/docker/asset/char_conf.txt` sets `login_ip: login` and
  `char_ip: 127.0.0.1`.
- `tools/docker/asset/map_conf.txt` sets `char_ip: char` and
  `map_ip: 127.0.0.1`.
- The announced char and map addresses are loopback. A client on the same Mac
  works. A LAN client needs `char_ip` and `map_ip` changed to the Mac LAN IP.
- The rAthena README marks this stack as unsuitable for production and warns
  that host port 3306 must be free.

Pinned commit used by the plan: `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`
(master on 2026-10-06). Full setup is in [DOCKER.md](DOCKER.md).

## kRO client files

The macOS client needs a legal kRO data set. The rAthena server uses its own
database and map cache, so it does not need Gravity files.

Primary source, rAthena forum, maintained by Akkarin:

https://rathena.org/board/topic/106413-kro-full-client-2023-04-04-includes-bgm-rsu/

MEGA folder, full link including the decryption key:

https://mega.nz/folder/jUsDgRxQ#ttLmLjPY9p9cfU5_ShWVCw

The key is the fragment after `#`. MEGA cannot decrypt a folder from the bare
folder ID. Paste the full URL. The 2021 archive was downloaded and verified
locally on 2026-11-05.

The folder holds three archives:

- `kRO_FullClient_20210406.zip`, about 3.7 GB
- `kRO_FullClient_20220721.zip`, about 4.0 GB
- `kRO_FullClient_20230404.zip`, about 4.2 GB

Use the 2021-04-06 archive for `PACKETVER 20211103`. The forum notes that 2021
and older clients need the 2021 maps. The 2023 archive is the latest full
package, but its maps and GRF format are ahead of the target client date.

Downloaded locally on 2026-11-05:

- Path: `~/Downloads/kRO_FullClient_20210406.zip`
- Size: 3.4 GB on disk, 3.93 GB extracted, 555 files
- SHA-256: `5a99585533f260f985159751e9e13eb182629aafb36bd8e7ef6cbe230441ffaf`
- Full CRC test: pass

Contents verified: `client/DATA.INI`, `client/data.grf` (3.14 GB),
`client/rdata.grf` (289 MB), `client/System/` (35 files, including
`itemInfo.lub`), `client/BGM/`, and the 2021 client binaries. Both GRF files
report version `0x200`, which the upstream `RagnarokGRF` reader supports. The
archive has no loose `client/data/` directory and no `clientinfo.xml`.

This is enough for the upstream baseline: `data.grf` and `BGM` are present.
`rdata.grf` and `System/` are available for later format, localization, and
content work. The app does not need `DATA.INI`, `rdata.grf`, or `clientinfo.xml`
today.

Alternative sources:

- Official kRO installer: http://rofull.gnjoy.com/RAG_SETUP_220120.exe
- Nemo kRO downloads: http://nemo.herc.ws/downloads/#kro-mainsakray
- Community Google Drive mirror for the 2023 archive:
  https://drive.google.com/file/d/1ceW09_uIishuOTaneLhxVJjBax5Qz1OP/view
  (third-party mirror, verify before use)

Files to keep:

- `data.grf`
- `rdata.grf`
- `DATA.INI`
- `System/` Lua and LUB files
- `data/` loose files, including `clientinfo.xml`
- `BGM/`, optional, roughly 300 MB

The upstream app reads `data.grf`, optional loose files placed in its sandbox
Documents directory, and `BGM`. Keep the other files for later format, script,
and localization work. The sandbox path for the upstream bundle is
`~/Library/Containers/com.github.arkadeleon.ragnarok-offline/Data/Documents`;
the path changes after the fork gets a new bundle identifier.

Do not use 2025 or newer `data.grf` without checking GRF format support. Newer
kRO archives use GRF v3 (`0x300`), which older clients and some readers cannot
open. Phase 0 uses the 2021 archive.

Do not commit or redistribute these files.

## Korangar facts

- Rust, `wgpu 29`, `winit 0.30`.
- `wgpu` uses Metal on macOS, so it is a native Metal path without hand-written
  Metal code.
- MIT license, modular `ragnarok-*` crates for packets, formats, and containers.
- README says "very early in development and anything but feature-complete."
- 371 stars and 820 commits. Smaller than roBrowserLegacy, more permissive.

Fallback if the Swift base fails.

## OpenMidgard facts

- C++17, Qt 6, QML.
- Vulkan on Linux and macOS through MoltenVK. Windows uses Direct3D 11 and 12.
- Default packet target is `packet_ver 23`, `2008-09-10aSakexe`.
- Pre-Renewal 2008 experience only.
- macOS build path exists but is less exercised than Windows.

Not a fit for a Metal-first 20211103 client. Useful as a reference for classic
gameplay behavior.

## Effort calibration

- roBrowserLegacy: started as roBrowser in 2013, 4,775 commits, still incomplete.
  Web stack, not a native client.
- Korangar: 820 commits since 2021, still early.
- OpenMidgard: 1,318 commits, pre-Renewal only, still incomplete.
- arkadeleon: 2,028 commits, native Apple client with Metal and network stack.

Conclusion: from scratch is a multi-year project. Forking the Swift base is a
months project. The estimate in `PLAN.md` assumes the base works and the target
server stays on 20211103.

## Sources

- rAthena `src/config/packets.hpp`, `src/config/core.hpp`,
  `src/custom/defines_post.hpp`
- rAthena `src/map/packets_struct.hpp`
- rAthena `conf/login_athena.conf`, `conf/char_athena.conf`,
  `conf/map_athena.conf`, `conf/groups.yml`
- rAthena `tools/docker/docker-compose.yml`, `Dockerfile`, `builder.sh`,
  `README.md`, and `asset/*.txt`
- rAthena `sql-files/main.sql`, `sql-files/logs.sql`
- arkadeleon `PacketVersion.swift`, `AppModel.swift`, `GameSession.swift`,
  `GameClientView.swift`, `SettingsModel.swift`, `MapSceneRenderer.swift`
- arkadeleon `RagnarokNetwork` package sources
- roBrowserLegacy `docs/README.md`
- rAthena forum, kRO full client topic and MEGA folder
- Korangar `Cargo.toml` and README
- OpenMidgard README
- GitHub API metadata for commit counts, licenses, and push dates
