//
//  VendingShopTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct VendingShopTests {
    private func makeShop() -> VendingShop {
        VendingShop(
            vendorID: 2_000_001,
            shopID: 7,
            title: "Cheap potions",
            items: [
                VendingShop.Item(index: 2, itemID: 501, price: 100, amount: 20),
                VendingShop.Item(index: 3, itemID: 1201, type: 4, price: 5_000, amount: 1, refine: 4),
                VendingShop.Item(index: 5, itemID: 502, price: 250, amount: 3),
            ]
        )
    }

    @Test func nothingIsPickedAtFirst() {
        let shop = makeShop()

        #expect(shop.totalPrice == 0)
        #expect(shop.purchases.isEmpty)
        #expect(shop.problem(zeny: 1_000_000) == .nothingSelected)
    }

    @Test func quantityIsClampedToWhatTheShopHas() {
        var shop = makeShop()

        shop.setQuantity(50, of: 2)
        #expect(shop.quantity(of: 2) == 20)

        shop.setQuantity(-4, of: 2)
        #expect(shop.quantity(of: 2) == 0)

        shop.setQuantity(2, of: 99)
        #expect(shop.quantities.isEmpty)
    }

    @Test func totalAndPurchasesFollowTheOrderOfTheShop() {
        var shop = makeShop()
        shop.setQuantity(2, of: 5)
        shop.setQuantity(10, of: 2)
        shop.setQuantity(1, of: 3)

        #expect(shop.totalPrice == 2 * 250 + 10 * 100 + 5_000)
        #expect(shop.purchases == [
            VendingShop.Purchase(index: 2, count: 10),
            VendingShop.Purchase(index: 3, count: 1),
            VendingShop.Purchase(index: 5, count: 2),
        ])
    }

    @Test func problemIsReportedForZenyAndEmptyPicks() {
        var shop = makeShop()
        shop.setQuantity(10, of: 2)

        #expect(shop.problem(zeny: 999) == .notEnoughZeny)
        #expect(shop.problem(zeny: 1_000) == nil)

        shop.setQuantity(0, of: 2)
        #expect(shop.problem(zeny: 1_000) == .nothingSelected)
    }

    @Test func maxQuantityCountsTheOtherPickedItems() {
        var shop = makeShop()

        // 1,000 zeny pay for 10 of the first item, 4 of the third.
        #expect(shop.maxQuantity(of: 2, zeny: 1_000) == 10)
        #expect(shop.maxQuantity(of: 5, zeny: 1_000) == 3)

        shop.setQuantity(3, of: 5)
        // 750 are spent on the third item: 250 left for the first.
        #expect(shop.maxQuantity(of: 2, zeny: 1_000) == 2)
        // Its own pick does not count against it.
        #expect(shop.maxQuantity(of: 5, zeny: 1_000) == 3)
        #expect(shop.maxQuantity(of: 99, zeny: 1_000) == 0)
    }

    @Test func shopIsBuiltFromTheItemListPacket() {
        var entry = PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC_sub()
        entry.price = 5_000
        entry.amount = 1
        entry.index = 3
        entry.itemType = 4
        entry.itemId = 1201
        entry.identified = 1
        entry.damaged = 0
        entry.refine = 7
        var cards = EQUIPSLOTINFO()
        cards.card = [4001, 0, 0, 0]
        entry.slot = cards

        var packet = PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC()
        packet.AID = 2_000_001
        packet.venderId = 42
        packet.items = [entry]

        let shop = VendingShop(from: packet, title: "Swords")
        #expect(shop.vendorID == 2_000_001)
        #expect(shop.shopID == 42)
        #expect(shop.title == "Swords")
        #expect(shop.items == [
            VendingShop.Item(index: 3, itemID: 1201, type: 4, price: 5_000, amount: 1, refine: 7, cards: [4001]),
        ])
    }
}

struct CartTests {
    private func normalItem(index: Int16, itemID: UInt32, count: Int16) -> NORMALITEM_INFO {
        var item = NORMALITEM_INFO()
        item.index = index
        item.ITID = itemID
        item.type = 0
        item.count = count
        return item
    }

