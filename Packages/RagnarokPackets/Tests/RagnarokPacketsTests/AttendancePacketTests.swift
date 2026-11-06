//
//  AttendancePacketTests.swift
//  RagnarokPacketsTests
//
//  Golden bytes for the attendance packets, laid out as rAthena's clif.cpp writes and reads them
//  (`clif_ui_open`, `clif_enchantwindow_open`, `clif_attendence_response`,
//  `clif_parse_open_ui`, `clif_parse_attendance_request`).
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import XCTest
@testable import RagnarokPackets

final class AttendancePacketTests: XCTestCase {
    func testUIOpenForAttendance() throws {
        // 0AE2 <type>.B <data>.L with type OUT_UI_ATTENDANCE (7) and data 10 * 5 days + rewarded today.
        let packets = try decode([0xe2, 0x0a, 0x07, 0x33, 0x00, 0x00, 0x00])

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_UI_OPEN)
        XCTAssertEqual(packet.packetType, HEADER_ZC_UI_OPEN)
        XCTAssertEqual(packet.UIType, 7)
        XCTAssertEqual(packet.data, 51)
    }

    func testUIOpenV3ForEnchant() throws {
        // 0B9A <type>.B <data>.Q with type OUT_UI_ENCHANT (10).
        let packets = try decode([0x9a, 0x0b, 0x0a, 0xd2, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_UI_OPEN_V3)
        XCTAssertEqual(packet.packetType, HEADER_ZC_UI_OPEN_V3)
        XCTAssertEqual(packet.type, 10)
        XCTAssertEqual(packet.data, 1234)
    }

    func testCheckAttendanceAcknowledgement() throws {
        // 0AF0 <unknown>.L <data>.L; the server writes 0 and the rewarded day count.
        let packets = try decode([0xf0, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00])

        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_CHECK_ATTENDANCE)
        XCTAssertEqual(packet.packetType, HEADER_ZC_ACK_CHECK_ATTENDANCE)
        XCTAssertEqual(packet.unknown, 0)
        XCTAssertEqual(packet.rewardedDays, 4)
    }

    func testCheckAttendanceAcknowledgementSplitAcrossReads() throws {
        let bytes: [UInt8] = [0xf0, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00]
        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []
        for byte in bytes {
            try decoder.decode(from: Data([byte])) { packets.append($0) }
        }

        XCTAssertEqual((packets.first as? PACKET_ZC_ACK_CHECK_ATTENDANCE)?.rewardedDays, 20)
    }

    func testRequestCheckAttendanceEncoding() throws {
        // 0AEF, no fields.
        let data = try PacketEncoder().encode(PACKET_CZ_REQ_CHECK_ATTENDANCE())

        XCTAssertEqual([UInt8](data), [0xef, 0x0a])
    }

    func testOpenUIEncoding() throws {
        // 0A68 <type>.B with IN_UI_ATTENDANCE (5).
        var packet = PACKET_CZ_OPEN_UI()
        packet.packetType = HEADER_CZ_OPEN_UI
        packet.UIType = 5

        let data = try PacketEncoder().encode(packet)

        XCTAssertEqual([UInt8](data), [0x68, 0x0a, 0x05])
    }

    func testPacketSizesMatchRAthenaTable() {
        XCTAssertEqual(PACKET_ZC_UI_OPEN.size, 7)
        XCTAssertEqual(PACKET_ZC_UI_OPEN_V3.size, 11)
        XCTAssertEqual(PACKET_ZC_ACK_CHECK_ATTENDANCE.size, 10)
        XCTAssertEqual(PACKET_CZ_REQ_CHECK_ATTENDANCE.size, 2)
        XCTAssertEqual(PACKET_CZ_OPEN_UI.size, 3)

        XCTAssertEqual(packetDatabase.entriesByPacketType[HEADER_ZC_ACK_CHECK_ATTENDANCE]?.packetLength, 10)
        XCTAssertEqual(packetDatabase.entriesByPacketType[HEADER_CZ_REQ_CHECK_ATTENDANCE]?.packetLength, 2)
        XCTAssertEqual(packetDatabase.entriesByPacketType[HEADER_CZ_OPEN_UI]?.packetLength, 3)
    }

    private func decode(_ bytes: [UInt8]) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return packets
    }
}
