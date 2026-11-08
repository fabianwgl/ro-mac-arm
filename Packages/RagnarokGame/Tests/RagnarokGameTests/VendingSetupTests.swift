//
//  VendingSetupTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct VendingSetupTests {
    private func makeCart() -> Cart {
        var cart = Cart()
        var potion = InventoryItem()
        potion.index = 2
        potion.itemID = 501
        potion.amount = 30
        cart.items[2] = potion

        var sword = InventoryItem()
        sword.index = 3
        sword.itemID = 1201
        sword.amount = 1
        cart.items[3] = sword
        return cart
    }

    @Test func titleIsCutAtSeventyNineBytesWithoutSplittingACharacter() {
        var setup = VendingSetup(slots: 5)

        setup.setTitle(String(repeating: "a", count: 100))
        #expect(setup.title.utf8.count == 79)

        setup.setTitle(String(repeating: "é", count: 40))
        #expect(setup.title == String(repeating: "é", count: 39))
    }

    @Test func amountIsClampedToTheCart() {
        var setup = VendingSetup(slots: 5)

        setup.setAmount(99, for: 2, available: 30)
        #expect(setup.amount(of: 2) == 30)

        setup.setAmount(-1, for: 2, available: 30)
        #expect(setup.amount(of: 2) == 0)
        #expect(setup.pickedIndices.isEmpty)
    }

    @Test func priceIsClampedToTheServerLimit() {
        var setup = VendingSetup(slots: 5)

        setup.setPrice(5_000_000_000, for: 2)
        #expect(setup.price(of: 2) == VendingSetup.maxPrice)

        setup.setPrice(0, for: 2)
        #expect(setup.price(of: 2) == 0)
    }

    @Test func problemsComeInTheOrderTheWindowShowsThem() {
        let cart = makeCart()
        var setup = VendingSetup(slots: 1)
        #expect(setup.problem(cart: cart) == .emptyTitle)

        setup.setTitle("   ")
        #expect(setup.problem(cart: cart) == .emptyTitle)

        setup.setTitle("Shop")
        #expect(setup.problem(cart: cart) == .noItems)

        setup.setAmount(5, for: 2, available: 30)
        #expect(setup.problem(cart: cart) == .missingPrice)

        setup.setPrice(100, for: 2)
        #expect(setup.problem(cart: cart) == nil)

        setup.setAmount(1, for: 3, available: 1)
        setup.setPrice(900, for: 3)
        #expect(setup.problem(cart: cart) == .tooManyItems(slots: 1))
    }

    @Test func itemThatLeftTheCartIsAProblem() {
        var cart = makeCart()
        var setup = VendingSetup(slots: 5)
        setup.setTitle("Shop")
        setup.setAmount(20, for: 2, available: 30)
        setup.setPrice(100, for: 2)
        #expect(setup.problem(cart: cart) == nil)

        cart.remove(index: 2, amount: 15)
        #expect(setup.problem(cart: cart) == .notInCart)

        cart.remove(index: 2, amount: 15)
        #expect(setup.problem(cart: cart) == .notInCart)
    }

    @Test func requestItemsFollowTheCartOrder() {
        var setup = VendingSetup(slots: 5)
        setup.setAmount(1, for: 3, available: 1)
        setup.setPrice(900, for: 3)
        setup.setAmount(10, for: 2, available: 30)
        setup.setPrice(50, for: 2)

        let items = setup.requestItems
        #expect(items.map(\.index) == [2, 3])
        #expect(items.map(\.amount) == [10, 1])
        #expect(items.map(\.price) == [50, 900])
        #expect(setup.totalValue == 10 * 50 + 900)
    }
}

struct OwnVendingShopTests {
    private func makeShop() -> OwnVendingShop {
        OwnVendingShop(title: "Potions", items: [
            OwnVendingShop.Item(index: 2, itemID: 501, price: 100, amount: 20),
            OwnVendingShop.Item(index: 6, itemID: 502, price: 900, amount: 3),
        ])
    }