    @Test func cartListFillsTheCart() {
        var packet = packet_itemlist_normal()
        packet.invType = UInt8(Cart.inventoryType)
        packet.list = [
            normalItem(index: 2, itemID: 501, count: 30),
            normalItem(index: 3, itemID: 502, count: 5),
        ]

        var cart = Cart()
        cart.update(from: packet)

        #expect(cart.sortedItems.map(\.index) == [2, 3])
        #expect(cart.items[2]?.itemID == 501)
        #expect(cart.items[2]?.amount == 30)
    }

    @Test func addingAnItemAddsToTheSlot() {
        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 4
        add.amount = 10
        add.itemId = 501

        var cart = Cart()
        cart.update(from: add)
        add.amount = 5
        cart.update(from: add)

        #expect(cart.items[4]?.amount == 15)
        #expect(cart.items[4]?.itemID == 501)
    }

    @Test func deletingTakesTheAmountOutAndDropsEmptySlots() {
        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 4
        add.amount = 10
        add.itemId = 501

        var cart = Cart()
        cart.update(from: add)

        var delete = PACKET_ZC_DELETE_ITEM_FROM_CART()
        delete.index = 4
        delete.amount = 4
        cart.update(from: delete)
        #expect(cart.items[4]?.amount == 6)

        delete.amount = 6
        cart.update(from: delete)
        #expect(cart.items[4] == nil)
    }

    @Test func countInfoAndCartOff() {
        var info = PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO()
        info.curCount = 3
        info.maxCount = 100
        info.curWeight = 250
        info.maxWeight = 8_000

        var cart = Cart()
        cart.update(from: info)
        #expect(cart.count == 3)
        #expect(cart.maxCount == 100)
        #expect(cart.weight == 250)
        #expect(cart.maxWeight == 8_000)

        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 2
        add.amount = 1
        add.itemId = 501
        cart.update(from: add)
        cart.clear()
        #expect(cart.items.isEmpty)
        #expect(cart.count == 0)
    }
}

/// Feeds the vending packets of rAthena (PACKETVER 20211103) to a play session without a connection.
@MainActor
struct VendingPacketHandlingTests {
    private static let accountID: UInt32 = 2_000_002
    private static let vendorID: UInt32 = 2_000_001

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
        var character = CharacterInfo()
        character.charID = 150_002
        character.name = "Buyer"

