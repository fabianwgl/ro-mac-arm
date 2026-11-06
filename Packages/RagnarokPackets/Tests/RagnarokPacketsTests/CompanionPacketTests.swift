//
//  CompanionPacketTests.swift
//  RagnarokPacketsTests
//
//  Pet and homunculus packets at PACKETVER 20211103 (rAthena d4b8e7b8): the bytes are laid out as
//  clif.cpp writes them (clif_sendegg, clif_send_petstatus, clif_send_petdata, clif_hominfo,
//  clif_homunculus_updatestatus, clif_send_homdata, clif_homskillinfoblock) and as the
//  clif_parse_* functions read them (offsets from the packet table).
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class CompanionPacketTests: XCTestCase {

    // MARK: - Helpers

    private func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func name(_ string: String) -> [UInt8] {
        var data = Array(string.utf8)
        data += [UInt8](repeating: 0, count: 24 - data.count)
        return data
    }

    private func decodeOne(_ data: [UInt8]) throws -> any DecodablePacket {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(data)) { packets.append($0) }
        XCTAssertEqual(packets.count, 1, "the decoder frames \(data.count) bytes as one packet")
        return try XCTUnwrap(packets.first)
    }

    private func encode(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    // MARK: - Packet table

    func testOpcodesAtPacketVer20211103() {
        // Clients after 2018-03-07bRagexeRE are not shuffled, see clif_shuffle.hpp.
        XCTAssertEqual(ENTRY_CZ_COMMAND_PET.packetType, 0x01a1)
        XCTAssertEqual(ENTRY_CZ_COMMAND_PET.packetLength, 3)
        XCTAssertEqual(ENTRY_CZ_COMMAND_PET.offsets, [2])

        XCTAssertEqual(ENTRY_CZ_RENAME_PET.packetType, 0x01a5)
        XCTAssertEqual(ENTRY_CZ_RENAME_PET.packetLength, 26)
        XCTAssertEqual(ENTRY_CZ_RENAME_PET.offsets, [2])

        XCTAssertEqual(ENTRY_CZ_SELECT_PETEGG.packetType, 0x01a7)
        XCTAssertEqual(ENTRY_CZ_SELECT_PETEGG.packetLength, 4)
        XCTAssertEqual(ENTRY_CZ_SELECT_PETEGG.offsets, [2])

        XCTAssertEqual(ENTRY_CZ_COMMAND_MER.packetType, 0x022d)
        XCTAssertEqual(ENTRY_CZ_COMMAND_MER.packetLength, 5)
        XCTAssertEqual(ENTRY_CZ_COMMAND_MER.offsets, [2, 4])

        XCTAssertEqual(ENTRY_CZ_RENAME_MER.packetType, 0x0231)
        XCTAssertEqual(ENTRY_CZ_RENAME_MER.packetLength, 26)
        XCTAssertEqual(ENTRY_CZ_RENAME_MER.offsets, [2])

        XCTAssertEqual(ENTRY_CZ_REQUEST_MOVETOOWNER.packetType, 0x0234)
        XCTAssertEqual(ENTRY_CZ_REQUEST_MOVETOOWNER.packetLength, 6)
        XCTAssertEqual(ENTRY_CZ_REQUEST_MOVETOOWNER.offsets, [2])

        XCTAssertEqual(ENTRY_CZ_CONFIG.packetType, 0x02d8)
        XCTAssertEqual(ENTRY_CZ_CONFIG.packetLength, 10)
        XCTAssertEqual(ENTRY_CZ_CONFIG.offsets, [2, 6])

        XCTAssertEqual(HEADER_ZC_PETEGG_LIST, 0x01a6)
        XCTAssertEqual(HEADER_ZC_PROPERTY_PET, 0x01a2)
        XCTAssertEqual(HEADER_ZC_CHANGESTATE_PET, 0x01a4)
        XCTAssertEqual(HEADER_ZC_PROPERTY_HOMUN, 0x0ba4)
        XCTAssertEqual(HEADER_ZC_HO_PAR_CHANGE, 0x0ba5)
        XCTAssertEqual(HEADER_ZC_CHANGESTATE_MER, 0x0230)
    }

    // MARK: - Client to server

    func testCommandPet() throws {
        var packet = PACKET_CZ_COMMAND_PET()
        packet.command = PACKET_CZ_COMMAND_PET.Command.returnToEgg.rawValue

        XCTAssertEqual(try encode(packet), [0xa1, 0x01, 0x03])
    }

    func testCommandPetValuesMatchPetMenu() {
        // pet_menu: 0 information, 1 feed, 2 performance, 3 return to egg, 4 unequip accessory.
        XCTAssertEqual(PACKET_CZ_COMMAND_PET.Command.information.rawValue, 0)
        XCTAssertEqual(PACKET_CZ_COMMAND_PET.Command.feed.rawValue, 1)
        XCTAssertEqual(PACKET_CZ_COMMAND_PET.Command.performance.rawValue, 2)
        XCTAssertEqual(PACKET_CZ_COMMAND_PET.Command.returnToEgg.rawValue, 3)
        XCTAssertEqual(PACKET_CZ_COMMAND_PET.Command.unequipAccessory.rawValue, 4)
    }

    func testRenamePet() throws {
        var packet = PACKET_CZ_RENAME_PET()
        packet.name = "Poring"

        XCTAssertEqual(try encode(packet), [0xa5, 0x01] + name("Poring"))
    }

    func testRenamePetKeepsTheNameNulTerminated() throws {
        var packet = PACKET_CZ_RENAME_PET()
        packet.name = String(repeating: "a", count: 40)

        let data = try encode(packet)
        XCTAssertEqual(data.count, 26)
        XCTAssertEqual(Array(data[2..<25]), [UInt8](repeating: 0x61, count: 23))
        XCTAssertEqual(data[25], 0)
    }

    func testSelectPetEgg() throws {
        var packet = PACKET_CZ_SELECT_PETEGG()
        packet.index = 0x1234

        XCTAssertEqual(try encode(packet), [0xa7, 0x01, 0x34, 0x12])
    }

    func testSelectPetEggDefaultsToTheCancelIndex() throws {
        // rAthena subtracts 2 and refuses an index outside the inventory, then clears the egg menu.
        XCTAssertEqual(try encode(PACKET_CZ_SELECT_PETEGG()), [0xa7, 0x01, 0xff, 0xff])
    }

    func testCommandMer() throws {
        var packet = PACKET_CZ_COMMAND_MER()
        packet.command = PACKET_CZ_COMMAND_MER.Command.feed.rawValue

        // <type>.W is always 0, then <command>.B.
        XCTAssertEqual(try encode(packet), [0x2d, 0x02, 0x00, 0x00, 0x01])
    }

    func testCommandMerValuesMatchHomMenu() {
        // hom_menu: 0 information (no effect), 1 feed, 2 delete.
        XCTAssertEqual(PACKET_CZ_COMMAND_MER.Command.information.rawValue, 0)
        XCTAssertEqual(PACKET_CZ_COMMAND_MER.Command.feed.rawValue, 1)
        XCTAssertEqual(PACKET_CZ_COMMAND_MER.Command.delete.rawValue, 2)
    }

    func testRenameMer() throws {
        var packet = PACKET_CZ_RENAME_MER()
        packet.name = "Lif"

        XCTAssertEqual(try encode(packet), [0x31, 0x02] + name("Lif"))
    }

    func testRequestMoveToOwner() throws {
        var packet = PACKET_CZ_REQUEST_MOVETOOWNER()
        packet.GID = 0x0102_0304

        XCTAssertEqual(try encode(packet), [0x34, 0x02, 0x04, 0x03, 0x02, 0x01])
    }

    func testConfig() throws {
        var packet = PACKET_CZ_CONFIG()
        packet.type = PACKET_CZ_CONFIG.ConfigType.petAutofeed.rawValue
        packet.flag = 1

        XCTAssertEqual(try encode(packet), [0xd8, 0x02, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    }

    func testConfigTypesMatchEConfigType() {
        // e_config_type: 0 equipment window, 1 call, 2 pet autofeed, 3 homunculus autofeed, 5 costumes.
        XCTAssertEqual(PACKET_CZ_CONFIG.ConfigType.openEquipmentWindow.rawValue, 0)
        XCTAssertEqual(PACKET_CZ_CONFIG.ConfigType.call.rawValue, 1)
        XCTAssertEqual(PACKET_CZ_CONFIG.ConfigType.petAutofeed.rawValue, 2)
        XCTAssertEqual(PACKET_CZ_CONFIG.ConfigType.homunculusAutofeed.rawValue, 3)
        XCTAssertEqual(PACKET_CZ_CONFIG.ConfigType.disableShowCostumes.rawValue, 5)
    }

    // MARK: - Server to client

    func testPetEggList() throws {
        // clif_sendegg: 01a6 <packet len>.W { <index>.W }*, indices are server index + 2.
        let data = bytes(HEADER_ZC_PETEGG_LIST) + bytes(Int16(10)) + bytes(UInt16(5)) + bytes(UInt16(9)) + bytes(UInt16(30))

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_PETEGG_LIST)
        XCTAssertEqual(packet.indices, [5, 9, 30])
    }

    func testEmptyPetEggList() throws {
        let data = bytes(HEADER_ZC_PETEGG_LIST) + bytes(Int16(4))

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_PETEGG_LIST)
        XCTAssertEqual(packet.indices, [])
    }

    func testPetEggListBeforeItIsComplete() throws {
        let data = bytes(HEADER_ZC_PETEGG_LIST) + bytes(Int16(8)) + bytes(UInt16(5)) + bytes(UInt16(9))
        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []

        try decoder.decode(from: Data(data.prefix(6))) { packets.append($0) }
        XCTAssertTrue(packets.isEmpty)

        try decoder.decode(from: Data(data.dropFirst(6))) { packets.append($0) }
        XCTAssertEqual((packets.first as? PACKET_ZC_PETEGG_LIST)?.indices, [5, 9])
    }

    func testPropertyPet() throws {
        // 01a2 <name>.24B <renamed>.B <level>.W <hunger>.W <intimacy>.W <accessory id>.W <class>.W
        let data = bytes(HEADER_ZC_PROPERTY_PET) + name("Poring") + [1]
            + bytes(Int16(5)) + bytes(Int16(60)) + bytes(Int16(420)) + bytes(Int16(10001)) + bytes(Int16(1002))
        XCTAssertEqual(data.count, 37)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_PROPERTY_PET)
        XCTAssertEqual(packet.szName, "Poring")
        XCTAssertEqual(packet.bModified, 1)
        XCTAssertEqual(packet.nLevel, 5)
        XCTAssertEqual(packet.nFullness, 60)
        XCTAssertEqual(packet.nRelationship, 420)
        XCTAssertEqual(packet.ITID, 10001)
        XCTAssertEqual(packet.job, 1002)
    }

    func testChangeStatePet() throws {
        // 01a4 <type>.B <id>.L <data>.L
        let data = bytes(HEADER_ZC_CHANGESTATE_PET) + [2] + bytes(Int32(0x0100_0001)) + bytes(Int32(95))
        XCTAssertEqual(data.count, 11)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_CHANGESTATE_PET)
        XCTAssertEqual(packet.type, 2)
        XCTAssertEqual(packet.GID, 0x0100_0001)
        XCTAssertEqual(packet.data, 95)
    }

    func testFeedPet() throws {
        // 01a3 <result>.B <name id>.L, 7 bytes since PACKETVER_RE_NUM 20180704.
        let data = bytes(HEADER_ZC_FEED_PET) + [1] + bytes(UInt32(537))
        XCTAssertEqual(data.count, 7)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_FEED_PET)
        XCTAssertEqual(packet.result, 1)
        XCTAssertEqual(packet.itemId, 537)
    }

    func testPropertyHomun() throws {
        // 0ba4 at PACKETVER_RE_NUM >= 20211103: HP, SP and the two counters are 32 bit, exp is 64 bit.
        var data = bytes(HEADER_ZC_PROPERTY_HOMUN) + name("Lif")
        data += [0x05]                                              // renamed, alive
        data += bytes(UInt16(12)) + bytes(UInt16(70)) + bytes(UInt16(320))  // level, hunger, intimacy
        data += bytes(UInt16(80)) + bytes(UInt16(40)) + bytes(UInt16(90)) + bytes(UInt16(4))    // atk, matk, hit, crit
        data += bytes(UInt16(20)) + bytes(UInt16(10)) + bytes(UInt16(55)) + bytes(UInt16(700))  // def, mdef, flee, amotion
        data += bytes(UInt32(900)) + bytes(UInt32(1200)) + bytes(UInt32(50)) + bytes(UInt32(80))
        data += bytes(Int64(4_000_000_000_000)) + bytes(Int64(10_000_000_000_000))
        data += bytes(UInt16(2)) + bytes(UInt16(1))                 // skill points, range
        XCTAssertEqual(data.count, 85)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_PROPERTY_HOMUN)
        XCTAssertEqual(packet.name, "Lif")
        XCTAssertEqual(packet.flags, 0x05)
        XCTAssertEqual(packet.level, 12)
        XCTAssertEqual(packet.hunger, 70)
        XCTAssertEqual(packet.intimacy, 320)
        XCTAssertEqual(packet.atk2, 80)
        XCTAssertEqual(packet.matk, 40)
        XCTAssertEqual(packet.hit, 90)
        XCTAssertEqual(packet.crit, 4)
        XCTAssertEqual(packet.def, 20)
        XCTAssertEqual(packet.mdef, 10)
        XCTAssertEqual(packet.flee, 55)
        XCTAssertEqual(packet.amotion, 700)
        XCTAssertEqual(packet.hp, 900)
        XCTAssertEqual(packet.maxHp, 1200)
        XCTAssertEqual(packet.sp, 50)
        XCTAssertEqual(packet.maxSp, 80)
        XCTAssertEqual(packet.exp, 4_000_000_000_000)
        XCTAssertEqual(packet.expNext, 10_000_000_000_000)
        XCTAssertEqual(packet.skillPoints, 2)
        XCTAssertEqual(packet.range, 1)
    }

    func testHomunculusParameterChange() throws {
        // 0ba5 <type>.W <value>.Q
        let data = bytes(HEADER_ZC_HO_PAR_CHANGE) + bytes(UInt16(5)) + bytes(UInt64(321))
        XCTAssertEqual(data.count, 12)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_HO_PAR_CHANGE)
        XCTAssertEqual(packet.type, 5)
        XCTAssertEqual(packet.value, 321)
    }

    func testChangeStateMer() throws {
        // 0230 <type>.B <state>.B <id>.L <data>.L
        let data = bytes(HEADER_ZC_CHANGESTATE_MER) + [0, 2] + bytes(UInt32(0x0100_0002)) + bytes(UInt32(88))
        XCTAssertEqual(data.count, 12)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_CHANGESTATE_MER)
        XCTAssertEqual(packet.state, 2)
        XCTAssertEqual(packet.gid, 0x0100_0002)
        XCTAssertEqual(packet.data, 88)
    }

    func testHomunculusSkillList() throws {
        // 0235 <packet len>.W { <id>.W <inf>.W <unknown>.W <level>.W <sp>.W <range>.W <name>.24B <upgradable>.B }*
        func skill(id: UInt16, level: UInt16, sp: UInt16, name skillName: String, upgradable: UInt8) -> [UInt8] {
            bytes(id) + bytes(UInt16(16)) + bytes(UInt16(0)) + bytes(level) + bytes(sp) + bytes(UInt16(9))
                + name(skillName) + [upgradable]
        }

        let entries = skill(id: 8001, level: 1, sp: 13, name: "HLIF_HEAL", upgradable: 1)
            + skill(id: 8002, level: 0, sp: 20, name: "HLIF_AVOID", upgradable: 0)
        let data = bytes(HEADER_ZC_HOSKILLINFO_LIST) + bytes(Int16(4 + entries.count)) + entries
        XCTAssertEqual(entries.count, 2 * 37)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_HOSKILLINFO_LIST)
        XCTAssertEqual(packet.skills.count, 2)
        XCTAssertEqual(packet.skills[0].id, 8001)
        XCTAssertEqual(packet.skills[0].level, 1)
        XCTAssertEqual(packet.skills[0].sp, 13)
        XCTAssertEqual(packet.skills[0].name, "HLIF_HEAL")
        XCTAssertEqual(packet.skills[0].upgradable, 1)
        XCTAssertEqual(packet.skills[1].id, 8002)
        XCTAssertEqual(packet.skills[1].upgradable, 0)
    }

    func testHomunculusSkillUpdate() throws {
        // 0239 <skill id>.W <level>.W <sp>.W <range>.W <upgradable>.B
        let data = bytes(HEADER_ZC_HOSKILLINFO_UPDATE) + bytes(UInt16(8001)) + bytes(Int16(2)) + bytes(Int16(16)) + bytes(Int16(9)) + [0]
        XCTAssertEqual(data.count, 11)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_HOSKILLINFO_UPDATE)
        XCTAssertEqual(packet.skill_id, 8001)
        XCTAssertEqual(packet.Level, 2)
        XCTAssertEqual(packet.SP, 16)
        XCTAssertEqual(packet.AttackRange, 9)
        XCTAssertEqual(packet.upgradable, 0)
    }

    func testFeedMer() throws {
        let data = bytes(HEADER_ZC_FEED_MER) + [0] + bytes(UInt32(6637))
        XCTAssertEqual(data.count, 7)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_FEED_MER)
        XCTAssertEqual(packet.result, 0)
        XCTAssertEqual(packet.itemId, 6637)
    }

    func testConfigReply() throws {
        // 02d9 <type>.L <value>.L
        let data = bytes(HEADER_ZC_CONFIG) + bytes(Int32(2)) + bytes(Int32(1))
        XCTAssertEqual(data.count, 10)

        let packet = try XCTUnwrap(try decodeOne(data) as? PACKET_ZC_CONFIG)
        XCTAssertEqual(packet.type, 2)
        XCTAssertEqual(packet.value, 1)
    }
}
