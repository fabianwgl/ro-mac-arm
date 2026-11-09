//
//  GuildExtrasPacketTests.swift
//  RagnarokPacketsTests
//
//  Byte level checks of the guild skill, emblem, position editing and alliance packets. The layouts are written out
//  by hand from rAthena (src/map/packets.hpp, packets_struct.hpp, clif.cpp, clif_packetdb.hpp) at PACKETVER 20211103.
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import XCTest
@testable import RagnarokPackets

final class GuildExtrasPacketTests: XCTestCase {

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

    // MARK: - ZC_GUILD_SKILLINFO (0x0162)

    /// `<skill id>.W <type>.L <level>.W <sp cost>.W <attack range>.W <skill name>.24B <upgradable>.B`
    private func skillEntry(id: Int, inf: UInt32, level: Int, sp: Int, range: Int, name: String, upFlag: UInt8) -> [UInt8] {
        le16(id) + le32(inf) + le16(level) + le16(sp) + le16(range) + field(name, size: 24) + [upFlag]
    }

    func testGuildSkillDataSize() {
        XCTAssertEqual(GUILD_SKILLDATA.size, 37)
    }

    func testDecodeGuildSkillInfo() throws {
        // 0162 <packet len>.W <skill points>.W { <skill entry> }*
        var entries = skillEntry(id: 10000, inf: 0, level: 3, sp: 0, range: 0, name: "GD_APPROVAL", upFlag: 1)
        entries += skillEntry(id: 10013, inf: 4, level: 1, sp: 100, range: 9, name: "GD_EMERGENCYCALL", upFlag: 0)
        let bytes = le16(0x0162) + le16(6 + entries.count) + le16(2) + entries

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_GUILD_SKILLINFO)
        XCTAssertEqual(packet.skillPoint, 2)
        XCTAssertEqual(packet.skillInfo.count, 2)
        XCTAssertEqual(packet.skillInfo[0].id, 10000)
        XCTAssertEqual(packet.skillInfo[0].inf, 0)
        XCTAssertEqual(packet.skillInfo[0].level, 3)
        XCTAssertEqual(packet.skillInfo[0].name, "GD_APPROVAL")
        XCTAssertEqual(packet.skillInfo[0].upFlag, 1)
        XCTAssertEqual(packet.skillInfo[1].id, 10013)
        XCTAssertEqual(packet.skillInfo[1].inf, 4)
        XCTAssertEqual(packet.skillInfo[1].sp, 100)
        XCTAssertEqual(packet.skillInfo[1].range2, 9)
        XCTAssertEqual(packet.skillInfo[1].name, "GD_EMERGENCYCALL")
        XCTAssertEqual(packet.skillInfo[1].upFlag, 0)
    }

    func testGuildSkillInfoWithoutSkillsDecodes() throws {
        // A guild whose skills are all hidden by guild_check_skill_require still gets the point count.
        let bytes = le16(0x0162) + le16(6) + le16(5)

        let packet = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_GUILD_SKILLINFO)

        XCTAssertEqual(packet.skillPoint, 5)
        XCTAssertTrue(packet.skillInfo.isEmpty)
    }

    func testGuildSkillUpIsTheNormalSkillUpPacket() throws {
        // rAthena routes 0112 <skill id>.W to guild_skillup when the id is in the guild skill range (pc_skillup).
        var packet = PACKET_CZ_UPGRADE_SKILLLEVEL()
        packet.skillId = 10013

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x0112) + le16(10013))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x0112]!.packetLength))
    }

    // MARK: - Guild emblem (0x0151, 0x0152, 0x0153)

    func testEncodeEmblemRequest() throws {
        // 0151 <guild id>.L
        var packet = PACKET_CZ_REQ_GUILD_EMBLEM_IMG1()
        packet.packetType = HEADER_CZ_REQ_GUILD_EMBLEM_IMG1
        packet.guild_id = 7

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x0151) + le32(7))
        XCTAssertEqual(bytes.count, Int(packetDatabase.entriesByPacketType[0x0151]!.packetLength))
    }

    func testDecodeEmblem() throws {
        // clif_guild_emblem: 0152 <packet len>.W <guild id>.L <emblem id>.L <emblem data>.?B, at every PACKETVER.
        let data: [UInt8] = [0x78, 0x9c, 0x00, 0xff, 0x10]
        let bytes = le16(0x0152) + le16(12 + data.count) + le32(7) + le32(3) + data

        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY)
        XCTAssertEqual(packet.guildID, 7)
        XCTAssertEqual(packet.emblemID, 3)
        XCTAssertEqual(packet.data, data)
    }

    func testDecodeEmblemWithoutDataThenNextPacket() throws {
        // The decoder must stop at the length field so the packet behind it still decodes.
        let empty = le16(0x0152) + le16(12) + le32(7) + le32(3)
        let skills = le16(0x0162) + le16(6) + le16(5)

        let packets = try decodeAll(empty + skills)

        XCTAssertEqual(packets.count, 2)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_GUILD_EMBLEM_IMG_LEGACY)
        XCTAssertTrue(packet.data.isEmpty)
        XCTAssertTrue(packets.last is PACKET_ZC_GUILD_SKILLINFO)
    }

    func testEncodeEmblemUpload() throws {
        // clif_parse_GuildChangeEmblem: 0153 <packet len>.W <emblem data>.?B, the length covers the header.
        var packet = PACKET_CZ_REGISTER_GUILD_EMBLEM_IMG()
        packet.data = [0x78, 0x9c, 0x01, 0x02]

        let bytes = try encode(packet)

        XCTAssertEqual(bytes, le16(0x0153) + le16(8) + [0x78, 0x9c, 0x01, 0x02])
        XCTAssertEqual(packetDatabase.entriesByPacketType[0x0153]!.packetLength, -1)
    }
}
