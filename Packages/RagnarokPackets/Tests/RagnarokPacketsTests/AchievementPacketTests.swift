//
//  AchievementPacketTests.swift
//  RagnarokPacketsTests
//
//  Wire layouts from rAthena src/map/clif.cpp (clif_achievement_list_all, clif_achievement_update,
//  clif_achievement_reward_ack, clif_parse_AchievementCheckReward) at PACKETVER 20211103.
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import XCTest
@testable import RagnarokPackets

final class AchievementPacketTests: XCTestCase {
    func testListDecodesHeaderAndEntries() throws {
        var data = Data()
        data.appendLE(UInt16(0xa23))
        data.appendLE(UInt16(22 + 2 * 50))
        data.appendLE(UInt32(2))
        data.appendLE(UInt32(130))
        data.appendLE(UInt16(3))
        data.appendLE(UInt32(30))
        data.appendLE(UInt32(100))
        data.appendEntry(id: 120001, completed: true, objectives: [5, 0, 0, 0, 0, 0, 0, 0, 0, 7], completedAt: 1_700_000_000, rewarded: true)
        data.appendEntry(id: 120002, completed: false, objectives: [1], completedAt: 0, rewarded: false)

        let packets = try decodeAll(data)
        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_ALL_ACH_LIST)

        XCTAssertEqual(packet.achievementCount, 2)
        XCTAssertEqual(packet.totalPoints, 130)
        XCTAssertEqual(packet.level, 3)
        XCTAssertEqual(packet.experience, 30)
        XCTAssertEqual(packet.experienceToNextLevel, 100)
        XCTAssertEqual(packet.achievements.map(\.ach_id), [120001, 120002])

        let first = packet.achievements[0]
        XCTAssertEqual(first.completed, 1)
        XCTAssertEqual(first.objective.count, 10)
        XCTAssertEqual(first.objective[0], 5)
        XCTAssertEqual(first.objective[9], 7)
        XCTAssertEqual(first.completed_at, 1_700_000_000)
        XCTAssertEqual(first.reward, 1)

        let second = packet.achievements[1]
        XCTAssertEqual(second.completed, 0)
        XCTAssertEqual(second.objective[0], 1)
        XCTAssertEqual(second.reward, 0)
    }

    func testListFramesAcrossFragments() throws {
        var data = Data()
        data.appendLE(UInt16(0xa23))
        data.appendLE(UInt16(22 + 50))
        data.appendLE(UInt32(1))
        data.appendLE(UInt32(10))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(10))
        data.appendLE(UInt32(20))
        data.appendEntry(id: 110000, completed: true, objectives: [], completedAt: 1, rewarded: false)

        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []
        for byte in data {
            try decoder.decode(from: Data([byte])) { packets.append($0) }
        }

        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual((packets.first as? PACKET_ZC_ALL_ACH_LIST)?.achievements.first?.ach_id, 110000)
    }

    func testListWithCountLargerThanLengthKeepsWhatFits() throws {
        var data = Data()
        data.appendLE(UInt16(0xa23))
        data.appendLE(UInt16(22 + 50))
        data.appendLE(UInt32(5))
        data.appendLE(UInt32(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(0))
        data.appendEntry(id: 1, completed: false, objectives: [], completedAt: 0, rewarded: false)

        let packet = try XCTUnwrap(try decodeAll(data).first as? PACKET_ZC_ALL_ACH_LIST)
        XCTAssertEqual(packet.achievements.map(\.ach_id), [1])
    }

    func testUpdateDecodesTotalsAndEntry() throws {
        var data = Data()
        data.appendLE(UInt16(0xa24))
        data.appendLE(UInt32(140))
        data.appendLE(UInt16(4))
        data.appendLE(UInt32(15))
        data.appendLE(UInt32(0))
        data.appendEntry(id: 120003, completed: true, objectives: [3], completedAt: 1_700_000_100, rewarded: false)
        XCTAssertEqual(data.count, PACKET_ZC_ACH_UPDATE.size)
        XCTAssertEqual(data.count, 66)

        let packet = try XCTUnwrap(try decodeAll(data).first as? PACKET_ZC_ACH_UPDATE)
        XCTAssertEqual(packet.totalPoints, 140)
        XCTAssertEqual(packet.level, 4)
        XCTAssertEqual(packet.experience, 15)
        XCTAssertEqual(packet.experienceToNextLevel, 0)
        XCTAssertEqual(packet.achievement.ach_id, 120003)
        XCTAssertEqual(packet.achievement.completed, 1)
        XCTAssertEqual(packet.achievement.objective[0], 3)
        XCTAssertEqual(packet.achievement.completed_at, 1_700_000_100)
        XCTAssertEqual(packet.achievement.reward, 0)
    }

    func testUpdateWithoutAchievementIsAllZero() throws {
        var data = Data()
        data.appendLE(UInt16(0xa24))
        data.appendLE(UInt32(10))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(10))
        data.appendLE(UInt32(20))
        data.append(Data(count: 50))

        let packet = try XCTUnwrap(try decodeAll(data).first as? PACKET_ZC_ACH_UPDATE)
        XCTAssertEqual(packet.achievement.ach_id, 0)
        XCTAssertEqual(packet.achievement.completed, 0)
    }

    func testRewardAck() throws {
        var data = Data()
        data.appendLE(UInt16(0xa26))
        data.append(1)
        data.appendLE(UInt32(120001))
        XCTAssertEqual(data.count, PACKET_ZC_REQ_ACH_REWARD_ACK.size)

        let packet = try XCTUnwrap(try decodeAll(data).first as? PACKET_ZC_REQ_ACH_REWARD_ACK)
        XCTAssertEqual(packet.result, 1)
        XCTAssertEqual(packet.achievementID, 120001)
    }

    func testRewardRequestBytes() throws {
        var packet = PACKET_CZ_REQ_ACH_REWARD()
        packet.achievementID = 120001

        let data = try PacketEncoder().encode(packet)
        // 0a25 <achievementID>.L, 6 bytes (clif_packetdb.hpp: parseable_packet(0x0A25,6,...)).
        XCTAssertEqual([UInt8](data), [0x25, 0x0a, 0xc1, 0xd4, 0x01, 0x00])
    }

    private func decodeAll(_ data: Data) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: data) { packets.append($0) }
        return packets
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    /// One 50 byte entry: id.L completed.B objective[10].L completedAt.L rewarded.B
    mutating func appendEntry(id: UInt32, completed: Bool, objectives: [UInt32], completedAt: UInt32, rewarded: Bool) {
        appendLE(id)
        append(completed ? 1 : 0)
        for index in 0..<10 {
            appendLE(index < objectives.count ? objectives[index] : 0)
        }
        appendLE(completedAt)
        append(rewarded ? 1 : 0)
    }
}
