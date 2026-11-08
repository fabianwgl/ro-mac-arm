//
//  VendingPacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Byte level checks of the vending packets at PACKETVER 20211103. The layouts are the ones in rAthena's
//  clif.cpp (clif_showvendingboard, clif_vendinglist, clif_buyvending, clif_vendingreport, ...) and
//  packets_struct.hpp, written out here byte by byte instead of through the Swift structs.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class VendingPacketTests: XCTestCase {

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

    /// One entry of 0xb3d, as clif_vendinglist writes it: 64 bytes.
    private func listEntry(
        price: UInt32,
        amount: UInt16,
        index: UInt16,
        type: UInt8,
        itemID: UInt32,
        identified: UInt8 = 1,
        damaged: UInt8 = 0,
        cards: [UInt32] = [0, 0, 0, 0],
        refine: UInt8 = 0
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += le(price)
        bytes += le(amount)
        bytes += le(index)
        bytes += [type]
        bytes += le(itemID)
        bytes += [identified, damaged]
        bytes += cards.flatMap { le($0) }
        bytes += [UInt8](repeating: 0, count: 5 * 5)
        bytes += le(UInt32(0))
        bytes += le(UInt16(0))
        bytes += [refine, 0]
        return bytes
    }

    private func listPacket(vendorID: UInt32, shopID: UInt32, entries: [[UInt8]]) -> [UInt8] {
        let body = le(vendorID) + le(shopID) + entries.flatMap { $0 }
        return le(UInt16(0xb3d)) + le(UInt16(body.count + 4)) + body
    }

    // MARK: - Shop sign

    func testStoreEntryCarriesTheVendorAndTheTitle() throws {
        let bytes = le(UInt16(0x131)) + le(UInt32(2_000_001)) + fixed("Cheap potions", length: 80)
        XCTAssertEqual(bytes.count, 86)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let entry = try XCTUnwrap(packets.first as? PACKET_ZC_STORE_ENTRY)
        XCTAssertEqual(entry.makerAID, 2_000_001)
        XCTAssertEqual(entry.storeName, "Cheap potions")
    }

    func testDisappearEntryIsSixBytes() throws {
        let bytes = le(UInt16(0x132)) + le(UInt32(2_000_001))
        let packets = try decodeAll(bytes + bytes)

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_DISAPPEAR_ENTRY)?.GID, 2_000_001)
        XCTAssertEqual((packets[1] as? PACKET_ZC_DISAPPEAR_ENTRY)?.GID, 2_000_001)
    }

    // MARK: - Item list

    func testShopItemListReadsEveryEntry() throws {
        let bytes = listPacket(vendorID: 2_000_001, shopID: 7, entries: [
            listEntry(price: 100, amount: 20, index: 2, type: 0, itemID: 501),
            listEntry(price: 5_000, amount: 1, index: 3, type: 4, itemID: 1201, cards: [4001, 0, 0, 0], refine: 7),
        ])
        XCTAssertEqual(bytes.count, 12 + 64 * 2)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let list = try XCTUnwrap(packets.first as? PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC)
        XCTAssertEqual(list.packetType, HEADER_ZC_PC_PURCHASE_ITEMLIST_FROMMC)
        XCTAssertEqual(list.AID, 2_000_001)
        XCTAssertEqual(list.venderId, 7)
        XCTAssertEqual(list.items.count, 2)

        XCTAssertEqual(list.items[0].price, 100)
        XCTAssertEqual(list.items[0].amount, 20)
        XCTAssertEqual(list.items[0].index, 2)
        XCTAssertEqual(list.items[0].itemType, 0)
        XCTAssertEqual(list.items[0].itemId, 501)

        XCTAssertEqual(list.items[1].price, 5_000)
        XCTAssertEqual(list.items[1].index, 3)
        XCTAssertEqual(list.items[1].itemType, 4)
        XCTAssertEqual(list.items[1].itemId, 1201)
        XCTAssertEqual(list.items[1].slot.card, [4001, 0, 0, 0])
        XCTAssertEqual(list.items[1].refine, 7)
    }

    func testShopItemListWithoutItemsIsStillFramed() throws {
        let closing: [UInt8] = le(UInt16(0x132)) + le(UInt32(9))
        let packets = try decodeAll(listPacket(vendorID: 9, shopID: 1, entries: []) + closing)

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC)?.items.count, 0)
        XCTAssertEqual((packets[1] as? PACKET_ZC_DISAPPEAR_ENTRY)?.GID, 9)
    }

    // MARK: - Purchase

    func testPurchaseResultIsSevenBytes() throws {
        // clif_buyvending: <index>.W <amount>.W <result>.B
        let bytes = le(UInt16(0x135)) + le(UInt16(3)) + le(UInt16(2)) + [4]
        XCTAssertEqual(bytes.count, 7)

        let result = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_PC_PURCHASE_RESULT_FROMMC)
        XCTAssertEqual(result.index, 3)
        XCTAssertEqual(result.amount, 2)
        XCTAssertEqual(result.result, 4)
    }

    func testPurchaseRequestLayoutMatchesClifParsePurchaseReq2() throws {
        var packet = PACKET_CZ_PC_PURCHASE_ITEMLIST_FROMMC2()
        packet.packetType = HEADER_CZ_PC_PURCHASE_ITEMLIST_FROMMC2
        packet.packetLength = 12 + 4 * 2
        packet.AID = 2_000_001
        packet.UniqueID = 7
        packet.list = [
            CZ_PURCHASE_ITEM_FROMMC(count: 5, index: 2),
            CZ_PURCHASE_ITEM_FROMMC(count: 1, index: 3),
        ]

        // 0801 <packet len>.W <account id>.L <unique id>.L { <amount>.W <index>.W }*
        let expected: [UInt8] = le(UInt16(0x801)) + le(UInt16(20)) + le(UInt32(2_000_001)) + le(UInt32(7))
            + le(UInt16(5)) + le(UInt16(2))
            + le(UInt16(1)) + le(UInt16(3))
        XCTAssertEqual(try encoded(packet), expected)
    }

    // MARK: - Click on a vendor

    func testClickOnVendorIsSixBytes() throws {
        let data = try encoded(PACKET_CZ_REQ_BUY_FROMMC(AID: 2_000_001))
        XCTAssertEqual(data, le(UInt16(0x130)) + le(UInt32(2_000_001)))
    }
}

private extension CZ_PURCHASE_ITEM_FROMMC {
    init(count: Int16, index: Int16) {
        self.init()
        self.count = count
        self.index = index
    }
}
