# Local rAthena Test Server (Docker)

Phase 0 needs a real rAthena server. Use the official Docker development stack
from rAthena, not a custom image.

Source: https://github.com/rathena/rathena/tree/master/tools/docker

The stack is for local development only. It has fixed passwords, no TLS, and no
production hardening.

## Topology

```
macOS host
  ro-mac-client
    -> 127.0.0.1:6900  login server
    -> 127.0.0.1:6121  char server
    -> 127.0.0.1:5121  map server

Docker network
  login -> char -> map
  login, char, map -> db (MariaDB)
```

| Host port | Service | Purpose |
| --- | --- | --- |
| 6900 | login | Client login and server list |
| 6121 | char | Character list, creation, selection |
| 5121 | map | Map entry and gameplay |
| 3306 | db | Optional SQL access from the host |
| 8888 | web | Not started by the official compose |

The client needs only 6900, 6121, and 5121. Login, character selection, and map
entry do not use the web server. Keep 3306 bound to localhost, or do not publish
it at all outside development.

The default compose publishes every port on all host interfaces. For a same-Mac
test, bind them to loopback:

```yaml
ports:
    - "127.0.0.1:3306:3306"
    - "127.0.0.1:6900:6900"
    - "127.0.0.1:6121:6121"
    - "127.0.0.1:5121:5121"
```

Remove the `127.0.0.1:` prefix from 6900, 6121, and 5121 only when a client on
another machine must connect.

## Prerequisites

- Docker Desktop for Apple Silicon with Compose v2.
- Port 3306 free on the host. The compose publishes MariaDB there.
- About 12 GB free. The stack needs roughly 4 GB for images, build output, and
  the database. The kRO archive is 3.4 GB and extracts to about 3.9 GB.
- rAthena source tree at a pinned commit.

Check the port before starting:

```sh
lsof -nP -iTCP:3306 -sTCP:LISTEN
```

An empty result means the port is free.

## Pin rAthena

Pin a commit. `master` changes its default `PACKETVER` over time.

```sh
export RATHENA_COMMIT=d4b8e7b8f16061cc2496d377ac8f777ce72a4f39
git clone https://github.com/rathena/rathena.git ~/dev/rathena
git -C ~/dev/rathena checkout "$RATHENA_COMMIT"
```

This commit is rAthena `master` as of 2026-10-06. Its default `PACKETVER` is
20211103, which matches the client. Record the commit in the compatibility
manifest and in every bug report. The source and `sql-files` are pinned by
commit. The base images (`mariadb:noble`, `alpine:3.23`) are tags, not digests;
pin digests if strict reproducibility matters.

## Configure the stack

All commands run from `~/dev/rathena/tools/docker`.

### 0. Project and container names

The local stack runs as compose project `ro-backend` with containers
`ro-backend-db`, `ro-backend-builder`, `ro-backend-login`, `ro-backend-char`
and `ro-backend-map`. In `docker-compose.yml`, replace the obsolete
`version: "3.7"` line with `name: ro-backend`, rename each `container_name`
from `rathena-*` to `ro-backend-*`, and pin the database volume so a rename
never starts from an empty database:

```yaml
volumes:
    rathenadb:
        name: docker_rathenadb
```

`docker_rathenadb` is the volume the first start created under the default
project name `docker`. On a fresh machine any name works.

### 1. Packet version

`docker-compose.yml` already contains:

```yaml
environment:
    BUILDER_CONFIGURE: "--enable-packetver=20211103"
```

Keep it. This is the same date as `PACKET_VERSION` in the client.

### 2. Character server settings

Append to `asset/char_conf.txt`:

```yaml
pincode_enabled: no
char_name_option: 0
char_del_delay: 0
```

Reason: the login table starts with `new_account: no`, and the pincode flow is
not part of the Phase 0 client test. Disable it until the flow is implemented.

### 3. Packet obfuscation

No change needed. Stock rAthena defines `PACKET_OBFUSCATION` for
`PACKETVER >= 20110817`, but `src/map/clif_obfuscation.hpp` sets the keys to
`0x00000000` for every `PACKETVER > 20180307`, so packet ids pass through
unchanged at 20211103. The map server logs
`Packet Obfuscation: Enabled. Keys: 0x00000000, 0x00000000, 0x00000000`.

Verified on 2026-11-06 against stock `d4b8e7b8` with `Tools/ROProbe`
(`docs/port/probe-runs/stock-obfuscation.json`): login, character select, map
entry, walk, chat and attack with zero errors. Do not add
`#undef PACKET_OBFUSCATION` to `src/custom/defines_post.hpp`.

### 4. Database initialization

The compose mounts `../../sql-files` into
`/docker-entrypoint-initdb.d`. MariaDB imports every `.sql` file on the first
start of an empty `rathenadb` volume. Later starts do not re-import.

Fixed development credentials:

| Setting | Value |
| --- | --- |
| Host from containers | `db` |
| Host from macOS | `127.0.0.1` |
| Port | `3306` |
| Database | `ragnarok` |
| User | `ragnarok` |
| Password | `ragnarok` |
| Root password | `ragnarok` |

## Build and start

Start the database first:

```sh
docker compose up -d db
```

Build the server binaries. This configures on the first build and then runs
`make clean server` inside the builder container:

