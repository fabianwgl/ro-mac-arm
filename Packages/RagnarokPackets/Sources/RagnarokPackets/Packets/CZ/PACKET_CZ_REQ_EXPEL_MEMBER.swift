//
//  PACKET_CZ_REQ_EXPEL_MEMBER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// The owner of a chat room expels a member. See `clif_parse_KickFromChat` and `chat_kickchat`.
///
///     00e2 <name>.24B
///
/// 26 bytes. rAthena remembers the character in the kick list of the room, so the member cannot come back
/// (`ZC_REFUSE_ENTER_ROOM` with 2), and sends `ZC_MEMBER_EXIT` with the kicked flag to the whole room.
/// It does nothing when the target is a game master protected from kicks (`PC_PERM_NO_CHAT_KICK`).
public struct PACKET_CZ_REQ_EXPEL_MEMBER: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_EXPEL_MEMBER
    public var name: String

    public init(name: String = "") {
        self.name = name
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
    }
}
