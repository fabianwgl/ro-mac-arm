//
//  GuildPacketTests.swift
//  RagnarokPacketsTests
//
//  Byte level checks of the guild packets the client sends and decodes. The byte layouts are written out by hand
//  from rAthena d4b8e7b8 (src/map/packets.hpp, packets_struct.hpp, clif.cpp) at PACKETVER 20211103.
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import XCTest
@testable import RagnarokPackets

final class GuildPacketTests: XCTestCase {

    // MARK: - Byte builders

    private func le16(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
    }

    private func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xff) }
    }

    /// A zero padded fixed size string field, the way rAthena's safestrncpy leaves it.
    private func field(_ text: String, size: Int) -> [UInt8] {
        let bytes = Array(text.utf8)
        return bytes + [UInt8](repeating: 0, count: size - bytes.count)
    }

    private func encode(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func decodeAll(_ bytes: [UInt8]) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return packets
    }

    // MARK: - Registry

    func testGuildPacketsAreRegistered() {
        // clif_guild_memberlogin_notice, clif_guild_positionchanged, clif_guild_memberpositionchanged
        XCTAssertTrue(registeredPackets[0x01f2] == PACKET_ZC_UPDATE_CHARSTAT.self)
        XCTAssertTrue(registeredPackets[0x0174] == PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO.self)
        XCTAssertTrue(registeredPackets[0x0156] == PACKET_ZC_ACK_REQ_CHANGE_MEMBERS.self)
    }

    func testGuildPacketSizes() {
        // sizeof() of the structs rAthena sends at this PACKETVER.
        XCTAssertEqual(PACKET_ZC_UPDATE_CHARSTAT.size, 20)
        XCTAssertEqual(PACKET_ZC_UPDATE_GDID.size, 43)
        XCTAssertEqual(PACKET_ZC_GUILD_INFO.size, 118)
        XCTAssertEqual(GUILD_MEMBER_INFO.size, 58)
        XCTAssertEqual(PACKET_ZC_BAN_LIST_sub.size, 68)
        XCTAssertEqual(PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO_sub.size, 40)
        XCTAssertEqual(PACKET_ZC_ACK_REQ_CHANGE_MEMBERS_sub.size, 12)
        XCTAssertEqual(PACKET_ZC_ACK_LEAVE_GUILD2.size, 46)
        XCTAssertEqual(PACKET_ZC_ACK_BAN_GUILD3.size, 46)
        XCTAssertEqual(PACKET_ZC_GUILD_NOTICE.size, 182)
    }

    // MARK: - ZC_UPDATE_CHARSTAT (0x01f2)

    func testDecodeUpdateCharStat() throws {
        // 01f2 <account id>.L <char id>.L <status>.L <gender>.W <hair style>.W <hair color>.W
        var bytes = le16(0x01f2)
        bytes += le32(2_000_001)
        bytes += le32(150_000)
        bytes += le32(1)
        bytes += le16(1) + le16(12) + le16(3)
        XCTAssertEqual(bytes.count, 20)

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_UPDATE_CHARSTAT)
        XCTAssertEqual(packet.aid, 2_000_001)
        XCTAssertEqual(packet.cid, 150_000)
        XCTAssertEqual(packet.status, 1)
        XCTAssertEqual(packet.gender, 1)
        XCTAssertEqual(packet.hairStyle, 12)
        XCTAssertEqual(packet.hairColor, 3)
    }

    // MARK: - ZC_ACK_CHANGE_GUILD_POSITIONINFO (0x0174)

    private func positionInfoEntry(id: UInt32, mode: UInt32, ranking: UInt32, payRate: UInt32, name: String) -> [UInt8] {
        le32(id) + le32(mode) + le32(ranking) + le32(payRate) + field(name, size: 24)
    }

    func testDecodePositionInfoChange() throws {
        // 0174 <packet len>.W { <position id>.L <mode>.L <ranking>.L <pay rate>.L <position name>.24B }*
        let entries = positionInfoEntry(id: 3, mode: 0x11, ranking: 3, payRate: 25, name: "Officer")
            + positionInfoEntry(id: 4, mode: 0x01, ranking: 4, payRate: 0, name: "Recruiter")
        var bytes = le16(0x0174) + le16(4 + entries.count)
        bytes += entries

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO)
        XCTAssertEqual(packet.posInfo.count, 2)
        XCTAssertEqual(packet.posInfo[0].positionID, 3)
        XCTAssertEqual(packet.posInfo[0].mode, 0x11)
        XCTAssertEqual(packet.posInfo[0].ranking, 3)
        XCTAssertEqual(packet.posInfo[0].payRate, 25)
        XCTAssertEqual(packet.posInfo[0].posName, "Officer")
        XCTAssertEqual(packet.posInfo[1].positionID, 4)
        XCTAssertEqual(packet.posInfo[1].posName, "Recruiter")
    }

    func testDecodeSinglePositionInfoChangeFollowedByAnotherPacket() throws {
        // rAthena sends one packet per changed position (clif_guild_positionchanged), several can arrive at once.
        let entry = positionInfoEntry(id: 1, mode: 0x01, ranking: 1, payRate: 10, name: "Member")
        var bytes = le16(0x0174) + le16(4 + entry.count) + entry
        bytes += le16(0x0174) + le16(4 + entry.count) + entry

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 2)
        XCTAssertTrue(packets.allSatisfy { $0 is PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO })
    }

    func testPositionInfoChangeSurvivesEverySplitPoint() throws {
        let entry = positionInfoEntry(id: 1, mode: 0x01, ranking: 1, payRate: 10, name: "Member")
        let bytes = le16(0x0174) + le16(4 + entry.count) + entry

        for splitIndex in 0...bytes.count {
            let decoder = PacketDecoder()
            var packets: [any DecodablePacket] = []
            try decoder.decode(from: Data(bytes.prefix(splitIndex))) { packets.append($0) }
            try decoder.decode(from: Data(bytes.dropFirst(splitIndex))) { packets.append($0) }
            XCTAssertEqual(packets.count, 1, "split at \(splitIndex)")
        }
    }

    // MARK: - ZC_ACK_REQ_CHANGE_MEMBERS (0x0156)

    func testDecodeMemberPositionChange() throws {
        // 0156 <packet len>.W { <account id>.L <char id>.L <position id>.L }*
        var bytes = le16(0x0156) + le16(4 + 12)
        bytes += le32(2_000_002) + le32(150_001) + le32(5)

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_REQ_CHANGE_MEMBERS)
        XCTAssertEqual(packet.members.count, 1)
        XCTAssertEqual(packet.members[0].accId, 2_000_002)
        XCTAssertEqual(packet.members[0].charId, 150_001)
        XCTAssertEqual(packet.members[0].positionID, 5)
    }

    // MARK: - ZC_MEMBERMGR_INFO (0x0b7d) and ZC_GUILD_INFO (0x0b7b)

    func testDecodeMemberManagerInfo() throws {
        // 0b7d <packet len>.W { <account>.L <char id>.L <hair style>.W <hair color>.W <gender>.W <class>.W
        //                       <level>.W <contrib exp>.L <state>.L <position>.L <lastlogin>.L <name>.24B }*
        var entry = le32(2_000_001) + le32(150_000)
        entry += le16(12) + le16(3) + le16(1) + le16(7) + le16(45)
        entry += le32(1200) + le32(1) + le32(0) + le32(1_700_000_000)
        entry += field("Leon", size: 24)
        XCTAssertEqual(entry.count, 58)
        let bytes = le16(0x0b7d) + le16(4 + entry.count) + entry

        let packets = try decodeAll(bytes)

        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_MEMBERMGR_INFO)
        XCTAssertEqual(packet.guildMemberInfo.count, 1)
        let member = packet.guildMemberInfo[0]
        XCTAssertEqual(member.AID, 2_000_001)
        XCTAssertEqual(member.GID, 150_000)
        XCTAssertEqual(member.job, 7)
        XCTAssertEqual(member.level, 45)
        XCTAssertEqual(member.contributionExp, 1200)
        XCTAssertEqual(member.currentState, 1)
        XCTAssertEqual(member.positionID, 0)
        XCTAssertEqual(member.lastLoginTime, 1_700_000_000)
        XCTAssertEqual(member.char_name, "Leon")
    }

    func testDecodeGuildInfo() throws {
        // 0b7b <guild id>.L <level>.L <member num>.L <member max>.L <average level>.L <exp>.L <max exp>.L
        //      <points>.L <honor>.L <virtue>.L <emblem id>.L <name>.24B <manage land>.16B <zeny>.L
        //      <master char id>.L <master name>.24B
        var bytes = le16(0x0b7b)
        bytes += le32(7) + le32(5) + le32(2) + le32(26) + le32(61) + le32(300) + le32(1200)
        bytes += le32(0) + le32(0) + le32(0) + le32(3)
        bytes += field("Poring Hunters", size: 24) + field("Valkyrie", size: 16)
        bytes += le32(0) + le32(150_000) + field("Leon", size: 24)
        XCTAssertEqual(bytes.count, 118)

        let packets = try decodeAll(bytes)

        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_GUILD_INFO)
        XCTAssertEqual(packet.GDID, 7)
        XCTAssertEqual(packet.level, 5)
        XCTAssertEqual(packet.userNum, 2)
        XCTAssertEqual(packet.maxUserNum, 26)
        XCTAssertEqual(packet.userAverageLevel, 61)
        XCTAssertEqual(packet.exp, 300)
        XCTAssertEqual(packet.maxExp, 1200)
        XCTAssertEqual(packet.emblemVersion, 3)
        XCTAssertEqual(packet.guildname, "Poring Hunters")
        XCTAssertEqual(packet.manageLand, "Valkyrie")
        XCTAssertEqual(packet.masterGID, 150_000)
        XCTAssertEqual(packet.masterName, "Leon")
    }

    // MARK: - Expulsion and leaving (0x0a82, 0x0a83)

    func testDecodeLeaveAndExpulsion() throws {
        // 0a83 <char id>.L <reason>.40B (clif_guild_leave)
        // 0a82 <reason>.40B <char id>.L (PACKET_ZC_ACK_BAN_GUILD3, the field order of the struct rAthena sends)
        var bytes = le16(0x0a83) + le32(150_001) + field("Bye", size: 40)
        bytes += le16(0x0a82) + field("Inactive", size: 40) + le32(150_002)

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 2)
        let leave = try XCTUnwrap(packets[0] as? PACKET_ZC_ACK_LEAVE_GUILD2)
        XCTAssertEqual(leave.GID, 150_001)
        XCTAssertEqual(leave.reason, "Bye")
        let ban = try XCTUnwrap(packets[1] as? PACKET_ZC_ACK_BAN_GUILD3)
        XCTAssertEqual(ban.GID, 150_002)
        XCTAssertEqual(ban.reason, "Inactive")
    }

    // MARK: - Client to server

    func testEncodeRequestMakeGuild() throws {
        // 0165 <char id>.L <guild name>.24B
        var packet = PACKET_CZ_REQ_MAKE_GUILD()
        packet.GID = 150_000
        packet.guildName = "Poring Hunters"

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x0165) + le32(150_000) + field("Poring Hunters", size: 24))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x0165]!.packetLength))
    }

    func testEncodeRequestGuildMenuInterface() throws {
        // 014d
        let bytes = try encode(PACKET_CZ_REQ_GUILD_MENUINTERFACE())

        XCTAssertEqual(bytes, le16(0x014d))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x014d]!.packetLength))
    }

    func testEncodeRequestGuildMenu() throws {
        // 014f <type>.L
        var packet = PACKET_CZ_REQ_GUILD_MENU()
        packet.type = 4

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x014f) + le32(4))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x014f]!.packetLength))
    }

    func testEncodeGuildNotice() throws {
        // 016e <guild id>.L <subject>.60B <notice>.120B
        var packet = PACKET_CZ_GUILD_NOTICE()
        packet.guildID = 7
        packet.subject = "Siege tonight"
        packet.notice = "Meet at the portal."

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x016e) + le32(7) + field("Siege tonight", size: 60) + field("Meet at the portal.", size: 120))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x016e]!.packetLength))
    }

    func testEncodeGuildInviteByName() throws {
        // 0916 <char name>.24B
        var packet = PACKET_CZ_REQ_JOIN_GUILD2()
        packet.packetType = HEADER_CZ_REQ_JOIN_GUILD2
        packet.name = "Poring"

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x0916) + field("Poring", size: 24))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x0916]!.packetLength))
    }

    func testEncodeGuildInviteAnswer() throws {
        // 016b <guild id>.L <answer>.L
        var packet = PACKET_CZ_JOIN_GUILD()
        packet.packetType = HEADER_CZ_JOIN_GUILD
        packet.guild_id = 7
        packet.answer = 1

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x016b) + le32(7) + le32(1))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x016b]!.packetLength))
    }

    func testEncodeLeaveAndExpel() throws {
        // 0159 <guild id>.L <account id>.L <char id>.L <reason>.40B
        // 015b <guild id>.L <account id>.L <char id>.L <reason>.40B
        var leave = PACKET_CZ_REQ_LEAVE_GUILD()
        leave.packetType = HEADER_CZ_REQ_LEAVE_GUILD
        leave.guild_id = 7
        leave.AID = 2_000_001
        leave.CID = 150_000
        leave.message = "Bye"

        var expel = PACKET_CZ_REQ_BAN_GUILD()
        expel.packetType = HEADER_CZ_REQ_BAN_GUILD
        expel.guild_id = 7
        expel.AID = 2_000_002
        expel.CID = 150_001
        expel.message = "Inactive"

        let leaveBytes = try encode(leave)
        let expelBytes = try encode(expel)

        XCTAssertEqual(leaveBytes, le16(0x0159) + le32(7) + le32(2_000_001) + le32(150_000) + field("Bye", size: 40))
        XCTAssertEqual(expelBytes, le16(0x015b) + le32(7) + le32(2_000_002) + le32(150_001) + field("Inactive", size: 40))
        XCTAssertEqual(leaveBytes.count, Int(packetDatabase.entriesByPacketType[0x0159]!.packetLength))
        XCTAssertEqual(expelBytes.count, Int(packetDatabase.entriesByPacketType[0x015b]!.packetLength))
    }

    func testEncodeDisbandGuild() throws {
        // 015d <key>.40B, the key is the guild name
        var packet = PACKET_CZ_REQ_DISORGANIZE_GUILD()
        packet.packetType = HEADER_CZ_REQ_DISORGANIZE_GUILD
        packet.key = "Poring Hunters"

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x015d) + field("Poring Hunters", size: 40))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x015d]!.packetLength))
    }
}
