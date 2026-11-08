//
//  BuyingStoreTests.swift
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

struct BuyingStoreTests {
    private func makeStore(zenyLimit: Int = 5_000) -> BuyingStore {
        BuyingStore(
            buyerID: 2_000_001,
            storeID: 7,
            title: "Buying herbs",
            zenyLimit: zenyLimit,
            items: [
                BuyingStore.Item(itemID: 506, type: 0, price: 50, amount: 20),
                BuyingStore.Item(itemID: 507, type: 0, price: 18, amount: 100),
            ]
        )
    }

    private func makeInventory() -> Inventory {
        var inventory = Inventory()

        var green = InventoryItem()
        green.index = 2
        green.itemID = 506
        green.amount = 30
        inventory.append(item: green)

        var herb = InventoryItem()
        herb.index = 3
        herb.itemID = 507
        herb.amount = 4
        inventory.append(item: herb)

        // A second slot of the herb and one with a card inside, which a buying store refuses.
        var otherHerb = InventoryItem()
        otherHerb.index = 4
        otherHerb.itemID = 507
        otherHerb.amount = 9
        inventory.append(item: otherHerb)

        var carded = InventoryItem()
        carded.index = 5
        carded.itemID = 507
        carded.amount = 1
        carded.slots = [4001, 0, 0, 0]
        inventory.append(item: carded)
        return inventory
    }

    @Test func storeIsBuiltFromTheItemListPacketWithoutBoughtOutSlots() {
        var wanted = PACKET_ZC_ACK_ITEMLIST_BUYING_STORE_sub()
        wanted.price = 50
        wanted.amount = 20
        wanted.itemType = 0
        wanted.itemId = 506
        var done = PACKET_ZC_ACK_ITEMLIST_BUYING_STORE_sub()
        done.price = 18
        done.amount = 0
        done.itemId = 507

        var packet = PACKET_ZC_ACK_ITEMLIST_BUYING_STORE()
        packet.AID = 2_000_001
        packet.storeId = 7
        packet.zenyLimit = 5_000
        packet.items = [wanted, done]

        let store = BuyingStore(from: packet, title: "Buying herbs")
        #expect(store.buyerID == 2_000_001)
        #expect(store.storeID == 7)
        #expect(store.zenyLimit == 5_000)
        #expect(store.items == [BuyingStore.Item(itemID: 506, type: 0, price: 50, amount: 20)])
    }

    @Test func sellableAmountSkipsCardedAndWornItems() {
        var inventory = makeInventory()
        #expect(BuyingStore.sellableAmount(of: 506, in: inventory) == 30)
        #expect(BuyingStore.sellableAmount(of: 507, in: inventory) == 13)

        inventory.items[4]?.equippedLocation = EquipPositions(rawValue: 1)
        #expect(BuyingStore.sellableAmount(of: 507, in: inventory) == 4)
        #expect(BuyingStore.sellableAmount(of: 999, in: inventory) == 0)
    }

    @Test func quantityIsClampedToWhatTheBuyerWants() {
        var store = makeStore()

        store.setQuantity(50, of: 506)
        #expect(store.quantity(of: 506) == 20)

        store.setQuantity(-1, of: 506)
        #expect(store.quantity(of: 506) == 0)

        store.setQuantity(3, of: 999)
        #expect(store.quantities.isEmpty)
    }

    @Test func maxQuantityFollowsWantedOwnedAndTheLimit() {
        var store = makeStore(zenyLimit: 600)

        #expect(store.maxQuantity(of: 506, owned: 30) == 12)
        #expect(store.maxQuantity(of: 506, owned: 5) == 5)
        #expect(store.maxQuantity(of: 507, owned: 1_000) == 33)

        store.setQuantity(10, of: 506)
        // 500 of the 600 are spent on the first item.
        #expect(store.maxQuantity(of: 507, owned: 1_000) == 5)
        #expect(store.maxQuantity(of: 506, owned: 30) == 12)
        #expect(store.maxQuantity(of: 999, owned: 30) == 0)
    }

