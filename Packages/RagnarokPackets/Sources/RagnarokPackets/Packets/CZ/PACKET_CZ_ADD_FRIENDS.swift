//
//  PACKET_CZ_ADD_FRIENDS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

public let HEADER_CZ_ADD_FRIENDS: Int16 = 0x202

public struct PACKET_CZ_ADD_FRIENDS: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_ADD_FRIENDS
    public var name: String = ""

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
    }
}