    @Test func shopIsBuiltFromTheOwnItemListPacket() {
        var entry = PACKET_ZC_PC_PURCHASE_MYITEMLIST_sub()
        entry.price = 100
        entry.index = 2
        entry.amount = 20
        entry.itemId = 501
        entry.identified = 1

        var packet = PACKET_ZC_PC_PURCHASE_MYITEMLIST()
        packet.AID = 2_000_001
        packet.items = [entry]

        let shop = OwnVendingShop(from: packet, title: "Potions")
        #expect(shop.title == "Potions")
        #expect(shop.items == [OwnVendingShop.Item(index: 2, itemID: 501, price: 100, amount: 20)])
    }

    @Test func shopKeepsTheIdentifiedFlagOfTheOwnItemListPacket() {
        var entry = PACKET_ZC_PC_PURCHASE_MYITEMLIST_sub()
        entry.index = 3
        entry.amount = 1
        entry.itemId = 1201
        entry.identified = 0

        var packet = PACKET_ZC_PC_PURCHASE_MYITEMLIST()
        packet.items = [entry]

        let shop = OwnVendingShop(from: packet, title: "Knives")
        #expect(shop.item(at: 3)?.isIdentified == false)
    }

    @Test func salesReduceStockAndAddUpTheZeny() {
        var shop = makeShop()

        let recorded = shop.recordSale(index: 2, amount: 5, zeny: 500)
        #expect(recorded)
        #expect(shop.item(at: 2)?.amount == 15)
        #expect(shop.item(at: 2)?.sold == 5)
        #expect(shop.earnedZeny == 500)
        #expect(shop.isSoldOut == false)

        let unknown = shop.recordSale(index: 99, amount: 1, zeny: 1)
        #expect(unknown == false)
        #expect(shop.earnedZeny == 500)
    }

    @Test func shopIsSoldOutWhenEveryItemIs() {
        var shop = makeShop()

        shop.recordSale(index: 2, amount: 20, zeny: 2_000)
        #expect(shop.isSoldOut == false)

        shop.recordSale(index: 6, amount: 3, zeny: 2_700)
        #expect(shop.isSoldOut)
        #expect(shop.item(at: 6)?.isSoldOut == true)
        #expect(shop.earnedZeny == 4_700)
    }

    @Test func saleCannotTakeMoreThanTheStock() {
        var shop = makeShop()

        shop.recordSale(index: 6, amount: 10, zeny: 2_700)
        #expect(shop.item(at: 6)?.amount == 0)
        #expect(shop.item(at: 6)?.sold == 3)
    }
}

/// The vendor side of the packets, fed to a play session without a connection.
@MainActor
struct OwnVendingPacketHandlingTests {
    private static let accountID: UInt32 = 2_000_001

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
        var character = CharacterInfo()
        character.charID = 150_001
        character.name = "Vendor"

