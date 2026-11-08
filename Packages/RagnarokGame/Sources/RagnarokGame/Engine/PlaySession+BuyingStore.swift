//
//  PlaySession+BuyingStore.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokNetwork
import RagnarokPackets

/// Buying stores: players who stand on the map and buy items from whoever walks up and sells.
@Observable
final class BuyingStoreState {
    /// The titles of the signs of other players' buying stores in view, by account id of the buyer
    /// (`ZC_BUYING_STORE_ENTRY`).
    var signs: [UInt32 : String] = [:]

    /// The buying store of another player that the player is looking at, with the window open while this is not nil.
    var store: BuyingStore?

    /// The set up window, open while this is not nil. A `buyingstore` script command (an item, an NPC) opens it.
    var setup: BuyingStoreSetup?

    /// The player's own buying store, once the server opened it.
    var own: OwnBuyingStore?

    /// The title that went out with the request, which the server's answer does not repeat.
    @ObservationIgnored var pendingTitle = ""

    func resetForMapChange() {
        signs = [:]
        store = nil
        setup = nil
        own = nil
    }
}

extension PlaySession {
    /// Handles buying store packets. Returns false when the packet is not one.
    func handleBuyingStorePacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_BUYING_STORE_ENTRY:
            vending.buying.signs[packet.makerAID] = packet.storeName
        case let packet as PACKET_ZC_DISAPPEAR_BUYING_STORE_ENTRY:
            handleBuyingStoreBoardRemoved(buyerID: packet.makerAID)
        case let packet as PACKET_ZC_ACK_ITEMLIST_BUYING_STORE:
            let title = vending.buying.signs[packet.AID] ?? ""
            vending.buying.store = BuyingStore(from: packet, title: title)
        case let packet as PACKET_ZC_ITEM_DELETE_BUYING_STORE:
            handleBuyingStoreItemSold(packet)
        case let packet as PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER:
            handleBuyingStoreSaleFailure(packet)

