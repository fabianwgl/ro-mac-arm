//
//  PACKET_CZ_REQ_MAKE_GUILD.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

/// `clif_parse_CreateGuild`: `0165 <char id>.L <guild name>.24B`.
public let HEADER_CZ_REQ_MAKE_GUILD: Int16 = 0x165

public struct PACKET_CZ_REQ_MAKE_GUILD: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_MAKE_GUILD
    public var GID: UInt32 = 0
    public var guildName: String = ""

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(GID)
        try encoder.encode(guildName, lengthOfBytes: 24, encoding: .utf8)
    }
}
