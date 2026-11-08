//
//  ChatRoomPacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Byte level checks of the chat room packets at PACKETVER 20211103. The layouts are the ones in rAthena's
//  clif.cpp (clif_createchat, clif_dispchat, clif_changechatstatus, clif_clearchat, clif_joinchatfail,
//  clif_joinchatok, clif_addchat, clif_chat_role, clif_chat_leave and the clif_parse_* of the requests),
//  packets.hpp and packets_struct.hpp, written out here byte by byte instead of through the Swift structs.
//  The sizes are the ones in clif_packetdb.hpp.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class ChatRoomPacketTests: XCTestCase {

    // MARK: - Byte helpers

    private func le(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8(value >> 8)]
    }

    private func le(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> ($0 * 8)) & 0xff) }
    }

    private func fixed(_ text: String, length: Int) -> [UInt8] {
        var bytes = [UInt8](text.utf8)
        bytes += [UInt8](repeating: 0, count: length - bytes.count)
        return bytes
    }

    private func decodeAll(_ bytes: [UInt8]) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return packets
    }

    private func encoded(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    /// 00d7 / 00df: `<packet len>.W <owner id>.L <chat id>.L <limit>.W <users>.W <type>.B <title>.?B`, the title
    /// is not zero terminated (`clif_dispchat` copies `safestrnlen` bytes).
    private func roomBody(owner: UInt32, chat: UInt32, limit: UInt16, users: UInt16, type: UInt8, title: String) -> [UInt8] {
        le(owner) + le(chat) + le(limit) + le(users) + [type] + [UInt8](title.utf8)
    }

    // MARK: - The sign

    func testRoomNewEntryCarriesOwnerChatLimitUsersTypeAndTheUnterminatedTitle() throws {
        let body = roomBody(owner: 2_000_001, chat: 777, limit: 8, users: 1, type: 1, title: "Trade Prontera")
        let bytes = le(UInt16(0xd7)) + le(UInt16(body.count + 4)) + body
        XCTAssertEqual(bytes.count, 4 + 4 + 4 + 2 + 2 + 1 + 14)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let entry = try XCTUnwrap(packets.first as? PACKET_ZC_ROOM_NEWENTRY)
        XCTAssertEqual(entry.packetType, HEADER_ZC_ROOM_NEWENTRY)
        XCTAssertEqual(entry.owner, 2_000_001)
        XCTAssertEqual(entry.id, 777)
        XCTAssertEqual(entry.limit, 8)
        XCTAssertEqual(entry.users, 1)
        XCTAssertEqual(entry.type, 1)
        XCTAssertEqual(entry.title, "Trade Prontera")
    }

    func testRoomNewEntryWithAnEmptyTitleStillFrames() throws {
        let body = roomBody(owner: 5, chat: 6, limit: 2, users: 2, type: 0, title: "")
        let bytes = le(UInt16(0xd7)) + le(UInt16(body.count + 4)) + body
        let destroy = le(UInt16(0xd8)) + le(UInt32(6))

        let packets = try decodeAll(bytes + destroy)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_ROOM_NEWENTRY)?.title, "")
        XCTAssertEqual((packets[0] as? PACKET_ZC_ROOM_NEWENTRY)?.type, 0)
        XCTAssertEqual((packets[1] as? PACKET_ZC_DESTROY_ROOM)?.chatId, 6)
    }

    func testDestroyRoomIsSixBytes() throws {
        let bytes = le(UInt16(0xd8)) + le(UInt32(777))
        XCTAssertEqual(bytes.count, 6)

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_DESTROY_ROOM)
        XCTAssertEqual(packet.packetType, HEADER_ZC_DESTROY_ROOM)
        XCTAssertEqual(packet.chatId, 777)
    }

    func testChangeChatRoomCarriesTheSameFieldsAsTheSign() throws {
        let body = roomBody(owner: 2_000_001, chat: 777, limit: 20, users: 3, type: 0, title: "New title")
        let bytes = le(UInt16(0xdf)) + le(UInt16(body.count + 4)) + body

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_CHANGE_CHATROOM)
        XCTAssertEqual(packet.packetType, HEADER_ZC_CHANGE_CHATROOM)
        XCTAssertEqual(packet.ownerId, 2_000_001)
        XCTAssertEqual(packet.chatId, 777)
        XCTAssertEqual(packet.limit, 20)
        XCTAssertEqual(packet.users, 3)
        XCTAssertEqual(packet.flag, 0)
        XCTAssertEqual(packet.title, "New title")
    }

    // MARK: - Creating and joining

    func testAckCreateIsThreeBytes() throws {
        for flag: UInt8 in [0, 1, 2] {
            let bytes = le(UInt16(0xd6)) + [flag]
            let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ACK_CREATE_CHATROOM)
            XCTAssertEqual(packet.packetType, HEADER_ZC_ACK_CREATE_CHATROOM)
            XCTAssertEqual(packet.flag, flag)
        }
    }

    func testRefuseEnterRoomIsThreeBytes() throws {
        for result: UInt8 in 0...7 {
            let bytes = le(UInt16(0xda)) + [result]
            let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_REFUSE_ENTER_ROOM)
            XCTAssertEqual(packet.packetType, HEADER_ZC_REFUSE_ENTER_ROOM)
            XCTAssertEqual(packet.result, result)
        }
    }

    func testEnterRoomListsTheOwnerFirstWithRoleZero() throws {
        // 00db <packet len>.W <chat id>.L { <role>.L <name>.24B }*, role 0 is the owner.
        var members: [UInt8] = []
        members += le(UInt32(0)) + fixed("Owner", length: 24)
        members += le(UInt32(1)) + fixed("Guest", length: 24)
        members += le(UInt32(1)) + fixed("Another", length: 24)
        let bytes = le(UInt16(0xdb)) + le(UInt16(8 + members.count)) + le(UInt32(777)) + members
        XCTAssertEqual(bytes.count, 8 + 28 * 3)

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ENTER_ROOM)
        XCTAssertEqual(packet.packetType, HEADER_ZC_ENTER_ROOM)
        XCTAssertEqual(packet.chatId, 777)
        XCTAssertEqual(packet.members.count, 3)
        XCTAssertEqual(packet.members.map(\.flag), [0, 1, 1])
        XCTAssertEqual(packet.members.map(\.name), ["Owner", "Guest", "Another"])
    }

    func testRequestToEnterIsFourteenBytesWithAnEightByteFieldPassword() throws {
        var packet = PACKET_CZ_REQ_ENTER_ROOM()
        packet.packetType = HEADER_CZ_REQ_ENTER_ROOM
        packet.chat_id = 777
        packet.password = "secret"
        let bytes = try encoded(packet)

        // 00d9 <chat id>.L <password>.8B
        XCTAssertEqual(bytes.count, 14)
        XCTAssertEqual(Array(bytes[0..<2]), le(UInt16(0xd9)))
        XCTAssertEqual(Array(bytes[2..<6]), le(UInt32(777)))
        XCTAssertEqual(Array(bytes[6..<14]), fixed("secret", length: 8))
    }

    func testCreateRoomCarriesLimitTypePasswordAndTheTitleWithoutTerminator() throws {
        var packet = PACKET_CZ_CREATE_CHATROOM()
        packet.packetType = HEADER_CZ_CREATE_CHATROOM
        packet.packetLength = Int16(15 + 5)
        packet.limit = 12
        packet.type = 0
        packet.password = "pw"
        packet.title = "Hello"
        let bytes = try encoded(packet)

        // 00d5 <packet len>.W <limit>.W <type>.B <password>.8B <title>.?B
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(Array(bytes[0..<2]), le(UInt16(0xd5)))
        XCTAssertEqual(Array(bytes[2..<4]), le(UInt16(20)))
        XCTAssertEqual(Array(bytes[4..<6]), le(UInt16(12)))
        XCTAssertEqual(bytes[6], 0)
        XCTAssertEqual(Array(bytes[7..<15]), fixed("pw", length: 8))
        XCTAssertEqual(Array(bytes[15...]), [UInt8]("Hello".utf8))
    }

    func testChangeRoomHasTheLayoutOfCreate() throws {
        var packet = PACKET_CZ_CHANGE_CHATROOM()
        packet.packetType = HEADER_CZ_CHANGE_CHATROOM
        packet.packetLength = Int16(15 + 3)
        packet.limit = 5
        packet.type = 1
        packet.password = ""
        packet.title = "New"
        let bytes = try encoded(packet)

        // 00de <packet len>.W <limit>.W <type>.B <password>.8B <title>.?B
        XCTAssertEqual(bytes.count, 18)
        XCTAssertEqual(Array(bytes[0..<2]), le(UInt16(0xde)))
        XCTAssertEqual(Array(bytes[2..<4]), le(UInt16(18)))
        XCTAssertEqual(Array(bytes[4..<6]), le(UInt16(5)))
        XCTAssertEqual(bytes[6], 1)
        XCTAssertEqual(Array(bytes[7..<15]), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(Array(bytes[15...]), [UInt8]("New".utf8))
    }

    // MARK: - Members

    func testMemberNewEntryIsTwentyEightBytes() throws {
        // 00dc <users>.W <name>.24B
        let bytes = le(UInt16(0xdc)) + le(UInt16(3)) + fixed("Guest", length: 24)
        XCTAssertEqual(bytes.count, 28)

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_MEMBER_NEWENTRY)
        XCTAssertEqual(packet.packetType, HEADER_ZC_MEMBER_NEWENTRY)
        XCTAssertEqual(packet.count, 3)
        XCTAssertEqual(packet.name, "Guest")
    }

    func testMemberExitCarriesTheUsersLeftAndTheKickedFlag() throws {
        // 00dd <users>.W <name>.24B <flag>.B
        let left = le(UInt16(0xdd)) + le(UInt16(1)) + fixed("Guest", length: 24) + [0]
        let kicked = le(UInt16(0xdd)) + le(UInt16(1)) + fixed("Rude", length: 24) + [1]
        XCTAssertEqual(left.count, 29)

        let packets = try decodeAll(left + kicked)
        XCTAssertEqual(packets.count, 2)

        let first = try XCTUnwrap(packets[0] as? PACKET_ZC_MEMBER_EXIT)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.name, "Guest")
        XCTAssertEqual(first.kicked, 0)

        let second = try XCTUnwrap(packets[1] as? PACKET_ZC_MEMBER_EXIT)
        XCTAssertEqual(second.name, "Rude")
        XCTAssertEqual(second.kicked, 1)
    }

    func testRoleChangeIsThirtyBytesAndZeroIsTheOwner() throws {
        // 00e1 <role>.L <name>.24B
        let bytes = le(UInt16(0xe1)) + le(UInt32(0)) + fixed("Guest", length: 24)
        XCTAssertEqual(bytes.count, 30)

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ROLE_CHANGE)
        XCTAssertEqual(packet.packetType, HEADER_ZC_ROLE_CHANGE)
        XCTAssertEqual(packet.flag, 0)
        XCTAssertEqual(packet.name, "Guest")
    }

    func testRoomPacketsFrameBackToBack() throws {
        let body = roomBody(owner: 1, chat: 2, limit: 3, users: 1, type: 1, title: "Hi")
        let sign = le(UInt16(0xd7)) + le(UInt16(body.count + 4)) + body
        let ack = le(UInt16(0xd6)) + [0]
        let newEntry = le(UInt16(0xdc)) + le(UInt16(2)) + fixed("Guest", length: 24)

        let packets = try decodeAll(sign + ack + newEntry)
        XCTAssertEqual(packets.count, 3)
        XCTAssertTrue(packets[0] is PACKET_ZC_ROOM_NEWENTRY)
        XCTAssertTrue(packets[1] is PACKET_ZC_ACK_CREATE_CHATROOM)
        XCTAssertTrue(packets[2] is PACKET_ZC_MEMBER_NEWENTRY)
    }

    // MARK: - Owner requests

    func testRoleChangeRequestIsThirtyBytesWithRoleThenName() throws {
        let bytes = try encoded(PACKET_CZ_REQ_ROLE_CHANGE(role: 0, name: "Guest"))

        // 00e0 <role>.L <name>.24B
        XCTAssertEqual(bytes.count, 30)
        XCTAssertEqual(Array(bytes[0..<2]), le(UInt16(0xe0)))
        XCTAssertEqual(Array(bytes[2..<6]), le(UInt32(0)))
        XCTAssertEqual(Array(bytes[6..<30]), fixed("Guest", length: 24))
    }

    func testExpelRequestIsTwentySixBytes() throws {
        let bytes = try encoded(PACKET_CZ_REQ_EXPEL_MEMBER(name: "Rude"))

        // 00e2 <name>.24B
        XCTAssertEqual(bytes.count, 26)
        XCTAssertEqual(Array(bytes[0..<2]), le(UInt16(0xe2)))
        XCTAssertEqual(Array(bytes[2..<26]), fixed("Rude", length: 24))
    }

    func testExitRoomIsTwoBytes() throws {
        XCTAssertEqual(try encoded(PACKET_CZ_EXIT_ROOM()), [0xe3, 0x00])
    }

    func testNamesOfTwentyFourBytesFit() throws {
        let name = String(repeating: "n", count: 24)
        let bytes = try encoded(PACKET_CZ_REQ_EXPEL_MEMBER(name: name))
        XCTAssertEqual(Array(bytes[2..<26]), [UInt8](name.utf8))
    }
}
