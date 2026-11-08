//
//  PACKET_CZ_REQ_ROLE_CHANGE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// The owner of a chat room gives it to another member. See `clif_parse_ChangeChatOwner` and `chat_changechatowner`.
///
///     00e0 <role>.L <name>.24B
///
/// 30 bytes. rAthena ignores `role` (the read is commented out in `clif_parse_ChangeChatOwner`) and makes the named
/// member the owner, so the client sends 0 for owner like the official one. A name that is not a member
/// other than the owner changes nothing. Both players then get `ZC_ROLE_CHANGE` (0xe1).
public struct PACKET_CZ_REQ_ROLE_CHANGE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_ROLE_CHANGE
    public var role: Int32
    public var name: String

    public init(role: Int32 = 0, name: String = "") {
        self.role = role
        self.name = name
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(role)
        try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
    }
}