        let context = GameContext.testing
        let session = PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )

        var potion = InventoryItem()
        potion.index = 2
        potion.itemID = 501
        potion.amount = 30
        session.vending.cart.items[2] = potion
        return session
    }

    private func ownListPacket(amount: Int16 = 10) -> PACKET_ZC_PC_PURCHASE_MYITEMLIST {
        var entry = PACKET_ZC_PC_PURCHASE_MYITEMLIST_sub()
        entry.price = 100
        entry.index = 2
        entry.amount = amount
        entry.itemId = 501

        var packet = PACKET_ZC_PC_PURCHASE_MYITEMLIST()
        packet.AID = Self.accountID
        packet.items = [entry]
        return packet
    }

    private func soldPacket(amount: UInt16, zeny: Int32) -> PACKET_ZC_DELETEITEM_FROM_MCSTORE {
        var packet = PACKET_ZC_DELETEITEM_FROM_MCSTORE()
        packet.index = 2
        packet.amount = amount
        packet.buyerCID = 150_002
        packet.zeny = zeny
        return packet
    }

    private func fillSetup(_ session: PlaySession) {
        var open = PACKET_ZC_OPENSTORE()
        open.num = 5
        _ = session.handleVendingPacket(open)

        session.setVendingTitle("Potions")
        session.setVendingAmount(10, forCartIndex: 2)
        session.setVendingPrice(100, forCartIndex: 2)
    }

    private func openShop(_ session: PlaySession) {
        fillSetup(session)
        session.openVendingShop()
        _ = session.handleVendingPacket(ownListPacket())
        _ = session.handleVendingPacket(PACKET_ZC_ACK_OPENSTORE2())
    }

    @Test func vendingSkillOpensTheSetUpWindow() {
        let session = makeSession()
        var open = PACKET_ZC_OPENSTORE()
        open.num = 5

        #expect(session.handleVendingPacket(open))
        #expect(session.vending.setup?.slots == 5)
    }

    @Test func settingUpTheShopFollowsTheCartAmounts() {
        let session = makeSession()
        fillSetup(session)

        session.setVendingAmount(99, forCartIndex: 2)
        #expect(session.vending.setup?.amount(of: 2) == 30)
        // An index the cart does not have sells nothing.
        session.setVendingAmount(5, forCartIndex: 77)
        #expect(session.vending.setup?.amount(of: 77) == 0)
    }

    @Test func openingWaitsForTheServerAndTheShopOpensOnItsAnswer() {
        let session = makeSession()
        fillSetup(session)

        session.openVendingShop()
        #expect(session.vending.setup?.isSending == true)
        #expect(session.vending.pendingShopTitle == "Potions")
        #expect(session.vending.ownShop == nil)

        _ = session.handleVendingPacket(ownListPacket())
        #expect(session.vending.ownShop?.title == "Potions")
        #expect(session.vending.ownShop?.items.map(\.itemID) == [501])

        let ack = PACKET_ZC_ACK_OPENSTORE2()
        #expect(session.handleVendingPacket(ack))
        #expect(session.vending.setup == nil)
        #expect(session.vending.signs[Self.accountID] == "Potions")
    }

    @Test func refusedShopLeavesNothingOpen() {
        let session = makeSession()
        fillSetup(session)
        session.openVendingShop()

        var ack = PACKET_ZC_ACK_OPENSTORE2()
        ack.result = 1
        #expect(session.handleVendingPacket(ack))

        #expect(session.vending.setup == nil)
        #expect(session.vending.ownShop == nil)
        #expect(session.vending.signs[Self.accountID] == nil)
        #expect(session.messageCenter.messages.last?.content == "The shop could not be opened.")
    }

    @Test func incompleteSetUpIsNotSent() {
        let session = makeSession()
        var open = PACKET_ZC_OPENSTORE()
        open.num = 5
        _ = session.handleVendingPacket(open)

        session.openVendingShop()

        #expect(session.vending.setup?.isSending == false)
        #expect(session.messageCenter.messages.last?.content == "Enter a title for the shop.")
    }

    @Test func cancellingClosesTheWindow() {
        let session = makeSession()
        fillSetup(session)

        session.cancelVendingSetup()

        #expect(session.vending.setup == nil)
    }

    @Test func saleUpdatesTheShopAndTellsTheVendor() {
        let session = makeSession()
        openShop(session)
        #expect(session.vending.signs[Self.accountID] == "Potions")

        #expect(session.handleVendingPacket(soldPacket(amount: 4, zeny: 400)))

        #expect(session.vending.ownShop?.item(at: 2)?.amount == 6)
        #expect(session.vending.ownShop?.earnedZeny == 400)
        let content = session.messageCenter.messages.last?.content ?? ""
        #expect(content.hasPrefix("Sold 4 "))
        #expect(content.hasSuffix(" for 400 zeny."))
        #expect(session.vending.signs[Self.accountID] == "Potions")
    }

    @Test func shopClosesByItselfWhenTheLastItemSells() {
        let session = makeSession()
        openShop(session)

        _ = session.handleVendingPacket(soldPacket(amount: 10, zeny: 1_000))

        #expect(session.vending.ownShop == nil)
        #expect(session.vending.signs[Self.accountID] == nil)
        #expect(session.messageCenter.messages.last?.content == "Everything is sold, the shop is closed. It earned 1000 zeny.")
    }

    @Test func closingTheShopRemovesTheSign() {
        let session = makeSession()
        openShop(session)

        session.closeOwnVendingShop()

        #expect(session.vending.ownShop == nil)
        #expect(session.vending.signs[Self.accountID] == nil)
    }

    @Test func mapChangeForgetsTheOwnShop() {
        let session = makeSession()
        openShop(session)

        session.vending.resetForMapChange()

        #expect(session.vending.ownShop == nil)
        #expect(session.vending.setup == nil)
    }
}
