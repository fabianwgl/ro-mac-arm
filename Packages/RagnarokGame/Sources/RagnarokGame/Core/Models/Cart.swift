//
//  Cart.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokConstants
import RagnarokModels
import RagnarokPackets

/// The pushcart of a Merchant, which is where vending takes its items from.
///
/// rAthena sends the cart as the item lists of inventory type 1 (`clif_cartlist`), then one packet for every
/// change. The indices are the ones the shop packets use as well: the cart slot plus 2 (`client_index`).
struct Cart: Sendable {
    /// Inventory type of the cart in `ZC_INVENTORY_START` and the item lists.
    static let inventoryType = 1

    /// `MAX_CART` in mmo.hpp.
    static let capacity = 100

    var items: [Int : InventoryItem] = [:]

    /// Whether the player has a cart. rAthena sends the cart list and the cart counts when a cart is put on and
    /// `ZC_CARTOFF` when it is taken off, so the packets are the only source. Without a cart the server drops
    /// every move to or from it.
    var isActive = false

    var count = 0
    var maxCount = Cart.capacity
    var weight = 0
    var maxWeight = 0

    var sortedItems: [InventoryItem] {
        items.values.sorted()
    }

    mutating func update(from packet: packet_itemlist_normal) {
        for item in packet.list.map(InventoryItem.init(from:)) {
            items[item.index] = item
        }
    }

    mutating func update(from packet: packet_itemlist_equip) {
        for item in packet.list.map(InventoryItem.init(from:)) {
            items[item.index] = item
        }
    }

    mutating func update(from packet: PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO) {
        isActive = true
        count = Int(packet.curCount)
        maxCount = Int(packet.maxCount)
        weight = Int(packet.curWeight)
        maxWeight = Int(packet.maxWeight)
    }

    /// `amount` is the amount that was added, not the new total.
    mutating func update(from packet: PACKET_ZC_ADD_ITEM_TO_CART) {
        let index = Int(packet.index)
        let amount = Int(packet.amount)

        if var item = items[index] {
            item.amount += amount
            items[index] = item
        } else {
            var item = InventoryItem()
            item.index = index
            item.itemID = Int(packet.itemId)
            item.type = ItemType(rawValue: Int(packet.itemType)) ?? .etc
            item.amount = amount
            item.slots = packet.slot.card.map(Int.init)
            items[index] = item
        }
    }

    /// `amount` is the amount that was taken out.
    mutating func update(from packet: PACKET_ZC_DELETE_ITEM_FROM_CART) {
        remove(index: Int(packet.index), amount: Int(packet.amount))
    }

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

    /// `ZC_CARTOFF`: rAthena sends it when the cart is taken off, and for `@clearcart`, which sends the cart counts
    /// right after, so the cart is active again.
    mutating func clear() {
        items = [:]
        isActive = false
        count = 0
    }
}
