//
//  PACKET_CZ_REGISTER_GUILD_EMBLEM_IMG.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

/// `clif_parse_GuildChangeEmblem`: `0153 <packet len>.W <emblem data>.?B`, guild master only.
///
/// The data is a zlib compressed BMP. rAthena inflates it into a 1800 byte buffer and requires the `BM` signature, a
/// `bfSize` that equals the inflated length and a `bfOffBits` inside the file, so a 24 by 24 24-bit BMP (1782 bytes)
/// or 8-bit BMP (1654 bytes) fits. It rejects an emblem that is mostly the magenta transparency color.
public let HEADER_CZ_REGISTER_GUILD_EMBLEM_IMG: Int16 = 0x153

public struct PACKET_CZ_REGISTER_GUILD_EMBLEM_IMG: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REGISTER_GUILD_EMBLEM_IMG
    public var data: [UInt8] = []

    public init() {
    }

    /// The length field covers the 4 header bytes.
    public var packetLength: Int16 {
        Int16(truncatingIfNeeded: 4 + data.count)
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(packetLength)
        try encoder.encode(data)
    }
}
