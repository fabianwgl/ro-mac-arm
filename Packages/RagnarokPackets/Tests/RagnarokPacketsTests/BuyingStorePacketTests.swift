//
//  BuyingStorePacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Byte level checks of the buying store packets at PACKETVER 20211103. The layouts are the ones in rAthena's
//  clif.cpp (clif_buyingstore_*) and packets_struct.hpp, written out here byte by byte.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class BuyingStorePacketTests: XCTestCase {

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

    // MARK: - Sign

    func testEntryAndDisappearCarryTheBuyer() throws {
        // clif_buyingstore_entry: 0814 <account id>.L <store name>.80B
        let entry = le(UInt16(0x814)) + le(UInt32(2_000_001)) + fixed("Buying herbs", length: 80)
        // clif_buyingstore_disappear_entry: 0816 <account id>.L
        let disappear = le(UInt16(0x816)) + le(UInt32(2_000_001))
        XCTAssertEqual(entry.count, 86)

        let packets = try decodeAll(entry + disappear)
        XCTAssertEqual(packets.count, 2)

        let sign = try XCTUnwrap(packets[0] as? PACKET_ZC_BUYING_STORE_ENTRY)
        XCTAssertEqual(sign.makerAID, 2_000_001)
        XCTAssertEqual(sign.storeName, "Buying herbs")
        XCTAssertEqual((packets[1] as? PACKET_ZC_DISAPPEAR_BUYING_STORE_ENTRY)?.makerAID, 2_000_001)
    }

    // MARK: - Item list

    func testItemListCarriesStoreIDAndLimit() throws {
        // clif_buyingstore_itemlist: 0818 <packet len>.W <account id>.L <store id>.L <limit zeny>.L
        // { <price>.L <amount>.W <type>.B <name id>.L }*
        var entries: [UInt8] = []
        entries += le(UInt32(50)) + le(UInt16(20)) + [0] + le(UInt32(506))
        entries += le(UInt32(18)) + le(UInt16(100)) + [0] + le(UInt32(507))
        let bytes = le(UInt16(0x818)) + le(UInt16(16 + entries.count)) + le(UInt32(2_000_001)) + le(UInt32(7)) + le(UInt32(5_000)) + entries
        XCTAssertEqual(entries.count, 22)

        let list = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ACK_ITEMLIST_BUYING_STORE)
        XCTAssertEqual(list.AID, 2_000_001)
        XCTAssertEqual(list.storeId, 7)
        XCTAssertEqual(list.zenyLimit, 5_000)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].price, 50)
        XCTAssertEqual(list.items[0].amount, 20)
        XCTAssertEqual(list.items[0].itemId, 506)
        XCTAssertEqual(list.items[1].price, 18)
        XCTAssertEqual(list.items[1].amount, 100)
        XCTAssertEqual(list.items[1].itemId, 507)
    }

    // MARK: - Selling

    func testSaleRequestLayoutMatchesClifParseReqTradeBuyingStore() throws {
        var first = PACKET_CZ_REQ_TRADE_BUYING_STORE_sub()
        first.index = 5
        first.itemId = 506
        first.amount = 3
        var second = PACKET_CZ_REQ_TRADE_BUYING_STORE_sub()
        second.index = 9
        second.itemId = 507
        second.amount = 10

        var packet = PACKET_CZ_REQ_TRADE_BUYING_STORE()
        packet.packetType = HEADER_CZ_REQ_TRADE_BUYING_STORE
        packet.packetLength = 12 + 8 * 2
        packet.AID = 2_000_001
        packet.storeId = 7
        packet.items = [first, second]

        // 0819 <packet len>.W <account id>.L <store id>.L { <index>.W <name id>.L <amount>.W }*
        let expected: [UInt8] = le(UInt16(0x819)) + le(UInt16(28)) + le(UInt32(2_000_001)) + le(UInt32(7))
            + le(UInt16(5)) + le(UInt32(506)) + le(UInt16(3))
            + le(UInt16(9)) + le(UInt32(507)) + le(UInt16(10))
        XCTAssertEqual(try encoded(packet), expected)
    }

    func testClickAndCloseAreSixAndTwoBytes() throws {
        XCTAssertEqual(try encoded(PACKET_CZ_REQ_CLICK_TO_BUYING_STORE(AID: 2_000_001)), le(UInt16(0x817)) + le(UInt32(2_000_001)))
        XCTAssertEqual(try encoded(PACKET_CZ_REQ_CLOSE_BUYING_STORE()), le(UInt16(0x815)))
    }

    func testSaleResultsAndTheDeletedItems() throws {
        // clif_buyingstore_delete_item: 081c <index>.W <amount>.W <price>.L
        let deleted = le(UInt16(0x81c)) + le(UInt16(5)) + le(UInt16(3)) + le(UInt32(50))
        // clif_buyingstore_trade_failed_seller: 0824 <result>.W <name id>.L
        let failed = le(UInt16(0x824)) + le(UInt16(7)) + le(UInt32(506))
        XCTAssertEqual(deleted.count, 10)
        XCTAssertEqual(failed.count, 8)

        let packets = try decodeAll(deleted + failed)
        XCTAssertEqual(packets.count, 2)

        let item = try XCTUnwrap(packets[0] as? PACKET_ZC_ITEM_DELETE_BUYING_STORE)
        XCTAssertEqual(item.index, 5)
        XCTAssertEqual(item.amount, 3)
        XCTAssertEqual(item.price, 50)

        let result = try XCTUnwrap(packets[1] as? PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER)
        XCTAssertEqual(result.result, 7)
        XCTAssertEqual(result.itemId, 506)
    }

    // MARK: - Own buying store

    func testSetUpWindowAndRefusal() throws {
        // clif_buyingstore_open: 0810 <slots>.B
        let open: [UInt8] = le(UInt16(0x810)) + [2]
        // clif_buyingstore_open_failed: 0812 <result>.W <total weight>.L
        let failed = le(UInt16(0x812)) + le(UInt16(2)) + le(UInt32(1_530))
        XCTAssertEqual(open.count, 3)
        XCTAssertEqual(failed.count, 8)

        let packets = try decodeAll(open + failed)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_OPEN_BUYING_STORE)?.slots, 2)
        XCTAssertEqual((packets[1] as? PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER)?.result, 2)
        XCTAssertEqual((packets[1] as? PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER)?.totalWeight, 1_530)
    }

    func testOpenRequestLayoutMatchesClifParseReqOpenBuyingStore() throws {
        var item = PACKET_CZ_REQ_OPEN_BUYING_STORE_sub()
        item.itemId = 506
        item.amount = 20
        item.price = 50

        var packet = PACKET_CZ_REQ_OPEN_BUYING_STORE()
        packet.packetType = HEADER_CZ_REQ_OPEN_BUYING_STORE
        packet.packetLength = 89 + 10
        packet.zenyLimit = 5_000
        packet.result = 1
        packet.storeName = "Buying herbs"
        packet.items = [item]

        // 0811 <packet len>.W <limit zeny>.L <result>.B <store name>.80B { <name id>.L <amount>.W <price>.L }*
        let expected: [UInt8] = le(UInt16(0x811)) + le(UInt16(99)) + le(UInt32(5_000)) + [1] + fixed("Buying herbs", length: 80)
            + le(UInt32(506)) + le(UInt16(20)) + le(UInt32(50))
        XCTAssertEqual(try encoded(packet), expected)
    }

    func testOpenedStoreAndItsPurchases() throws {
        // clif_buyingstore_myitemlist: 0813 <packet len>.W <account id>.L <limit zeny>.L
        // { <price>.L <count>.W <type>.B <name id>.L }*
        let entry = le(UInt32(50)) + le(UInt16(20)) + [0] + le(UInt32(506))
        let myItems = le(UInt16(0x813)) + le(UInt16(12 + entry.count)) + le(UInt32(2_000_001)) + le(UInt32(5_000)) + entry
        // clif_buyingstore_update_item: 09e6 <name id>.L <amount>.W <zeny>.L <limit zeny>.L <char id>.L <date>.L
        let update = le(UInt16(0x9e6)) + le(UInt32(506)) + le(UInt16(5)) + le(UInt32(250)) + le(UInt32(4_750)) + le(UInt32(150_002)) + le(UInt32(1_700_000_000))
        // clif_buyingstore_trade_failed_buyer: 081a <result>.W
        let finished = le(UInt16(0x81a)) + le(UInt16(4))
        XCTAssertEqual(update.count, 24)

        let packets = try decodeAll(myItems + update + finished)
        XCTAssertEqual(packets.count, 3)

        let mine = try XCTUnwrap(packets[0] as? PACKET_ZC_MYITEMLIST_BUYING_STORE)
        XCTAssertEqual(mine.AID, 2_000_001)
        XCTAssertEqual(mine.zenyLimit, 5_000)
        XCTAssertEqual(mine.items.count, 1)
        XCTAssertEqual(mine.items[0].itemId, 506)
        XCTAssertEqual(mine.items[0].amount, 20)
        XCTAssertEqual(mine.items[0].price, 50)

        let bought = try XCTUnwrap(packets[1] as? PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE)
        XCTAssertEqual(bought.itemId, 506)
        XCTAssertEqual(bought.amount, 5)
        XCTAssertEqual(bought.zeny, 250)
        XCTAssertEqual(bought.zenyLimit, 4_750)
        XCTAssertEqual(bought.charId, 150_002)

        XCTAssertEqual((packets[2] as? PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER)?.result, 4)
    }
}
