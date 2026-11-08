//
//  BuyingStore.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets

extension Inventory {
    /// Takes `amount` out of the slot and drops the slot when it is empty.
    mutating func remove(index: Int, amount: Int) {
        guard amount > 0, var item = items[index] else {
            return
        }

        item.amount -= amount
        if item.amount > 0 {
            items[index] = item
        } else {
            items.removeValue(forKey: index)
        }
    }
}

/// Another player's buying store, with the amounts the seller picked.
///
/// rAthena sends it as `ZC_ACK_ITEMLIST_BUYING_STORE` (`clif_buyingstore_itemlist`) and checks the sale in
/// `buyingstore_trade`.
struct BuyingStore: Equatable, Sendable {
    /// One thing the buyer wants.
    struct Item: Identifiable, Equatable, Sendable {
        var itemID: Int
        var type: Int

        /// What the buyer pays for each.
        var price: Int

        /// How many the buyer still wants.
        var amount: Int

        var id: Int {
            itemID
        }
    }

    /// One inventory slot of the sale. `index` is the slot the server uses (`CZ_REQ_TRADE_BUYING_STORE`).
    struct Sale: Equatable, Sendable {
        var index: Int
        var itemID: Int
        var amount: Int
    }

    enum Problem: Equatable, Sendable {
        case nothingSelected
        case overLimit
        case tooFarAway

        var message: String {
            switch self {
            case .nothingSelected: "Pick the items to sell."
            case .overLimit: "The buyer cannot pay that much."
            case .tooFarAway: "The buying store is too far away."
            }
        }
    }

    /// `AREA_SIZE`: rAthena ignores a sale from farther away than this (in cells) with a failure message.
    static let maxSaleDistance = 14

    /// Account id of the buyer, which `ZC_BUYING_STORE_ENTRY` and the sale call `AID`.
    var buyerID: UInt32

    /// The id of this opening of the store. The sale is refused when the buyer closed and opened again.
    var storeID: UInt32

    var title: String

    /// The zeny the buyer still has for buying.
    var zenyLimit: Int

    var items: [Item]

    /// Amount picked per item id.
    private(set) var quantities: [Int : Int] = [:]

    init(buyerID: UInt32, storeID: UInt32, title: String, zenyLimit: Int, items: [Item]) {
        self.buyerID = buyerID
        self.storeID = storeID
        self.title = title
        self.zenyLimit = zenyLimit
        self.items = items
    }

    init(from packet: PACKET_ZC_ACK_ITEMLIST_BUYING_STORE, title: String) {
        self.init(
            buyerID: packet.AID,
            storeID: packet.storeId,
            title: title,
            zenyLimit: Int(packet.zenyLimit),
            // rAthena lists the slots that were bought out as well, with no amount.
            items: packet.items.compactMap { entry in
                guard entry.amount > 0 else {
                    return nil
                }
                return Item(itemID: Int(entry.itemId), type: Int(entry.itemType), price: Int(entry.price), amount: Int(entry.amount))
            }
        )
    }

    // MARK: - Inventory

    /// The slots of the inventory that can go to a buying store: not worn, and with no card inside
    /// (rAthena refuses carded items). Fullest first.
    static func sellableStacks(of itemID: Int, in inventory: Inventory) -> [InventoryItem] {
        inventory.items.values
            .filter { $0.itemID == itemID && !$0.isEquipped && $0.slots.allSatisfy { $0 == 0 } }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.index < $1.index }
    }

    /// How many of the item the seller can sell.
    static func sellableAmount(of itemID: Int, in inventory: Inventory) -> Int {
        sellableStacks(of: itemID, in: inventory).reduce(0) { $0 + $1.amount }
    }

    // MARK: - Selection

    func quantity(of itemID: Int) -> Int {
        quantities[itemID] ?? 0
    }

    /// Picks `quantity` of the item, between none and what the buyer wants.
    mutating func setQuantity(_ quantity: Int, of itemID: Int) {
        guard let item = items.first(where: { $0.itemID == itemID }) else {
            return
        }

        let quantity = min(max(quantity, 0), item.amount)
        if quantity == 0 {
            quantities.removeValue(forKey: itemID)
        } else {
            quantities[itemID] = quantity
        }
    }

    /// The most of the item that can still be picked: what the buyer wants, what the seller owns, and what
    /// the zeny limit pays for next to the other picked items.
    func maxQuantity(of itemID: Int, owned: Int) -> Int {
        guard let item = items.first(where: { $0.itemID == itemID }) else {
            return 0
        }

        var limit = min(item.amount, owned)
        if item.price > 0 {
            let otherTotal = totalPrice - quantity(of: itemID) * item.price
            limit = min(limit, max(zenyLimit - otherTotal, 0) / item.price)
        }
        return limit
    }

    /// What the seller would be paid.
    var totalPrice: Int {
        items.reduce(0) { $0 + quantity(of: $1.itemID) * $1.price }
    }

    func problem() -> Problem? {
        if quantities.isEmpty {
            return .nothingSelected
        }
        if totalPrice > zenyLimit {
            return .overLimit
        }
        return nil
    }

    /// The inventory slots to send for the picked items, in the order of the store. An item the seller
    /// no longer has enough of yields less than picked.
    func sales(from inventory: Inventory) -> [Sale] {
        var sales: [Sale] = []
        for item in items {
            var remaining = quantity(of: item.itemID)
            for stack in Self.sellableStacks(of: item.itemID, in: inventory) where remaining > 0 {
                let amount = min(stack.amount, remaining)
                sales.append(Sale(index: stack.index, itemID: item.itemID, amount: amount))
                remaining -= amount
            }
        }
        return sales
    }
}
