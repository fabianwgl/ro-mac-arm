//
//  PACKET_CZ_GUILD_NOTICE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

/// `clif_parse_GuildChangeNotice`: `016e <guild id>.L <subject>.60B <notice>.120B`.
public let HEADER_CZ_GUILD_NOTICE: Int16 = 0x16e

public struct PACKET_CZ_GUILD_NOTICE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_GUILD_NOTICE
    public var guildID: UInt32 = 0
    public var subject: String = ""
    public var notice: String = ""

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(guildID)
        try encoder.encode(subject, lengthOfBytes: 60, encoding: .utf8)
        try encoder.encode(notice, lengthOfBytes: 120, encoding: .utf8)
    }
}
