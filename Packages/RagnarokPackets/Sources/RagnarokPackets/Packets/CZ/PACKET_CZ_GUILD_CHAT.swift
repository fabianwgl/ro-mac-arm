//
//  PACKET_CZ_GUILD_CHAT.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

public let HEADER_CZ_GUILD_CHAT: Int16 = 0x17e

public struct PACKET_CZ_GUILD_CHAT: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_GUILD_CHAT
    public var packetLength: Int16 = 0
    public var message: String = ""

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(packetLength)
        try encoder.encode(message, encoding: .utf8)
    }
}