```sh
docker compose run --rm builder bash -lc \
  'cd /rathena && (test -f make || ./configure $BUILDER_CONFIGURE) && make clean server'
```

`docker compose run --rm builder` without a command only builds when a server
binary is missing. Use the command above when you need a rebuild.

The first build takes roughly 5 to 15 minutes on Apple Silicon. Wait for exit
code 0 before starting the server processes.

Start login, char, and map:

```sh
docker compose up -d login char map
docker compose ps
docker compose logs --tail=100 login char map
```

All three services should report `running`. Compose starts login before char and
char before map, and each waits for the database, but it does not wait for the
servers to become ready. Inspect the logs if one restarts.

Verify the three client ports:

```sh
nc -vz 127.0.0.1 6900
nc -vz 127.0.0.1 6121
nc -vz 127.0.0.1 5121
```

## Create a test account

`new_account` is `no` by default. Insert the account directly. Passwords are
plain text while `use_MD5_passwords` stays `no`, which is the default.

```sh
docker compose exec db mariadb -uragnarok -pragnarok ragnarok -e "
DELETE FROM login WHERE userid = 'test';
INSERT INTO login (userid, user_pass, sex, email, group_id, pincode)
VALUES ('test', 'test', 'M', 'test@example.com', 0, '');
"
```

Verify:

```sh
docker compose exec db mariadb -uragnarok -pragnarok ragnarok -e "
SELECT account_id, userid, group_id, state FROM login WHERE userid = 'test';
"
```

`group_id` 0 is a normal player. Group 99 is the default administrator group in
`conf/groups.yml`; confirm before using it.

## Point the client at the stack

1. Start the macOS app and select a local kRO client directory.
2. Open the game client screen.
3. Set server address to `127.0.0.1`.
4. Set server port to `6900`.
5. Log in as `test` with password `test`.
6. Create a character in the client UI.
7. Select the character and enter the map.

The login server returns the char server address from `asset/char_conf.txt`.
The char server returns the map server address from `asset/map_conf.txt`. Both
are `127.0.0.1` for a client on the same Mac.

## Play from another machine on the LAN

The default published ports listen on all host interfaces, but the char and map
servers announce `127.0.0.1`. A remote client would connect to itself and fail.
If you applied the loopback port binding above, remove `127.0.0.1:` from 6900,
6121, and 5121 first.

Change only the announced addresses:

- `asset/char_conf.txt`: set `char_ip` to the Mac LAN IP.
- `asset/map_conf.txt`: set `map_ip` to the Mac LAN IP.

Keep `login_ip: login` and the map server `char_ip: char`. Those are container
DNS names used between services. Restart char and map after the change:

```sh
docker compose restart char map
```

Open the macOS firewall for TCP 6900, 6121, and 5121 if prompted.

## Expected Phase 0 failures

- Immediate disconnect after login: check the map and char logs for the
  obfuscation warning. Rebuild after the `#undef` edit.
- Login refused: account row missing, wrong password, or `new_account` disabled.
- Empty character list: create a character first.
- Map connection refused: check port 5121, `map_ip`, and the map server log.
- Char list works but map entry fails: compare the map server packet log with
  `PACKETVER 20211103`.
- Client shows a packet error: record opcode, length, and hex payload before
  changing anything.

## Reset and rebuild

Stop the stack:

```sh
docker compose down
```

Delete the database and force a clean `sql-files` import:

```sh
docker compose down --volumes
```

Rebuild after changing server source or `defines_post.hpp`:

```sh
docker compose run --rm builder bash -lc 'cd /rathena && make clean server'
docker compose up -d --force-recreate login char map
```

Reconfigure after changing the packet version:

```sh
docker compose run --rm builder bash -lc \
  'cd /rathena && make clean && ./configure --enable-packetver=20211103 && make server -j"$(nproc)"'
```

## Troubleshooting

### Port 3306 is already in use

Stop the local MySQL or MariaDB, or change the host side of the mapping:

```yaml
ports:
    - "3307:3306"
```

Container-to-container traffic still uses `db:3306`. Only host tools need the
new port.

### Wrong architecture

On Apple Silicon the images must be arm64:

```sh
docker image inspect rathena:local --format '{{.Architecture}}'
docker image inspect mariadb:noble --format '{{.Architecture}}'
```

Both should print `arm64`. Rebuild with `docker compose build --no-cache` if they
do not.

### Database initialization failed

```sh
docker compose logs db
docker compose down --volumes
docker compose up -d db
```

The import runs only when the volume is empty.

### Builder uses the wrong packet version

`builder.sh` runs `./configure` only when the generated `make` file is absent.
After a packet version change, remove it and reconfigure explicitly with the
command in the reset section.

## Limits

- Not for production. Do not expose it to the internet.
- No account registration by default.
- No pincode flow.
- No web server on 8888.
- Server source and `sql-files` are pinned to one rAthena commit.
- The server needs no Gravity assets. The macOS client still needs a kRO data
  set.

## Acceptance checklist

- [ ] All three client ports answer on `127.0.0.1`.
- [ ] Login, char, and map containers stay running for 10 minutes.
- [ ] Test account exists in MariaDB.
- [ ] Client reaches the login screen.
- [ ] Client creates and selects a character.
- [ ] Character spawns on a map.
- [ ] Walk and chat work for 10 minutes without a disconnect.
