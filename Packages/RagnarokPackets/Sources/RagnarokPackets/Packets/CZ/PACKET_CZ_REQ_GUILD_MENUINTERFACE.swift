//
//  PACKET_CZ_REQ_GUILD_MENUINTERFACE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

/// `clif_parse_GuildCheckMaster`: `014d`, answered with `ZC_ACK_GUILD_MENUINTERFACE`.
public let HEADER_CZ_REQ_GUILD_MENUINTERFACE: Int16 = 0x14d

public struct PACKET_CZ_REQ_GUILD_MENUINTERFACE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_GUILD_MENUINTERFACE

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
