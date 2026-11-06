#!/usr/bin/env bash
#
# Generates Packages/RagnarokPackets/Tests/RagnarokPacketsTests/Golden/RathenaGolden20211103.swift
# from the rAthena headers at the pinned commit.
#
# Usage: Tools/packet-golden/generate.sh <rathena-dir>
#
# How it works:
#   1. The rAthena packet headers are run through the C++ preprocessor (clang++ -E with
#      PACKETVER=20211103, the define `./configure --enable-packetver=20211103` passes) to
#      list the HEADER_* constants and PACKET_* structs that exist at this PACKETVER.
#   2. dump_map.cpp and dump_common.cpp are compiled against the real headers. They record
#      the packet table by #including clif_packetdb.hpp with packetdb_addpacket() turned into
#      a recorder, print sizeof() of every struct and HEADER_* values, and build the golden
#      packets with rAthena's own structs and position packing.
#   3. emit_swift.awk joins that with the HEADER_* constants and struct sizes the Swift
#      package defines and writes the Swift file.
#
# Nothing is parsed with regular expressions except the preprocessor output (one
# `const int16 HEADER_X = ...` / `struct X {` per line) and the Swift sources.
#
# The rAthena checkout is only read. GPL-3.0, derived from rAthena.

set -euo pipefail

EXPECTED_COMMIT=d4b8e7b8f16061cc2496d377ac8f777ce72a4f39
PACKETVER=20211103

