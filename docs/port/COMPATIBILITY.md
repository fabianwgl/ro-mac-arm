# Compatibility

One page per tested client build. Copy
[compatibility-manifest.template.json](compatibility-manifest.template.json) into
the release and fill in every field. Add a row here for each release or
development milestone.

| Client build | Server | rAthena commit | PACKETVER | Obfuscation | Known gaps |
| --- | --- | --- | --- | --- | --- |
| `main` | Docker `ro-backend` (reference for the probe) | `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39`, Renewal | 20211103 | stock (zero keys) | see KNOWN_GAPS.md |
| `integrate-m2` | Docker `ro-backend` | same | 20211103 | stock (zero keys) | see KNOWN_GAPS.md |
| not tested yet | Embedded `swift-rathena` at `eec09e4f` (what the player uses, TASKS.md P7-01) | base not recorded yet; last merge from rAthena 2026-09-08. Renewal and Pre-Renewal builds | 20211103 | not checked | not checked |

Notes:

- `stock (zero keys)`: rAthena compiles `PACKET_OBFUSCATION` in, but its keys are
  zero after 2018-03-07, so no client support is needed. See [DOCKER.md](DOCKER.md) step 3.
- The rAthena commit pin is defined in [DOCKER.md](DOCKER.md).
