# Local Patches

Every divergence from `arkadeleon/ragnarok-offline` is listed here. See
[UPSTREAM_SYNC.md](UPSTREAM_SYNC.md) for the sync procedure.

| File or area | Reason | Upstreamable? |
| --- | --- | --- |
| App display name and bundle identifier (xcconfig) | Fork identity and a separate sandbox container: `tech.thecapy.ro-mac-client` | No, fork specific |
| `NOTICE`, `.github/` CI, issue templates, `scripts/provision-assets.sh` | Fork-only licensing, build, and asset provisioning files | No, fork specific |
