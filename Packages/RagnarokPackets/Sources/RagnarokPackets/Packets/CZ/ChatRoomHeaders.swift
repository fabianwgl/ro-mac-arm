//
//  ChatRoomHeaders.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Client to server chat room opcodes at PACKETVER 20211103 that the generated packets.swift does not have.
// clif_packetdb.hpp registers them with raw numbers (`parseable_packet(0x00e0, 30, clif_parse_ChangeChatOwner, 2, 6)`)
// and rAthena has no HEADER_* constant for them, so the names are the ones its comments give. The other chat room
// opcodes (0xd5 create, 0xd9 join, 0xde change) are generated.

/// `CZ_REQ_ROLE_CHANGE`, `clif_parse_ChangeChatOwner`. The owner of a room gives the room to another member.
public let HEADER_CZ_REQ_ROLE_CHANGE: Int16 = 0xe0

/// `CZ_REQ_EXPEL_MEMBER`, `clif_parse_KickFromChat`. The owner of a room expels a member by name.
public let HEADER_CZ_REQ_EXPEL_MEMBER: Int16 = 0xe2

/// `CZ_EXIT_ROOM`, `clif_parse_ChatLeave`. Leaves the room, and closes it when the player is the last member.
public let HEADER_CZ_EXIT_ROOM: Int16 = 0xe3