    @Test func problemsAreReportedForEmptyAndOverLimitPicks() {
        var store = makeStore(zenyLimit: 100)
        #expect(store.problem() == .nothingSelected)

        store.setQuantity(2, of: 506)
        #expect(store.problem() == nil)
        #expect(store.totalPrice == 100)

        store.setQuantity(3, of: 506)
        #expect(store.problem() == .overLimit)
    }

    @Test func salesTakeFromTheFullestSlotsFirst() {
        var store = makeStore()
        let inventory = makeInventory()

        store.setQuantity(12, of: 507)
        store.setQuantity(5, of: 506)

        // The first slot of the herb holds 9, the other 4, the carded one is left alone.
        let sales = store.sales(from: inventory)
        #expect(sales == [
            BuyingStore.Sale(index: 2, itemID: 506, amount: 5),
            BuyingStore.Sale(index: 4, itemID: 507, amount: 9),
            BuyingStore.Sale(index: 3, itemID: 507, amount: 3),
        ])
    }

    @Test func salesShrinkWhenTheInventoryHoldsLess() {
        var store = makeStore()
        var inventory = makeInventory()

        store.setQuantity(20, of: 506)
        inventory.items[2]?.amount = 8

        #expect(store.sales(from: inventory) == [BuyingStore.Sale(index: 2, itemID: 506, amount: 8)])
    }

    @Test func inventoryRemoveDropsEmptySlots() {
        var inventory = makeInventory()

        inventory.remove(index: 2, amount: 10)
        #expect(inventory.items[2]?.amount == 20)

        inventory.remove(index: 2, amount: 20)
        #expect(inventory.items[2] == nil)

        inventory.remove(index: 99, amount: 1)
        #expect(inventory.items.count == 3)
    }
}

struct BuyingStoreSetupTests {
    private func makeInventory() -> Inventory {
        var inventory = Inventory()
        var green = InventoryItem()
        green.index = 2
        green.itemID = 506
        green.amount = 30
        inventory.append(item: green)

        var herb = InventoryItem()
        herb.index = 3
        herb.itemID = 507
        herb.amount = 4
        inventory.append(item: herb)
        return inventory
    }

    @Test func amountCountsWhatTheBuyerOwnsAgainstTheCap() {
        var setup = BuyingStoreSetup(slots: 2)

        setup.setAmount(20_000, for: 506, owned: 30)
        #expect(setup.amount(of: 506) == BuyingStoreSetup.maxAmount - 30)

        setup.setAmount(5, for: 506, owned: 10_000)
        #expect(setup.amount(of: 506) == 0)
    }

    @Test func priceIsClampedToTheServerLimit() {
        var setup = BuyingStoreSetup(slots: 2)

        setup.setPrice(500_000_000, for: 506)
        #expect(setup.price(of: 506) == BuyingStoreSetup.maxPrice)
    }

    @Test func problemsComeInTheOrderTheWindowShowsThem() {
        let inventory = makeInventory()
        var setup = BuyingStoreSetup(slots: 1)
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .emptyTitle)

        setup.setTitle("Herbs")
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .noItems)

        setup.setAmount(10, for: 506, owned: 30)
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .missingPrice)

        setup.setPrice(50, for: 506)
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .noZenyLimit)

        setup.zenyLimit = 20_000
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .notEnoughZeny)

        setup.zenyLimit = 500
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == nil)

        setup.setAmount(5, for: 507, owned: 4)
        setup.setPrice(18, for: 507)
        #expect(setup.problem(inventory: inventory, zeny: 10_000) == .tooManyItems(slots: 1))
    }

    @Test func itemTheBuyerDoesNotOwnIsAProblem() {
        let inventory = makeInventory()
        var setup = BuyingStoreSetup(slots: 2)
        setup.setTitle("Herbs")
        setup.setAmount(5, for: 999, owned: 0)
        setup.setPrice(10, for: 999)
        setup.zenyLimit = 100

        #expect(setup.problem(inventory: inventory, zeny: 1_000) == .notOwned)
    }

    @Test func requestItemsFollowTheItemIDOrder() {
        var setup = BuyingStoreSetup(slots: 2)
        setup.setAmount(5, for: 507, owned: 4)
        setup.setPrice(18, for: 507)
        setup.setAmount(10, for: 506, owned: 30)
        setup.setPrice(50, for: 506)

        let items = setup.requestItems
        #expect(items.map(\.itemID) == [506, 507])
        #expect(items.map(\.amount) == [10, 5])
        #expect(items.map(\.price) == [50, 18])
        #expect(setup.totalCost == 10 * 50 + 5 * 18)
    }
}

