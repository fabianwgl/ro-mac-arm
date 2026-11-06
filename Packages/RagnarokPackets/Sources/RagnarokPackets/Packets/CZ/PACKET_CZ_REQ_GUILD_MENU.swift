//
//  PACKET_CZ_REQ_GUILD_MENU.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

/// `clif_parse_GuildRequestInfo`: `014f <type>.L`.
///
/// type: 0 basic info and relations, 1 position names and members, 2 position names and position info,
/// 3 skills, 4 expulsion list.
public let HEADER_CZ_REQ_GUILD_MENU: Int16 = 0x14f

public struct PACKET_CZ_REQ_GUILD_MENU: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_GUILD_MENU
    public var type: Int32 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(type)
    }
}
