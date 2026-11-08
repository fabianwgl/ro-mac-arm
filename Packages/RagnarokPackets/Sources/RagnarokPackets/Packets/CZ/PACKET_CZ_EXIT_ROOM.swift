//
//  PACKET_CZ_EXIT_ROOM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Leaves the chat room. See `clif_parse_ChatLeave` and `chat_leavechat`.
///
///     00e3
///
/// 2 bytes. The whole room, the leaver included, gets `ZC_MEMBER_EXIT` (0xdd). The room goes away when
/// nobody is left (`ZC_DESTROY_ROOM`), and passes to the next member when the owner leaves (`ZC_ROLE_CHANGE`).
public struct PACKET_CZ_EXIT_ROOM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_EXIT_ROOM

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
