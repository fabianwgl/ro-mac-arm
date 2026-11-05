# Installing RO Mac Client

RO Mac Client is distributed outside the App Store as a signed and notarized
DMG. The source is GPL-3.0. See `LICENSE` and `NOTICE` in this DMG.

## Requirements

- Apple silicon Mac (arm64).
- macOS 15 or later.
- A legal copy of the 2021-04-06 kRO full client. You need its `data.grf` and
  `BGM` folder.
- An rAthena server built for `PACKETVER 20211103`, or the app's embedded local
  server.

Gravity client files are not included. Do not redistribute them.

## Install from the DMG

1. Open `RO-Mac-Client-<version>.dmg`.
2. Drag **RO Mac Client** to the **Applications** folder.
3. Eject the DMG and launch the app from Applications.

The DMG also contains `LICENSE`, `NOTICE`, `INSTALL.md`, and
`compatibility-manifest.json`. The manifest records the exact client and rAthena
versions used for the release.

## First launch

The app is signed with a Developer ID certificate and notarized by Apple. It
should launch without a Gatekeeper warning. The app is sandboxed and creates its
container on first launch.

If Gatekeeper blocks the app, first check the DMG against `SHA256SUMS.txt`. Then
open **System Settings > Privacy & Security**, find the blocked app, and choose
**Open Anyway**. Only do this when the checksum matches.

## Supply kRO client files

Use the **2021-04-06** kRO full client. It matches `PACKETVER 20211103` and has
the supported GRF version. Source links are in `docs/port/RESEARCH.md` in the
source archive.

Copy `data.grf` and the `BGM` folder into the app's local client files. Choose one
method:

- In the app, open **Local Client Files** and add `data.grf` and the `BGM`
  folder.
- From a terminal in the source checkout, run:

  ```sh
  scripts/provision-assets.sh /path/to/kRO_FullClient_20210406
  ```

The script validates the GRF header and version, copies `data.grf` and `BGM`,
and verifies the result. Launch the app once before running it so the sandbox
container exists.

Do not commit or share `data.grf`, `rdata.grf`, `BGM`, or extracted Gravity
files.

## Server address and port

The default login server address is `127.0.0.1` and the default port is `6900`.
Change them in the **Game Client** screen using **Server Address** and **Server
Port**.

The login server returns the character server address (`6121` by default) and
the map server address (`5121` by default). A client on another Mac needs those
announced addresses changed to the server's LAN IP.

## Server requirements

- rAthena built with `PACKETVER 20211103`.
- Packet obfuscation: for PACKETVER after 2018-03-07 rAthena uses zero
  obfuscation keys, so stock rAthena works (expected). If the connection fails
  with packet errors, disable `PACKET_OBFUSCATION` in
  `src/custom/defines_post.hpp` and rebuild the server.
- Pincode is supported.

Record the rAthena commit in bug reports. The current pin is
`d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`; this is the commit named in the
compatibility manifest.

## Troubleshooting

### The app will not open

- Check that macOS is 15 or later and the Mac is Apple silicon.
- Compare the DMG with `SHA256SUMS.txt`.
- In Terminal, run `spctl -a -vvv -t install /path/to/RO-Mac-Client-<version>.dmg`.
  A notarized DMG should be accepted.
- For a locally built, unnotarized DMG, Gatekeeper rejection is expected. Use
  `--skip-notarize` output only for local testing.

### Wrong GRF version

The app expects the GRF version from the 2021-04-06 kRO client. If
`provision-assets.sh` reports `unsupported GRF version` or the app cannot load
resources, you are probably using a different client archive. Use the
2021-04-06 archive.

### Connection refused

- Start the login, character, and map servers before starting the game.
- Check the address and port in the **Game Client** screen. The default is
  `127.0.0.1:6900`.
- Check that the login server is listening:

  ```sh
  lsof -nP -iTCP:6900 -sTCP:LISTEN
  ```

- Check the server's firewall and the announced character and map addresses.

### Packet errors or disconnects

Packet errors usually mean the server and client disagree about `PACKETVER` or
packet obfuscation.

- Build rAthena with `--enable-packetver=20211103`.
- If packet errors continue, add `#undef PACKET_OBFUSCATION` and
  `#undef PACKET_OBFUSCATION_WARN` to `src/custom/defines_post.hpp`, then rebuild.
- Read app logs in **Console.app**. Filter by the process **RO Mac Client** or
  the subsystem `RagnarokNetwork`.
- Read the login, character, and map server output in the terminal where they
  run, or in the server's log files.

## Uninstall

1. Quit the app.
2. Drag **RO Mac Client** from Applications to the Trash.
3. Remove the sandbox container and your local client files:

   ```sh
   rm -rf ~/Library/Containers/tech.thecapy.ro-mac-client
   ```