if [ $# -ne 1 ] || [ ! -d "$1/src/map" ]; then
	echo "usage: $0 <rathena-dir>" >&2
	exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
rathena=$(cd "$1" && pwd)
swift_sources="$repo_root/Packages/RagnarokPackets/Sources/RagnarokPackets"
output="$repo_root/Packages/RagnarokPackets/Tests/RagnarokPacketsTests/Golden/RathenaGolden20211103.swift"

commit=$(git -C "$rathena" rev-parse HEAD)
if [ "$commit" != "$EXPECTED_COMMIT" ] && [ "${PACKET_GOLDEN_ANY_COMMIT:-0}" != "1" ]; then
	echo "rAthena is at $commit, expected $EXPECTED_COMMIT." >&2
	echo "Set PACKET_GOLDEN_ANY_COMMIT=1 to generate from it anyway." >&2
	exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/packet-golden.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/map" "$work/common"

# Same defines as the rAthena Makefiles use, see `grep PACKETVER rathena/config.log`.
cxx_flags=(
	-std=c++17 -w -fno-strict-aliasing
	-DHAS_TLS -DHAVE_GETADDRINFO -DHAVE_SETRLIMIT -DHAVE_STRNLEN -DHAVE_MONOTONIC_CLOCK
	-DPACKETVER="$PACKETVER"
	-I"$rathena/src/common" -I"$rathena/src"
	-I"$rathena/3rdparty/libconfig"
	-I"$rathena/3rdparty/rapidyaml/src" -I"$rathena/3rdparty/rapidyaml/ext/c4core/src"
	-I"$rathena/3rdparty/mysql/include"
)

# Lists the HEADER_* constants and the structs defined in the packet headers as seen by the
# compiler, as X-macro lines for names.inc.
write_names() {
	local tag=$1 include=$2
	printf '#include "%s"\n' "$include" >"$work/$tag/driver.cpp"
	clang++ "${cxx_flags[@]}" -E "$work/$tag/driver.cpp" -o "$work/$tag/driver.i"
	awk '
		/^# [0-9]+ "/ { file = $3; next }
		/^const int16 HEADER_[A-Za-z0-9_]+ = / {
			name = $3; sub(/^HEADER_/, "", name); print "GOLDEN_HEADER(" name ")"
		}
		file ~ /\/packets(_struct)?\.hpp"$/ && /^struct [A-Za-z_][A-Za-z0-9_]* *\{/ {
			name = $2; sub(/\{.*$/, "", name); print "GOLDEN_STRUCT(" name ")"
		}
	' "$work/$tag/driver.i" | sort -u >"$work/$tag/names.inc"
}

write_names map "map/clif.hpp"
write_names common "common/packets.hpp"

clang++ "${cxx_flags[@]}" -I"$work/map" -I"$script_dir" -o "$work/dump_map" "$script_dir/dump_map.cpp"
clang++ "${cxx_flags[@]}" -I"$work/common" -I"$script_dir" -o "$work/dump_common" "$script_dir/dump_common.cpp"

"$work/dump_map" >"$work/dump.txt"
"$work/dump_common" >>"$work/dump.txt"

# HEADER_* constants and sized structs the Swift package defines.
grep -rhoE '^(public )?let HEADER_[A-Za-z0-9_]+' "$swift_sources" | sed -E 's/^(public )?let //' | sort -u >"$work/client_headers.txt"
find "$swift_sources" -name '*.swift' -print0 | sort -z | xargs -0 awk '
	/^(public )?struct [A-Za-z0-9_]+/ {
		name = $0
		sub(/^(public )?struct /, "", name)
		sub(/[^A-Za-z0-9_].*$/, "", name)
		pending = ""
		if (name ~ /^_/) next
		if ($0 ~ /DecodablePacket|CodablePacket/) { print name; next }
		pending = name
		lines = 0
		next
	}
	pending != "" {
		lines++
		if ($0 ~ /static (var|let) size/) { print pending; pending = "" }
		else if (lines >= 3) pending = ""
	}
' | sort -u >"$work/client_structs.txt"

# Opcodes and HEADER_* names rAthena's packet-sending code uses. The sources are run through the
# preprocessor with -fdirectives-only (evaluates every #if PACKETVER block, leaves macros alone), so
# only code that is live at this PACKETVER counts. Opcode literals count when they sit on a line that
# writes a packet type (WFIFOW, WBUFW, packet_len, packetType, cmd).
: >"$work/live.txt"
for source in "$rathena/src/map/clif.cpp" "$rathena/src/char/char_clif.cpp" "$rathena/src/login/loginclif.cpp"; do
	clang++ "${cxx_flags[@]}" -E -fdirectives-only -x c++ "$source" |
		awk -v target="$source" '
			/^# [0-9]+ "/ { file = $3; gsub(/"/, "", file); next }
			file == target { print }
		' >>"$work/live.txt"
done
awk '
	{ line = $0; sub(/\/\/.*$/, "", line) }
	line ~ /^[ \t]*(\/\*|\*)/ { next }
	line ~ /(WFIFOW|WBUFW|packet_len|[pP]acketType|cmd)/ {
		while (match(line, /0[xX][0-9a-fA-F]+/)) {
			token = tolower(substr(line, RSTART, RLENGTH))
			sub(/^0x0+/, "0x", token)
			if (token == "0x") token = "0x0"
			print token
			line = substr(line, RSTART + RLENGTH)
		}
	}
' "$work/live.txt" | sort -u >"$work/literals.txt"
grep -oE '\bHEADER_[A-Za-z0-9_]+\b' "$work/live.txt" | sort -u >"$work/header_refs.txt"

# Packet names for opcodes that have no HEADER_* constant, from the "/// 0a18 <fields> (ZC_NAME)"
# comments above rAthena's clif functions. Used only to label and sort packets in reports.
for file in "$rathena"/src/map/*.cpp; do
	awk '
		/^[ \t]*(\/\/\/|\/\/|\*)[ \t]+[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]?[ \t]/ {
			line = $0
			sub(/^[ \t]*(\/\/\/|\/\/|\*)[ \t]+/, "", line)
			opcode = line
			sub(/[ \t].*$/, "", opcode)
			if (match(line, /\([A-Z][A-Z0-9]*_[A-Z0-9_]*[,)]/)) {
				name = substr(line, RSTART + 1, RLENGTH - 2)
				sub(/^0+/, "", opcode)
				print tolower(opcode) "\t" name
			}
		}
	' "$file"
done | sort -u >"$work/name_hints.txt"

mkdir -p "$(dirname "$output")"
awk -f "$script_dir/emit_swift.awk" \
	-v commit="$commit" -v packetver="$PACKETVER" \
	-v files="$work/dump.txt $work/client_headers.txt $work/client_structs.txt $work/literals.txt $work/header_refs.txt $work/name_hints.txt" \
	"$work/dump.txt" "$work/client_headers.txt" "$work/client_structs.txt" "$work/literals.txt" "$work/header_refs.txt" "$work/name_hints.txt" \
	>"$work/output.swift"

mv "$work/output.swift" "$output"
echo "wrote ${output#$repo_root/}"
