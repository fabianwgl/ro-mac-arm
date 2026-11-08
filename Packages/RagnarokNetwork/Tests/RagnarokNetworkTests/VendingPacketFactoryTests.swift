//
//  VendingPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  The bytes of the vending requests against what rAthena reads at PACKETVER 20211103
//  (clif_parse_VendingListReq, clif_parse_PurchaseReq2, clif_parse_PutItemToCart in clif.cpp,
//  offsets and sizes from clif_packetdb.hpp).
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Vending packet factory")
struct VendingPacketFactoryTests {
    private func bytes(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << UInt32($1 * 8) }
    }

    @Test func clickOnVendorIsSixBytes() throws {
        let data = try bytes(PacketFactory.CZ_REQ_BUY_FROMMC(vendorID: 2_000_001))
        #expect(data.count == 6)
        #expect(uint16(data, at: 0) == 0x130)
        #expect(uint32(data, at: 2) == 2_000_001)
    }

    @Test func purchaseCarriesVendorShopAndPairsOfCountThenIndex() throws {
        let packet = PacketFactory.CZ_PC_PURCHASE_ITEMLIST_FROMMC2(
            vendorID: 2_000_001,
            shopID: 9,
            purchases: [(index: 2, count: 5), (index: 7, count: 1)]
        )
        let data = try bytes(packet)

        // 0801 <packet len>.W <account id>.L <unique id>.L { <amount>.W <index>.W }*
        #expect(data.count == 20)
        #expect(uint16(data, at: 0) == 0x801)
        #expect(uint16(data, at: 2) == 20)
        #expect(uint32(data, at: 4) == 2_000_001)
        #expect(uint32(data, at: 8) == 9)
        #expect(uint16(data, at: 12) == 5)
        #expect(uint16(data, at: 14) == 2)
        #expect(uint16(data, at: 16) == 1)
        #expect(uint16(data, at: 18) == 7)
    }

    @Test func cartMovesUseIndexThenAmount() throws {
        let toCart = try bytes(PacketFactory.CZ_MOVE_ITEM_FROM_BODY_TO_CART(index: 5, amount: 30))
        #expect(toCart.count == 8)
        #expect(uint16(toCart, at: 0) == 0x126)
        #expect(uint16(toCart, at: 2) == 5)
        #expect(uint32(toCart, at: 4) == 30)

        let fromCart = try bytes(PacketFactory.CZ_MOVE_ITEM_FROM_CART_TO_BODY(index: 3, amount: 4))
        #expect(fromCart.count == 8)
        #expect(uint16(fromCart, at: 0) == 0x127)
        #expect(uint16(fromCart, at: 2) == 3)
        #expect(uint32(fromCart, at: 4) == 4)
    }

    @Test func openStoreCarriesTitleResultAndItems() throws {
        let packet = PacketFactory.CZ_REQ_OPENSTORE2(
            title: "Cheap potions",
            items: [(index: 2, amount: 20, price: 100), (index: 5, amount: 1, price: 1_000_000)]
        )
        let data = try bytes(packet)

        // 01b2 <packet len>.W <shop name>.80B <result>.B { <index>.W <amount>.W <price>.L }*
        #expect(data.count == 85 + 8 * 2)
        #expect(uint16(data, at: 0) == 0x1b2)
        #expect(uint16(data, at: 2) == 101)
        #expect(Array(data[4..<17]) == [UInt8]("Cheap potions".utf8))
        #expect(data[17] == 0)
        #expect(data[84] == 1)
        #expect(uint16(data, at: 85) == 2)
        #expect(uint16(data, at: 87) == 20)
        #expect(uint32(data, at: 89) == 100)
        #expect(uint16(data, at: 93) == 5)
        #expect(uint16(data, at: 95) == 1)
        #expect(uint32(data, at: 97) == 1_000_000)
    }

    @Test func cancellingTheSetUpHasResultZeroAndNoItems() throws {
        let data = try bytes(PacketFactory.CZ_REQ_OPENSTORE2(title: "Ignored", items: []))

        #expect(data.count == 85)
        #expect(uint16(data, at: 0) == 0x1b2)
        #expect(uint16(data, at: 2) == 85)
        #expect(data[84] == 0)
        #expect(data[4] == 0)
    }

    @Test func longTitlesAreCutToSeventyNineBytes() throws {
        let title = String(repeating: "a", count: 100)
        let data = try bytes(PacketFactory.CZ_REQ_OPENSTORE2(title: title, items: [(index: 2, amount: 1, price: 1)]))

        #expect(data.count == 93)
        #expect(Array(data[4..<83]) == [UInt8](repeating: UInt8(ascii: "a"), count: 79))
        // The 80th byte is the NUL rAthena needs.
        #expect(data[83] == 0)
    }

    @Test func titleCutNeverSplitsACharacter() throws {
        // 40 two byte characters are 80 bytes: the cut drops the last one.
        let title = String(repeating: "é", count: 40)
        let data = try bytes(PacketFactory.CZ_REQ_OPENSTORE2(title: title, items: [(index: 2, amount: 1, price: 1)]))

        let name = Array(data[4..<84]).prefix { $0 != 0 }
        #expect(String(decoding: name, as: UTF8.self) == String(repeating: "é", count: 39))
    }

    @Test func closeShopIsTwoBytes() throws {
        #expect(try bytes(PacketFactory.CZ_REQ_CLOSESTORE()) == [0x2e, 0x01])
    }
}
