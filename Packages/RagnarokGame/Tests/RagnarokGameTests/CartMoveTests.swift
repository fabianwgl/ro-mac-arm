//
//  CartMoveTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokConstants
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Whether the inventory menu offers "Move to cart" follows the cart packets.
@MainActor
struct CartMoveTests {
    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = 2_000_011
        var character = CharacterInfo()
        character.charID = 150_011
        character.name = "Hauler"

        let context = GameContext.testing
        return PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )
    }

    private func potions(amount: Int = 5) -> InventoryItem {
        var item = InventoryItem()
        item.index = 3
        item.itemID = 501
        item.type = .healing
        item.amount = amount
        return item
    }

    private func countInfo() -> PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO {
        var info = PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO()
        info.curCount = 0
        info.maxCount = 100
        info.curWeight = 0
        info.maxWeight = 8_000
        return info
    }

    @Test func noCartAtFirst() {
        let session = makeSession()

        #expect(session.vending.cart.isActive == false)
        #expect(session.canMoveToCart(potions()) == false)
    }

    @Test func cartCountsMakeTheCartActive() {
        let session = makeSession()

        #expect(session.handleVendingPacket(countInfo()))

        #expect(session.vending.cart.isActive)
        #expect(session.canMoveToCart(potions()))
    }

    @Test func cartItemListMakesTheCartActive() {
        let session = makeSession()

        var start = PACKET_ZC_INVENTORY_START()
        start.invType = UInt8(Cart.inventoryType)
        #expect(session.handleVendingPacket(start))

        #expect(session.vending.cart.isActive)
    }

    @Test func theInventoryItemListDoesNotMakeACart() {
        let session = makeSession()

        var start = PACKET_ZC_INVENTORY_START()
        start.invType = 0
        #expect(session.handleVendingPacket(start) == false)

        #expect(session.vending.cart.isActive == false)
    }

    @Test func takingTheCartOffClosesIt() {
        let session = makeSession()
        _ = session.handleVendingPacket(countInfo())

        #expect(session.handleVendingPacket(PACKET_ZC_CARTOFF()))

        #expect(session.vending.cart.isActive == false)
        #expect(session.canMoveToCart(potions()) == false)
    }

    @Test func equippedItemsStayOut() {
        let session = makeSession()
        _ = session.handleVendingPacket(countInfo())

        var sword = InventoryItem()
        sword.index = 6
        sword.itemID = 1101
        sword.type = .weapon
        sword.amount = 1
        sword.equippedLocation = .right_hand

        #expect(sword.isEquipped)
        #expect(session.canMoveToCart(sword) == false)

        sword.equippedLocation = EquipPositions(rawValue: 0)
        #expect(session.canMoveToCart(sword))
    }

    @Test func emptyStacksAreNotOffered() {
        let session = makeSession()
        _ = session.handleVendingPacket(countInfo())

        #expect(session.canMoveToCart(potions(amount: 0)) == false)
    }

    @Test func movedItemShowsUpInTheCart() {
        let session = makeSession()
        _ = session.handleVendingPacket(countInfo())

        // The server answers a move with the item in the cart and fewer in the inventory.
        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 2
        add.amount = 3
        add.itemId = 501
        _ = session.handleVendingPacket(add)
        #expect(session.vending.cart.items[2]?.amount == 3)

        var delete = PACKET_ZC_DELETE_ITEM_FROM_CART()
        delete.index = 2
        delete.amount = 3
        _ = session.handleVendingPacket(delete)
        #expect(session.vending.cart.items[2] == nil)
        #expect(session.vending.cart.isActive)
    }
}
