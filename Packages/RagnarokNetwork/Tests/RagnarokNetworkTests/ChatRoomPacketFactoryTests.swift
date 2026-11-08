//
//  ChatRoomPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  The bytes of the chat room requests against what rAthena reads at PACKETVER 20211103
//  (clif_parse_CreateChatRoom, clif_parse_ChatAddMember, clif_parse_ChatRoomStatusChange,
//  clif_parse_ChangeChatOwner, clif_parse_KickFromChat, clif_parse_ChatLeave in clif.cpp,
//  offsets and sizes from clif_packetdb.hpp and packets.hpp).
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Chat room packet factory")
struct ChatRoomPacketFactoryTests {
    private func bytes(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << UInt32($1 * 8) }
    }

    private func field(_ data: [UInt8], _ range: Range<Int>) -> [UInt8] {
        Array(data[range].prefix { $0 != 0 })
    }

    @Test func createPublicRoomCarriesLimitTypeEmptyPasswordAndTitle() throws {
        let data = try bytes(PacketFactory.CZ_CREATE_CHATROOM(title: "Hello room", limit: 12, isPublic: true, password: "ignored"))

        // 00d5 <packet len>.W <limit>.W <type>.B <passwd>.8B <title>.?B
        #expect(data.count == 15 + 10)
        #expect(uint16(data, at: 0) == 0xd5)
        #expect(uint16(data, at: 2) == 25)
        #expect(uint16(data, at: 4) == 12)
        #expect(data[6] == 1)
        #expect(Array(data[7..<15]) == [UInt8](repeating: 0, count: 8))
        #expect(Array(data[15...]) == [UInt8]("Hello room".utf8))
    }

    @Test func createPrivateRoomCarriesThePassword() throws {
        let data = try bytes(PacketFactory.CZ_CREATE_CHATROOM(title: "Secret", limit: 2, isPublic: false, password: "pw1234"))

        #expect(uint16(data, at: 2) == UInt16(15 + 6))
        #expect(data[6] == 0)
        #expect(field(data, 7..<15) == [UInt8]("pw1234".utf8))
    }

    @Test func createCutsTitleAndPasswordToWhatRathenaKeeps() throws {
        let title = String(repeating: "t", count: 50)
        let data = try bytes(PacketFactory.CZ_CREATE_CHATROOM(title: title, limit: 20, isPublic: false, password: "123456789012"))

        // CHATROOM_TITLE_SIZE is 37, so 36 bytes of title; the password field has 8.
        #expect(data.count == 15 + 36)
        #expect(uint16(data, at: 2) == UInt16(15 + 36))
        #expect(field(data, 7..<15) == [UInt8]("12345678".utf8))
        #expect(Array(data[15...]) == [UInt8](repeating: UInt8(ascii: "t"), count: 36))
    }

    @Test func titleCutNeverSplitsACharacter() throws {
        // 20 three byte characters are 60 bytes: 12 of them fit in 36 bytes.
        let title = String(repeating: "あ", count: 20)
        let data = try bytes(PacketFactory.CZ_CREATE_CHATROOM(title: title, limit: 5, isPublic: true, password: ""))

        #expect(data.count == 15 + 36)
        #expect(String(decoding: data[15...], as: UTF8.self) == String(repeating: "あ", count: 12))
    }

    @Test func joinIsFourteenBytesWithTheChatIDNotTheOwnerID() throws {
        let data = try bytes(PacketFactory.CZ_REQ_ENTER_ROOM(chatID: 1_048_576, password: "pw"))

        // 00d9 <chat id>.L <passwd>.8B
        #expect(data.count == 14)
        #expect(uint16(data, at: 0) == 0xd9)
        #expect(uint32(data, at: 2) == 1_048_576)
        #expect(field(data, 6..<14) == [UInt8]("pw".utf8))
    }

    @Test func joiningAPublicRoomSendsAnEmptyPasswordField() throws {
        let data = try bytes(PacketFactory.CZ_REQ_ENTER_ROOM(chatID: 5, password: ""))

        #expect(data.count == 14)
        #expect(Array(data[6..<14]) == [UInt8](repeating: 0, count: 8))
    }

    @Test func changeCarriesTheNewSettingsInTheLayoutOfCreate() throws {
        let data = try bytes(PacketFactory.CZ_CHANGE_CHATROOM(title: "New title", limit: 9, isPublic: false, password: "abc"))

        // 00de <packet len>.W <limit>.W <type>.B <passwd>.8B <title>.?B
        #expect(data.count == 15 + 9)
        #expect(uint16(data, at: 0) == 0xde)
        #expect(uint16(data, at: 2) == 24)
        #expect(uint16(data, at: 4) == 9)
        #expect(data[6] == 0)
        #expect(field(data, 7..<15) == [UInt8]("abc".utf8))
        #expect(Array(data[15...]) == [UInt8]("New title".utf8))
    }

    @Test func makingARoomPublicClearsThePassword() throws {
        let data = try bytes(PacketFactory.CZ_CHANGE_CHATROOM(title: "Open", limit: 9, isPublic: true, password: "abc"))

        #expect(data[6] == 1)
        #expect(Array(data[7..<15]) == [UInt8](repeating: 0, count: 8))
    }

    @Test func giveRoomAwayIsThirtyBytes() throws {
        let data = try bytes(PacketFactory.CZ_REQ_ROLE_CHANGE(newOwnerName: "Guest"))

        // 00e0 <role>.L <nick>.24B
        #expect(data.count == 30)
        #expect(uint16(data, at: 0) == 0xe0)
        #expect(uint32(data, at: 2) == 0)
        #expect(field(data, 6..<30) == [UInt8]("Guest".utf8))
    }

    @Test func expelIsTwentySixBytes() throws {
        let data = try bytes(PacketFactory.CZ_REQ_EXPEL_MEMBER(name: "Rude"))

        // 00e2 <nick>.24B
        #expect(data.count == 26)
        #expect(uint16(data, at: 0) == 0xe2)
        #expect(field(data, 2..<26) == [UInt8]("Rude".utf8))
    }

    @Test func leaveIsTwoBytes() throws {
        #expect(try bytes(PacketFactory.CZ_EXIT_ROOM()) == [0xe3, 0x00])
    }
}
