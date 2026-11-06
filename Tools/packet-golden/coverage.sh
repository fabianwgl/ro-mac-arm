#!/usr/bin/env bash
#
# Writes docs/port/packet-coverage.md.
#
# Usage: Tools/packet-golden/coverage.sh
#
# Runs PacketCoverageTests, which counts the client's packet table, decoders and
# PacketFactory builders against the rAthena data in Golden/RathenaGolden20211103.swift.
# The PacketFactory builders are read from the `/// | `PACKET_X` | `clif_function` |` doc comment
# above each builder and handed to the test in PACKET_FACTORY.
#
# Run generate.sh first when rAthena or the client's generated structs changed.

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
factory_swift="$repo_root/Packages/RagnarokNetwork/Sources/RagnarokNetwork/PacketFactory.swift"
output="$repo_root/docs/port/packet-coverage.md"

builders=$(grep -c 'public static func' "$factory_swift")
pairs=$(grep -oE '/// \| `PACKET_[A-Za-z0-9_]+` \| `[A-Za-z0-9_]+` \|' "$factory_swift" |
	sed -E 's/.*`(PACKET_[A-Za-z0-9_]+)` \| `([A-Za-z0-9_]+)`.*/\1=\2/')
documented=$(printf '%s\n' "$pairs" | grep -c .)
if [ "$builders" -ne "$documented" ]; then
	echo "PacketFactory has $builders builders but $documented doc comments naming packet and parse function." >&2
	exit 1
fi

mkdir -p "$(dirname "$output")"
PACKET_FACTORY=$(printf '%s\n' "$pairs" | paste -sd, -) \
	PACKET_COVERAGE_OUTPUT="$output" \
	swift test --package-path "$repo_root/Packages/RagnarokPackets" --filter PacketCoverageTests

echo "wrote ${output#$repo_root/}"
