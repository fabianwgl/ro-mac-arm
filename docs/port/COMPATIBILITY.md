# Compatibility

One page per tested client build. Copy
[compatibility-manifest.template.json](compatibility-manifest.template.json) into
the release and fill in every field. Add a row here for each release or
development milestone.

| Client build | rAthena commit | PACKETVER | Obfuscation | Known gaps |
| --- | --- | --- | --- | --- |
| `main` | `d4b8e7b8f16061cc2496d377ac8f777ce72a4f39` | 20211103 | off | see TASKS.md |

Notes:

- `off` means the server has `PACKET_OBFUSCATION` disabled in
  `src/custom/defines_post.hpp`. See [DOCKER.md](DOCKER.md).
- The rAthena commit pin is defined in [DOCKER.md](DOCKER.md).
