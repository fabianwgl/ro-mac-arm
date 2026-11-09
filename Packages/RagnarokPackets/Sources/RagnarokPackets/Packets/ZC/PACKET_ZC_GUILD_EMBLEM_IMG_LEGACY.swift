//
//  PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// The opcode `clif_guild_emblem` writes. It does not depend on PACKETVER: rAthena always sends the pre 2019 layout
/// and never `0x0b36`, the layout `PACKET_ZC_GUILD_EMBLEM_IMG` decodes.
public let HEADER_ZC_GUILD_EMBLEM_IMG_LEGACY: Int16 = 0x152

/// The emblem of a guild, sent to a client that asked with `CZ_REQ_GUILD_EMBLEM_IMG` and to every online member of
/// the guild when its master changes the emblem.
///
/// `0152 <packet len>.W <guild id>.L <emblem id>.L <emblem data>.?B`. The data is binary, a zlib compressed 24 by 24
/// BMP the way the master's client uploaded it. See `clif_guild_emblem`.
public struct PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY: DecodablePacket {
    public static var size: Int {
        -1
    }

    public var packetType: Int16
    public var packetLength: Int16
    public var guildID: UInt32
    public var emblemID: UInt32
    public var data: [UInt8]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)
        guildID = try decoder.decode(UInt32.self)
        emblemID = try decoder.decode(UInt32.self)

        // An empty array has no base address to read into.
        let dataLength = max(Int(packetLength) - 12, 0)
        data = dataLength > 0 ? try decoder.decode([UInt8].self, count: dataLength) : []
    }
}