struct OwnBuyingStoreTests {
    private func makeStore() -> OwnBuyingStore {
        OwnBuyingStore(title: "Herbs", zenyLimit: 5_000, items: [
            OwnBuyingStore.Item(itemID: 506, price: 50, amount: 20),
        ])
    }

    @Test func storeIsBuiltFromTheOwnItemListPacket() {
        var entry = PACKET_ZC_MYITEMLIST_BUYING_STORE_sub()
        entry.price = 50
        entry.amount = 20
        entry.itemId = 506

        var packet = PACKET_ZC_MYITEMLIST_BUYING_STORE()
        packet.AID = 2_000_001
        packet.zenyLimit = 5_000
        packet.items = [entry]

        let store = OwnBuyingStore(from: packet, title: "Herbs")
        #expect(store.zenyLimit == 5_000)
        #expect(store.items == [OwnBuyingStore.Item(itemID: 506, price: 50, amount: 20)])
    }

    @Test func purchasesReduceTheWantedAmountAndTheLimit() {
        var store = makeStore()

        let recorded = store.recordPurchase(itemID: 506, amount: 5, zeny: 250, zenyLimit: 4_750)
        #expect(recorded)
        #expect(store.item(withID: 506)?.amount == 15)
        #expect(store.item(withID: 506)?.bought == 5)
        #expect(store.spentZeny == 250)
        #expect(store.zenyLimit == 4_750)

        let unknown = store.recordPurchase(itemID: 999, amount: 1, zeny: 1, zenyLimit: 1)
        #expect(unknown == false)
        #expect(store.spentZeny == 250)
    }
}

/// The buying store packets, fed to a play session without a connection.
@MainActor
struct BuyingStorePacketHandlingTests {
    private static let accountID: UInt32 = 2_000_002
    private static let buyerID: UInt32 = 2_000_001

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
        var character = CharacterInfo()
        character.charID = 150_002
        character.name = "Seller"

