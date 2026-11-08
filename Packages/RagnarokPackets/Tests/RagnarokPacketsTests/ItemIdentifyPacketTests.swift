//
//  ItemIdentifyPacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Item appraisal at PACKETVER 20211103: the bytes are laid out as rAthena's clif.cpp writes them
//  (clif_item_identify_list, clif_item_identified) and as clif_parse_ItemIdentify reads them
//  (opcodes and sizes from clif_packetdb.hpp and packets.hpp).
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class ItemIdentifyPacketTests: XCTestCase {
    private func le(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8(value >> 8)]
    }

    private func decodeAll(_ bytes: [UInt8]) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return packets
    }

    func testOpcodesAtPacketVer20211103() throws {
        // Clients after 2018-03-07bRagexeRE are not shuffled, see clif_shuffle.hpp.
        XCTAssertEqual(HEADER_ZC_ITEMIDENTIFY_LIST, 0x0177)
        XCTAssertEqual(HEADER_CZ_REQ_ITEMIDENTIFY, 0x0178)
        XCTAssertEqual(HEADER_ZC_ACK_ITEMIDENTIFY, 0x0179)

        let request = try XCTUnwrap(packetDatabase.entry(forFunctionName: "clif_parse_ItemIdentify"))
        XCTAssertEqual(request.packetType, 0x0178)
        XCTAssertEqual(request.packetLength, 4)
        XCTAssertEqual(request.offsets, [0])

        XCTAssertEqual(PACKET_CZ_REQ_ITEMIDENTIFY.size, 4)
        XCTAssertEqual(PACKET_ZC_ACK_ITEMIDENTIFY.size, 5)
        XCTAssertEqual(PACKET_ZC_ITEMIDENTIFY_LIST.size, -1)
        XCTAssertTrue(registeredPackets[HEADER_ZC_ITEMIDENTIFY_LIST] == PACKET_ZC_ITEMIDENTIFY_LIST.self)
        XCTAssertTrue(registeredPackets[HEADER_ZC_ACK_ITEMIDENTIFY] == PACKET_ZC_ACK_ITEMIDENTIFY.self)
    }

    func testListCarriesTheClientIndices() throws {
        // clif_item_identify_list: 0177 <packet len>.W { <index>.W }*
        let bytes = le(0x177) + le(10) + le(2) + le(5) + le(32)
        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 1)
        let list = try XCTUnwrap(packets.first as? PACKET_ZC_ITEMIDENTIFY_LIST)
        XCTAssertEqual(list.indices, [2, 5, 32])
    }

    func testListFollowedByAnotherPacketIsFramedByItsLength() throws {
        // A list of two entries, then ZC_ACK_ITEMIDENTIFY: 0179 <index>.W <result>.B
        let bytes = le(0x177) + le(8) + le(3) + le(4) + le(0x179) + le(3) + [0]
        let packets = try decodeAll(bytes)

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_ITEMIDENTIFY_LIST)?.indices, [3, 4])
        XCTAssertEqual((packets[1] as? PACKET_ZC_ACK_ITEMIDENTIFY)?.index, 3)
    }

    func testEmptyListIsStillFramed() throws {
        let packets = try decodeAll(le(0x177) + le(4))

        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual((packets.first as? PACKET_ZC_ITEMIDENTIFY_LIST)?.indices, [])
    }

    func testAckIsFiveBytes() throws {
        // clif_item_identified: 0179 <index>.W <result>.B, 0 success and 1 failure
        let success = try XCTUnwrap(try decodeAll(le(0x179) + le(7) + [0]).first as? PACKET_ZC_ACK_ITEMIDENTIFY)
        XCTAssertEqual(success.index, 7)
        XCTAssertTrue(success.isSuccess)

        let failure = try XCTUnwrap(try decodeAll(le(0x179) + le(7) + [1]).first as? PACKET_ZC_ACK_ITEMIDENTIFY)
        XCTAssertEqual(failure.index, 7)
        XCTAssertFalse(failure.isSuccess)
    }

    func testRequestLayoutMatchesClifParseItemIdentify() throws {
        // 0178 <index>.W
        var request = PACKET_CZ_REQ_ITEMIDENTIFY()
        request.packetType = HEADER_CZ_REQ_ITEMIDENTIFY
        request.index = 9
        XCTAssertEqual([UInt8](try PacketEncoder().encode(request)), [0x78, 0x01, 0x09, 0x00])
    }

    func testCancelIsIndexMinusOne() throws {
        // The server computes server_index(-1) = 0xFFFD, which is out of range, and leaves the menu.
        XCTAssertEqual(PACKET_CZ_REQ_ITEMIDENTIFY.cancelIndex, 0xFFFF)

        var request = PACKET_CZ_REQ_ITEMIDENTIFY()
        request.packetType = HEADER_CZ_REQ_ITEMIDENTIFY
        request.index = PACKET_CZ_REQ_ITEMIDENTIFY.cancelIndex
        XCTAssertEqual([UInt8](try PacketEncoder().encode(request)), [0x78, 0x01, 0xff, 0xff])
    }
}