        // The player's own buying store.
        case let packet as PACKET_ZC_OPEN_BUYING_STORE:
            vending.buying.setup = BuyingStoreSetup(slots: Int(packet.slots))
        case let packet as PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER:
            handleBuyingStoreOpenFailure(packet)
        case let packet as PACKET_ZC_MYITEMLIST_BUYING_STORE:
            handleOwnBuyingStoreOpened(packet)
        case let packet as PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE:
            handleOwnBuyingStorePurchase(packet)
        case let packet as PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER:
            handleOwnBuyingStoreClosedByServer(packet)
        default:
            return false
        }
        return true
    }

    // MARK: - Browsing and selling

    /// Asks a buyer for the item list of the store. The server answers with the list, or says nothing
    /// when the buyer is not buying any more or too far away.
    func requestBuyingStoreList(buyerID: UInt32) {
        sendPacket(PacketFactory.CZ_REQ_CLICK_TO_BUYING_STORE(buyerID: buyerID))
    }

    /// Whether the player on the map with this account id has a buying store open.
    func hasBuyingStore(buyerID: UInt32) -> Bool {
        vending.buying.signs[buyerID] != nil
    }

    func closeBuyingStoreWindow() {
        vending.buying.store = nil
    }

    func setBuyingStoreQuantity(_ quantity: Int, of itemID: Int) {
        vending.buying.store?.setQuantity(quantity, of: itemID)
    }

    /// Sends the picked items from the inventory. rAthena answers a sale that works with the removal of
    /// the items (`ZC_ITEM_DELETE_BUYING_STORE`) and the new zeny, and a sale that does not with a failure message.
    func sellToBuyingStore() {
        guard let store = vending.buying.store else {
            return
        }

        if let problem = store.problem() {
            addVendingMessage(problem.message, type: .error)
            return
        }

        if let distance = distanceToPlayer(store.buyerID), distance > BuyingStore.maxSaleDistance {
            addVendingMessage(BuyingStore.Problem.tooFarAway.message, type: .error)
            return
        }

        let sales = store.sales(from: inventory).map { (index: $0.index, itemID: $0.itemID, amount: $0.amount) }
        guard !sales.isEmpty else {
            addVendingMessage(BuyingStore.Problem.nothingSelected.message, type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_REQ_TRADE_BUYING_STORE(buyerID: store.buyerID, storeID: store.storeID, sales: sales))
        vending.buying.store = nil
    }

    /// Cells between the player and another player in view, or nil when the other one is not in view.
    private func distanceToPlayer(_ objectID: UInt32) -> Int? {
        guard let scene = mapScene, let other = scene.objects[objectID] else {
            return nil
        }
        let delta = scene.player.gridPosition &- other.gridPosition
        return max(abs(delta.x), abs(delta.y))
    }

    // MARK: - Own buying store

    func setBuyingStoreTitle(_ title: String) {
        vending.buying.setup?.setTitle(title)
    }

    func setBuyingStoreZenyLimit(_ zenyLimit: Int) {
        vending.buying.setup?.zenyLimit = max(zenyLimit, 0)
    }

    func setBuyingStoreAmount(_ amount: Int, forItemID itemID: Int) {
        let owned = inventory.items.values.filter { $0.itemID == itemID }.reduce(0) { $0 + $1.amount }
        vending.buying.setup?.setAmount(amount, for: itemID, owned: owned)
    }

    func setBuyingStorePrice(_ price: Int, forItemID itemID: Int) {
        vending.buying.setup?.setPrice(price, for: itemID)
    }

    /// Sends the store. The window stays until the server answers with the store or a refusal.
    func openBuyingStore() {
        guard var setup = vending.buying.setup, !setup.isSending else {
            return
        }

        if let problem = setup.problem(inventory: inventory, zeny: playerStatus.zeny) {
            addVendingMessage(problem.message, type: .error)
            return
        }

        vending.buying.pendingTitle = setup.title
        setup.isSending = true
        vending.buying.setup = setup
        sendPacket(PacketFactory.CZ_REQ_OPEN_BUYING_STORE(
            title: setup.title,
            zenyLimit: setup.zenyLimit,
            items: setup.requestItems
        ))
    }

    /// Closes the set up window. rAthena keeps the slots of the license until it hears the store or the cancel.
    func cancelBuyingStoreSetup() {
        guard vending.buying.setup != nil else {
            return
        }
        vending.buying.setup = nil
        sendPacket(PacketFactory.CZ_REQ_OPEN_BUYING_STORE(title: "", zenyLimit: 0, items: []))
    }

    /// Takes the player's own buying store down.
    func closeOwnBuyingStore() {
        guard vending.buying.own != nil else {
            return
        }
        vending.buying.own = nil
        sendPacket(PacketFactory.CZ_REQ_CLOSE_BUYING_STORE())
    }

    // MARK: - Packets

    private func handleBuyingStoreBoardRemoved(buyerID: UInt32) {
        vending.buying.signs.removeValue(forKey: buyerID)

        if vending.buying.store?.buyerID == buyerID {
            vending.buying.store = nil
            addVendingMessage("The buying store was closed.", type: .info)
        }
    }

    /// `ZC_ITEM_DELETE_BUYING_STORE`: the items the player sold leave the inventory here, and the notice follows.
    private func handleBuyingStoreItemSold(_ packet: PACKET_ZC_ITEM_DELETE_BUYING_STORE) {
        let index = Int(packet.index)
        let amount = Int(packet.amount)
        let itemID = inventory.items[index]?.itemID

        inventory.remove(index: index, amount: amount)

        let itemName = itemID.flatMap { messageCenter.itemInfoTable.localizedIdentifiedItemName(forItemID: $0) }
            ?? itemID.map { "item \($0)" }
            ?? "an item"
        addVendingMessage("\(itemName) (\(amount)) were sold at \(packet.price)z.", type: .system)
    }

    /// `e_buyingstore_failure` in buyingstore.cpp.
    private func handleBuyingStoreSaleFailure(_ packet: PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER) {
        let itemName = messageCenter.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(packet.itemId)) ?? "\(packet.itemId)"
        let message: String? = switch packet.result {
        case 5: "The deal has failed."
        case 6: "The trade failed, because the entered amount of \(itemName) is higher than the buyer is willing to buy."
        case 7: "The trade failed, because the buyer is lacking required balance."
        default: nil
        }
        if let message {
            addVendingMessage(message, type: .error)
        }
    }

    private func handleBuyingStoreOpenFailure(_ packet: PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER) {
        vending.buying.setup = nil
        vending.buying.own = nil

        let message: String? = switch packet.result {
        case 1: "Failed to open the buying store."
        case 2: "The items you want to buy would make you overweight. Please re-enter."
        case 8: "No sale (purchase) information available."
        default: nil
        }
        if let message {
            addVendingMessage(message, type: .error)
        }
    }

    private func handleOwnBuyingStoreOpened(_ packet: PACKET_ZC_MYITEMLIST_BUYING_STORE) {
        let store = OwnBuyingStore(from: packet, title: vending.buying.pendingTitle)
        vending.buying.own = store
        vending.buying.setup = nil
        // The server does not send the sign to its owner.
        vending.buying.signs[account.accountID] = store.title
        addVendingMessage("Your buying store \"\(store.title)\" is open.", type: .system)
    }

    /// The vendor side of a sale: someone sold `amount` of the item for `zeny` in all.
    private func handleOwnBuyingStorePurchase(_ packet: PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE) {
        let itemID = Int(packet.itemId)
        let itemName = messageCenter.itemInfoTable.localizedIdentifiedItemName(forItemID: itemID) ?? "\(itemID)"
        addVendingMessage("Bought \(packet.amount) \(itemName) for \(packet.zeny) zeny.", type: .system)

        vending.buying.own?.recordPurchase(
            itemID: itemID,
            amount: Int(packet.amount),
            zeny: Int(packet.zeny),
            zenyLimit: Int(packet.zenyLimit)
        )
    }

    /// The server closes the store when everything was bought or the zeny limit is reached.
    private func handleOwnBuyingStoreClosedByServer(_ packet: PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER) {
        vending.buying.own = nil
        vending.buying.signs.removeValue(forKey: account.accountID)

        switch packet.result {
        case 3: addVendingMessage("All items within the buy limit were purchased.", type: .info)
        case 4: addVendingMessage("All items were purchased.", type: .info)
        default: break
        }
    }
}