        let context = GameContext.testing
        let session = PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )

        var green = InventoryItem()
        green.index = 2
        green.itemID = 506
        green.amount = 30
        session.inventory.append(item: green)
        return session
    }

    private func signPacket() -> PACKET_ZC_BUYING_STORE_ENTRY {
        var packet = PACKET_ZC_BUYING_STORE_ENTRY()
        packet.makerAID = Self.buyerID
        packet.storeName = "Buying herbs"
        return packet
    }

    private func listPacket() -> PACKET_ZC_ACK_ITEMLIST_BUYING_STORE {
        var entry = PACKET_ZC_ACK_ITEMLIST_BUYING_STORE_sub()
        entry.price = 50
        entry.amount = 20
        entry.itemId = 506

        var packet = PACKET_ZC_ACK_ITEMLIST_BUYING_STORE()
        packet.AID = Self.buyerID
        packet.storeId = 7
        packet.zenyLimit = 5_000
        packet.items = [entry]
        return packet
    }

    private func lastMessage(_ session: PlaySession) -> MessageCenter.Message? {
        session.messageCenter.messages.last
    }

    @Test func signAppearsAndDisappears() {
        let session = makeSession()
        #expect(session.hasBuyingStore(buyerID: Self.buyerID) == false)

        #expect(session.handleVendingPacket(signPacket()))
        #expect(session.hasBuyingStore(buyerID: Self.buyerID))
        #expect(session.hasVendingShop(vendorID: Self.buyerID) == false)

        var disappear = PACKET_ZC_DISAPPEAR_BUYING_STORE_ENTRY()
        disappear.makerAID = Self.buyerID
        #expect(session.handleVendingPacket(disappear))
        #expect(session.hasBuyingStore(buyerID: Self.buyerID) == false)
    }

    @Test func itemListOpensTheStoreWithTheTitleOfTheSign() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())

        #expect(session.handleVendingPacket(listPacket()))
        #expect(session.vending.buying.store?.title == "Buying herbs")
        #expect(session.vending.buying.store?.storeID == 7)

        session.setBuyingStoreQuantity(4, of: 506)
        #expect(session.vending.buying.store?.totalPrice == 200)

        session.closeBuyingStoreWindow()
        #expect(session.vending.buying.store == nil)
    }

    @Test func buyerClosingTheStoreClosesTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())

        var disappear = PACKET_ZC_DISAPPEAR_BUYING_STORE_ENTRY()
        disappear.makerAID = Self.buyerID
        _ = session.handleVendingPacket(disappear)

        #expect(session.vending.buying.store == nil)
        #expect(lastMessage(session)?.content == "The buying store was closed.")
    }

    @Test func sellingWithNothingPickedKeepsTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())

        session.sellToBuyingStore()

        #expect(session.vending.buying.store != nil)
        #expect(lastMessage(session)?.content == "Pick the items to sell.")
    }

    @Test func sellingClosesTheWindow() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())
        session.setBuyingStoreQuantity(4, of: 506)

        session.sellToBuyingStore()

        #expect(session.vending.buying.store == nil)
    }

    @Test func soldItemsLeaveTheInventory() {
        let session = makeSession()

        var deleted = PACKET_ZC_ITEM_DELETE_BUYING_STORE(index: 2, amount: 4, price: 50)
        #expect(session.handleVendingPacket(deleted))

        #expect(session.inventory.items[2]?.amount == 26)
        let content = lastMessage(session)?.content ?? ""
        #expect(content.hasSuffix("(4) were sold at 50z."))

        deleted = PACKET_ZC_ITEM_DELETE_BUYING_STORE(index: 2, amount: 26, price: 50)
        _ = session.handleVendingPacket(deleted)
        #expect(session.inventory.items[2] == nil)
    }

    @Test func saleFailuresAreReported() {
        let session = makeSession()

        for (result, text) in [
            (UInt16(5), "The deal has failed."),
            (7, "The trade failed, because the buyer is lacking required balance."),
        ] {
            var packet = PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER()
            packet.result = result
            packet.itemId = 506
            #expect(session.handleVendingPacket(packet))
            #expect(lastMessage(session)?.content == text)
            #expect(lastMessage(session)?.type == .error)
        }

        var tooMany = PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER()
        tooMany.result = 6
        tooMany.itemId = 506
        _ = session.handleVendingPacket(tooMany)
        #expect(lastMessage(session)?.content.hasPrefix("The trade failed, because the entered amount of ") == true)
    }

    // MARK: - Own buying store

    private func fillSetup(_ session: PlaySession) {
        _ = session.handleVendingPacket(PACKET_ZC_OPEN_BUYING_STORE(slots: 2))
        session.setBuyingStoreTitle("Buying herbs")
        session.setBuyingStoreZenyLimit(1_000)
        session.setBuyingStoreAmount(20, forItemID: 506)
        session.setBuyingStorePrice(50, forItemID: 506)
        session.playerStatus.zeny = 5_000
    }

    private func ownListPacket() -> PACKET_ZC_MYITEMLIST_BUYING_STORE {
        var entry = PACKET_ZC_MYITEMLIST_BUYING_STORE_sub()
        entry.price = 50
        entry.amount = 20
        entry.itemId = 506

        var packet = PACKET_ZC_MYITEMLIST_BUYING_STORE()
        packet.AID = Self.accountID
        packet.zenyLimit = 1_000
        packet.items = [entry]
        return packet
    }

    @Test func licenseOpensTheSetUpWindow() {
        let session = makeSession()

        #expect(session.handleVendingPacket(PACKET_ZC_OPEN_BUYING_STORE(slots: 2)))
        #expect(session.vending.buying.setup?.slots == 2)
    }

    @Test func openingWaitsForTheServerAndTheStoreOpensOnItsAnswer() {
        let session = makeSession()
        fillSetup(session)

        session.openBuyingStore()
        #expect(session.vending.buying.setup?.isSending == true)
        #expect(session.vending.buying.pendingTitle == "Buying herbs")

        #expect(session.handleVendingPacket(ownListPacket()))
        #expect(session.vending.buying.own?.title == "Buying herbs")
        #expect(session.vending.buying.own?.zenyLimit == 1_000)
        #expect(session.vending.buying.setup == nil)
        #expect(session.vending.buying.signs[Self.accountID] == "Buying herbs")
    }

    @Test func incompleteSetUpIsNotSent() {
        let session = makeSession()
        _ = session.handleVendingPacket(PACKET_ZC_OPEN_BUYING_STORE(slots: 2))

        session.openBuyingStore()

        #expect(session.vending.buying.setup?.isSending == false)
        #expect(lastMessage(session)?.content == "Enter a title for the store.")
    }

    @Test func refusedStoreLeavesNothingOpen() {
        let session = makeSession()
        fillSetup(session)
        session.openBuyingStore()

        let failed = PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER(result: 1, totalWeight: 0)
        #expect(session.handleVendingPacket(failed))

        #expect(session.vending.buying.setup == nil)
        #expect(session.vending.buying.own == nil)
        #expect(lastMessage(session)?.content == "Failed to open the buying store.")
    }

    @Test func purchasesUpdateTheOwnStore() {
        let session = makeSession()
        fillSetup(session)
        session.openBuyingStore()
        _ = session.handleVendingPacket(ownListPacket())

        var update = PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE()
        update.itemId = 506
        update.amount = 5
        update.zeny = 250
        update.zenyLimit = 750
        #expect(session.handleVendingPacket(update))

        #expect(session.vending.buying.own?.item(withID: 506)?.amount == 15)
        #expect(session.vending.buying.own?.zenyLimit == 750)
        #expect(session.vending.buying.own?.spentZeny == 250)
        #expect(lastMessage(session)?.content.hasPrefix("Bought 5 ") == true)
    }

    @Test func serverClosesTheStoreWhenEverythingWasBought() {
        let session = makeSession()
        fillSetup(session)
        session.openBuyingStore()
        _ = session.handleVendingPacket(ownListPacket())

        #expect(session.handleVendingPacket(PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER(result: 4)))

        #expect(session.vending.buying.own == nil)
        #expect(session.vending.buying.signs[Self.accountID] == nil)
        #expect(lastMessage(session)?.content == "All items were purchased.")
    }

    @Test func closingTheOwnStoreRemovesTheSign() {
        let session = makeSession()
        fillSetup(session)
        session.openBuyingStore()
        _ = session.handleVendingPacket(ownListPacket())

        session.closeOwnBuyingStore()

        #expect(session.vending.buying.own == nil)
    }

    @Test func mapChangeForgetsEverything() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        _ = session.handleVendingPacket(listPacket())

        session.vending.resetForMapChange()

        #expect(session.vending.buying.signs.isEmpty)
        #expect(session.vending.buying.store == nil)
    }

    @Test func removedPlayerTakesBothSignsWithHim() {
        let session = makeSession()
        _ = session.handleVendingPacket(signPacket())
        session.vending.signs[Self.buyerID] = "Shop"

        session.vending.removeSigns(of: Self.buyerID)

        #expect(session.vending.signs.isEmpty)
        #expect(session.vending.buying.signs.isEmpty)
    }
}
