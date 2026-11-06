// Shared output helpers for the packet-golden dump programs.
//
// The dump programs print one record per line, tab separated, with a leading
// tag. generate.sh turns those records into the Swift golden file.
//
//   @pkt   <opcode> <length> <function|-> <offsets|-> <latest 0|1>
//   @hdr   <HEADER_NAME> <value>
//   @size  <struct name> <sizeof>
//   @blob  <NAME> <lowercase hex> <layout description>
//
// GPL-3.0, derived from rAthena.

#ifndef PACKET_GOLDEN_EMIT_HPP
#define PACKET_GOLDEN_EMIT_HPP

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace golden {

/// Copies a C string into a fixed char array the way rAthena fills packet fields
/// (zero padded, truncated to the array size).
template <size_t N>
inline void copy_string(char (&dst)[N], const char* src) {
	std::memset(dst, 0, N);
	std::strncpy(dst, src, N);
}

inline void emit_blob(const char* name, const void* data, size_t size, const char* layout) {
	const uint8_t* bytes = static_cast<const uint8_t*>(data);
	std::printf("@blob\t%s\t", name);
	for (size_t i = 0; i < size; i++) {
		std::printf("%02x", bytes[i]);
	}
	std::printf("\t%s\n", layout);
}

inline void emit_blob(const char* name, const std::vector<uint8_t>& data, const char* layout) {
	emit_blob(name, data.data(), data.size(), layout);
}

/// Little endian writers for packets rAthena only reads with RFIFOx (no struct).
inline void put_u16(std::vector<uint8_t>& buf, size_t pos, uint16_t value) {
	buf[pos + 0] = static_cast<uint8_t>(value);
	buf[pos + 1] = static_cast<uint8_t>(value >> 8);
}

inline void put_u32(std::vector<uint8_t>& buf, size_t pos, uint32_t value) {
	for (int i = 0; i < 4; i++) {
		buf[pos + i] = static_cast<uint8_t>(value >> (8 * i));
	}
}

}  // namespace golden

#endif