        let context = GameContext.testing
        return PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )
    }

    private func signPacket(title: String = "Cheap potions") -> PACKET_ZC_STORE_ENTRY {
        var packet = PACKET_ZC_STORE_ENTRY()
        packet.makerAID = Self.vendorID
        packet.storeName = title
        return packet
    }

    private func listPacket() -> PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC {
        var entry = PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC_sub()
        entry.price = 100
        entry.amount = 20
        entry.index = 2
        entry.itemId = 501
        entry.identified = 1

        var packet = PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC()
        packet.AID = Self.vendorID
        packet.venderId = 9
        packet.items = [entry]
        return packet
    }

    private func lastMessage(_ session: PlaySession) -> MessageCenter.Message? {
        session.messageCenter.messages.last
    }

    @Test func signAppearsAndDisappears() {
        let session = makeSession()
        #expect(session.hasVendingShop(vendorID: Self.vendorID) == false)

        #expect(session.handleVendingPacket(signPacket()))
        #expect(session.hasVendingShop(vendorID: Self.vendorID))
        #expect(session.vending.signs[Self.vendorID] == "Cheap potions")

        var disappear = PACKET_ZC_DISAPPEAR_ENTRY()
        disappear.GID = Int32(bitPattern: Self.vendorID)
        #expect(session.handleVendingPacket(disappear))
        #expect(session.hasVendingShop(vendorID: Self.vendorID) == false)
    }

    @Test func itemListOpensTheShopWithTheTitleOfTheSign() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket(title: "Cheap potions"))

        #expect(session.handleVendingPacket(listPacket()))
        #expect(session.vending.shop?.title == "Cheap potions")
        #expect(session.vending.shop?.shopID == 9)
        #expect(session.vending.shop?.items.map(\.itemID) == [501])

        session.setVendingQuantity(3, of: 2)
        #expect(session.vending.shop?.totalPrice == 300)

        session.closeVendingShopWindow()
        #expect(session.vending.shop == nil)
    }

    @Test func vendorClosingTheShopClosesTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())
        #expect(session.vending.shop != nil)

        var disappear = PACKET_ZC_DISAPPEAR_ENTRY()
        disappear.GID = Int32(bitPattern: Self.vendorID)
        _ = session.handleVendingPacket(disappear)

        #expect(session.vending.shop == nil)
        #expect(lastMessage(session)?.content == "The shop was closed.")
    }

    @Test func otherVendorsDoNotCloseTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())

        var disappear = PACKET_ZC_DISAPPEAR_ENTRY()
        disappear.GID = Int32(Self.vendorID + 5)
        _ = session.handleVendingPacket(disappear)

        #expect(session.vending.shop != nil)
        #expect(session.hasVendingShop(vendorID: Self.vendorID))
    }

    @Test func purchaseFailuresAreReported() {
        let session = makeSession()

        for (result, text) in [
            (UInt8(1), "You do not have enough zeny."),
            (2, "You cannot carry that much weight."),
            (4, "The shop does not have that many left."),
            (6, "The shop information was incorrect, nothing was bought."),
        ] {
            var packet = PACKET_ZC_PC_PURCHASE_RESULT_FROMMC()
            packet.result = result
            #expect(session.handleVendingPacket(packet))
            #expect(lastMessage(session)?.content == text)
            #expect(lastMessage(session)?.type == .error)
        }
    }

    @Test func purchaseSuccessIsSilent() {
        let session = makeSession()
        let count = session.messageCenter.messages.count

        var packet = PACKET_ZC_PC_PURCHASE_RESULT_FROMMC()
        packet.result = 0
        #expect(session.handleVendingPacket(packet))
        #expect(session.messageCenter.messages.count == count)
    }

    @Test func buyingWithoutZenyDoesNotCloseTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())
        session.setVendingQuantity(3, of: 2)
        session.playerStatus.zeny = 10

        session.purchaseFromVendingShop()

        #expect(session.vending.shop != nil)
        #expect(lastMessage(session)?.content == "You do not have enough zeny.")
    }

    @Test func buyingClosesTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())
        session.setVendingQuantity(3, of: 2)
        session.playerStatus.zeny = 1_000

        session.purchaseFromVendingShop()

        #expect(session.vending.shop == nil)
    }

    @Test func saleNoticeFindsTheItemEvenWhenTheCartSlotIsGone() {
        let session = makeSession()

        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 2
        add.amount = 5
        add.itemId = 501
        _ = session.handleVendingPacket(add)

        // rAthena empties the cart slot first, then reports the sale.
        var delete = PACKET_ZC_DELETE_ITEM_FROM_CART()
        delete.index = 2
        delete.amount = 5
        _ = session.handleVendingPacket(delete)
        #expect(session.vending.cart.items[2] == nil)

        var sold = PACKET_ZC_DELETEITEM_FROM_MCSTORE()
        sold.index = 2
        sold.amount = 5
        sold.buyerCID = 150_002
        sold.zeny = 500
        #expect(session.handleVendingPacket(sold))

        let content = lastMessage(session)?.content ?? ""
        #expect(content.hasPrefix("Sold 5 "))
        #expect(content.hasSuffix(" for 500 zeny."))
    }

    @Test func cartPacketsReachTheCart() {
        let session = makeSession()

        var start = PACKET_ZC_INVENTORY_START()
        start.invType = UInt8(Cart.inventoryType)
        #expect(session.handleVendingPacket(start))

        var list = packet_itemlist_normal()
        list.invType = UInt8(Cart.inventoryType)
        var item = NORMALITEM_INFO()
        item.index = 2
        item.ITID = 501
        item.count = 12
        list.list = [item]
        #expect(session.handleVendingPacket(list))
        #expect(session.vending.cart.items[2]?.amount == 12)

        // The inventory and the storage keep theirs.
        var inventoryList = packet_itemlist_normal()
        inventoryList.invType = 0
        #expect(session.handleVendingPacket(inventoryList) == false)
        var storageStart = PACKET_ZC_INVENTORY_START()
        storageStart.invType = 2
        #expect(session.handleVendingPacket(storageStart) == false)

        // A refresh starts the cart list over.
        #expect(session.handleVendingPacket(start))
        #expect(session.vending.cart.items.isEmpty)
    }

    @Test func mapChangeForgetsSignsAndShop() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())

        session.vending.resetForMapChange()

        #expect(session.vending.signs.isEmpty)
        #expect(session.vending.shop == nil)
    }

    @Test func unrelatedPacketsAreLeftAlone() {
        let session = makeSession()
        #expect(session.handleVendingPacket(PACKET_ZC_PING_LIVE()) == false)
    }
}
