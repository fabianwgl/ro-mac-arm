//
//  TradePacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Byte level checks of the player trade packets at PACKETVER 20211103. The layouts are the ones in rAthena's
//  clif.cpp (clif_traderequest, clif_traderesponse, clif_tradeadditem, clif_tradeitemok, clif_tradedeal_lock,
//  clif_tradecancelled, clif_tradecompleted), packets.hpp and packets_struct.hpp, the sizes the ones in
//  clif_packetdb.hpp.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class TradePacketTests: XCTestCase {

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

    // MARK: - Server to client

    func testTradePacketsAreRegisteredWithRathenaSizes() {
        // (opcode, size) from clif_packetdb.hpp and the PACKET_* structs at PACKETVER 20211103.
        let expected: [(Int16, Int)] = [
            (0x1f4, 32), (0x1f5, 9), (0xb42, 62), (0xea, 5), (0xec, 3), (0xee, 2), (0xf0, 3), (0xf1, 2),
        ]
        for (opcode, size) in expected {
            guard let type = registeredPackets[opcode] else {
                XCTFail("0x\(String(opcode, radix: 16)) is not registered")
                continue
            }
            XCTAssertEqual(type.size, size, "size of 0x\(String(opcode, radix: 16))")
        }
    }

    func testRequestDecodesNameAccountIDAndLevel() throws {
        // 01f4 <nick>.24B <targetid>.L <baselvl>.W
        let bytes = le(UInt16(0x1f4)) + fixed("Poring", length: 24) + le(UInt32(2_000_001)) + le(UInt16(77))
        XCTAssertEqual(bytes.count, 32)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let request = try XCTUnwrap(packets.first as? PACKET_ZC_REQ_EXCHANGE_ITEM)
        XCTAssertEqual(request.requesterName, "Poring")
        XCTAssertEqual(request.targetId, 2_000_001)
        XCTAssertEqual(request.targetLv, 77)
    }

    func testResponseDecodesResultAccountIDAndLevel() throws {
        // 01f5 <result>.B <targetid>.L <baselvl>.W
        let bytes = le(UInt16(0x1f5)) + [3] + le(UInt32(2_000_002)) + le(UInt16(12))
        XCTAssertEqual(bytes.count, 9)

        let response = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ACK_EXCHANGE_ITEM)
        XCTAssertEqual(response.result, 3)
        XCTAssertEqual(response.targetId, 2_000_002)
        XCTAssertEqual(response.targetLv, 12)
    }

    func testPartnerItemDecodesAtTheCurrentLayout() throws {
        // 0b42 <nameid>.L <type>.B <amount>.L <identified>.B <damaged>.B <cards>.16B <options>.25B
        //      <location>.L <look>.W <refine>.B <grade>.B
        var bytes = le(UInt16(0xb42))
        bytes += le(UInt32(1201))
        bytes += [4]
        bytes += le(UInt32(1))
        bytes += [1, 0]
        bytes += le(UInt32(4001)) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0))
        bytes += [UInt8](repeating: 0, count: 25)
        bytes += le(UInt32(2)) + le(UInt16(3)) + [7, 2]
        XCTAssertEqual(bytes.count, 62)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let item = try XCTUnwrap(packets.first as? PACKET_ZC_ADD_EXCHANGE_ITEM)
        XCTAssertEqual(item.itemId, 1201)
        XCTAssertEqual(item.itemType, 4)
        XCTAssertEqual(item.amount, 1)
        XCTAssertEqual(item.identified, 1)
        XCTAssertEqual(item.damaged, 0)
        XCTAssertEqual(item.slot.card, [4001, 0, 0, 0])
        XCTAssertEqual(item.refine, 7)
        XCTAssertEqual(item.grade, 2)
    }

    func testPartnerZenyIsAnItemWithIDZero() throws {
        // clif_tradeadditem with index 0 sends a zeroed struct with only the amount set.
        var bytes = le(UInt16(0xb42)) + le(UInt32(0)) + [0] + le(UInt32(125_000))
        bytes += [UInt8](repeating: 0, count: 62 - bytes.count)

        let item = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ADD_EXCHANGE_ITEM)
        XCTAssertEqual(item.itemId, 0)
        XCTAssertEqual(item.amount, 125_000)
    }

    func testAddAckDecodesIndexAndResult() throws {
        // 00ea <index>.W <result>.B
        let ack = try XCTUnwrap(try decodeAll(le(UInt16(0xea)) + le(UInt16(7)) + [1]).first as? PACKET_ZC_ACK_ADD_EXCHANGE_ITEM)
        XCTAssertEqual(ack.index, 7)
        XCTAssertEqual(ack.result, 1)
    }

    func testLockCancelAndCompleteDecode() throws {
        let bytes = le(UInt16(0xec)) + [1] + le(UInt16(0xee)) + le(UInt16(0xf0)) + [0] + le(UInt16(0xf1))
        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 4)

        XCTAssertEqual((packets[0] as? PACKET_ZC_CONCLUDE_EXCHANGE_ITEM)?.who, 1)
        XCTAssertNotNil(packets[1] as? PACKET_ZC_CANCEL_EXCHANGE_ITEM)
        XCTAssertEqual((packets[2] as? PACKET_ZC_EXEC_EXCHANGE_ITEM)?.result, 0)
        XCTAssertNotNil(packets[3] as? PACKET_ZC_EXCHANGEITEM_UNDO)
    }

    // MARK: - Client to server

    func testRequestIsSixBytes() throws {
        var packet = PACKET_CZ_REQ_EXCHANGE_ITEM()
        packet.AID = 2_000_001
        XCTAssertEqual(try encoded(packet), le(UInt16(0xe4)) + le(UInt32(2_000_001)))
    }

    func testAnswerIsThreeBytes() throws {
        var packet = PACKET_CZ_ACK_EXCHANGE_ITEM()
        packet.result = 3
        XCTAssertEqual(try encoded(packet), [0xe6, 0x00, 3])
    }

    func testLockCancelAndExecAreTwoBytes() throws {
        XCTAssertEqual(try encoded(PACKET_CZ_CONCLUDE_EXCHANGE_ITEM()), [0xeb, 0x00])
        XCTAssertEqual(try encoded(PACKET_CZ_CANCEL_EXCHANGE_ITEM()), [0xed, 0x00])
        XCTAssertEqual(try encoded(PACKET_CZ_EXEC_EXCHANGE_ITEM()), [0xef, 0x00])
    }

    func testGeneratedAddItemIsEightBytes() throws {
        var packet = PACKET_CZ_ADD_EXCHANGE_ITEM()
        packet.packetType = HEADER_CZ_ADD_EXCHANGE_ITEM
        packet.index = 5
        packet.amount = 20
        XCTAssertEqual(try encoded(packet), le(UInt16(0xe8)) + le(UInt16(5)) + le(UInt32(20)))
    }
}
