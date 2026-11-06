//
//  GuildPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Guild packet factory")
struct GuildPacketFactoryTests {
    private func bytes(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xff) }
    }

    private func field(_ text: String, size: Int) -> [UInt8] {
        Array(text.utf8) + [UInt8](repeating: 0, count: size - text.utf8.count)
    }

    @Test func makeGuild() throws {
        let data = try bytes(PacketFactory.CZ_REQ_MAKE_GUILD(characterID: 150_000, name: "Poring Hunters"))

        #expect(data == [0x65, 0x01] + le32(150_000) + field("Poring Hunters", size: 24))
        #expect(data.count == 30)
    }

    @Test func menuInterface() throws {
        let data = try bytes(PacketFactory.CZ_REQ_GUILD_MENUINTERFACE())

        #expect(data == [0x4d, 0x01])
    }

    @Test func menuRequestsEveryTab() throws {
        for type in Int32(0)...4 {
            let data = try bytes(PacketFactory.CZ_REQ_GUILD_MENU(type: type))

            #expect(data == [0x4f, 0x01] + le32(UInt32(type)))
        }
    }

    @Test func inviteByName() throws {
        let data = try bytes(PacketFactory.CZ_REQ_JOIN_GUILD2(name: "Poring"))

        #expect(data == [0x16, 0x09] + field("Poring", size: 24))
    }

    @Test func inviteAnswer() throws {
        let accept = try bytes(PacketFactory.CZ_JOIN_GUILD(guildID: 7, accept: true))
        let decline = try bytes(PacketFactory.CZ_JOIN_GUILD(guildID: 7, accept: false))

        #expect(accept == [0x6b, 0x01] + le32(7) + le32(1))
        #expect(decline == [0x6b, 0x01] + le32(7) + le32(0))
    }

    @Test func leaveSendsOwnIdentifiers() throws {
        let packet = PacketFactory.CZ_REQ_LEAVE_GUILD(guildID: 7, accountID: 2_000_001, characterID: 150_000, reason: "Bye")
        let data = try bytes(packet)

        #expect(data == [0x59, 0x01] + le32(7) + le32(2_000_001) + le32(150_000) + field("Bye", size: 40))
        #expect(data.count == 54)
    }

    @Test func expelSendsMemberIdentifiers() throws {
        let packet = PacketFactory.CZ_REQ_BAN_GUILD(guildID: 7, accountID: 2_000_002, characterID: 150_001, reason: "Inactive")
        let data = try bytes(packet)

        #expect(data == [0x5b, 0x01] + le32(7) + le32(2_000_002) + le32(150_001) + field("Inactive", size: 40))
        #expect(data.count == 54)
    }

    @Test func disbandSendsGuildName() throws {
        let data = try bytes(PacketFactory.CZ_REQ_DISORGANIZE_GUILD(key: "Poring Hunters"))

        #expect(data == [0x5d, 0x01] + field("Poring Hunters", size: 40))
    }

    @Test func notice() throws {
        let data = try bytes(PacketFactory.CZ_GUILD_NOTICE(guildID: 7, subject: "Siege", notice: "Tonight"))

        #expect(data == [0x6e, 0x01] + le32(7) + field("Siege", size: 60) + field("Tonight", size: 120))
        #expect(data.count == 186)
    }

    @Test func longTextIsTruncatedToTheFieldSize() throws {
        let reason = String(repeating: "x", count: 100)
        let data = try bytes(PacketFactory.CZ_REQ_LEAVE_GUILD(guildID: 7, accountID: 1, characterID: 2, reason: reason))

        #expect(data.count == 54)
    }
}
