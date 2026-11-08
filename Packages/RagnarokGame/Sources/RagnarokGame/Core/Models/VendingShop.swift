//
//  VendingShop.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets

/// The item list of another player's shop, with the amounts the buyer picked.
///
/// rAthena sends it as `ZC_PC_PURCHASE_ITEMLIST_FROMMC` (`clif_vendinglist`) when the buyer clicks the vendor,
/// and checks the purchase against the shop in `vending_purchasereq`.
struct VendingShop: Equatable, Sendable {
    /// One row of the shop.
    struct Item: Identifiable, Equatable, Sendable {
        /// The cart index the server uses for the item (the cart slot plus 2). The purchase sends it back.
        var index: Int
        var itemID: Int
        var type: Int
        var price: Int

        /// What is left to buy.
        var amount: Int
        var isIdentified: Bool
        var isDamaged: Bool
        var refine: Int
        var cards: [Int]

        var id: Int {
            index
        }

        init(
            index: Int,
            itemID: Int,
            type: Int = 0,
            price: Int,
            amount: Int,
            isIdentified: Bool = true,
            isDamaged: Bool = false,
            refine: Int = 0,
            cards: [Int] = []
        ) {
            self.index = index
            self.itemID = itemID
            self.type = type
            self.price = price
            self.amount = amount
            self.isIdentified = isIdentified
            self.isDamaged = isDamaged
            self.refine = refine
            self.cards = cards
        }

        init(from entry: PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC_sub) {
            self.init(
                index: Int(entry.index),
                itemID: Int(entry.itemId),
                type: Int(entry.itemType),
                price: Int(entry.price),
                amount: Int(entry.amount),
                isIdentified: entry.identified != 0,
                isDamaged: entry.damaged != 0,
                refine: Int(entry.refine),
                cards: entry.slot.card.map(Int.init).filter { $0 != 0 }
            )
        }
    }

    /// An item of the purchase request.
    struct Purchase: Equatable, Sendable {
        var index: Int
        var count: Int
    }

    enum Problem: Equatable, Sendable {
        case nothingSelected
        case notEnoughZeny
        case tooFarAway

        var message: String {
            switch self {
            case .nothingSelected: "Pick the items to buy."
            case .notEnoughZeny: "You do not have enough zeny."
            case .tooFarAway: "The shop is too far away."
            }
        }
    }

    /// `AREA_SIZE`: rAthena ignores a purchase from farther away than this (in cells) without an answer.
    static let maxPurchaseDistance = 14

    /// `MAX_VENDING`: the most different items rAthena accepts in one purchase.
    static let maxPurchaseItems = 12

    /// Account id of the vendor, which `ZC_STORE_ENTRY` and the purchase call `AID`.
    var vendorID: UInt32

    /// The id of this opening of the shop (`venderId`). The purchase is refused when the vendor closed and opened again.
    var shopID: UInt32

    var title: String
    var items: [Item]

    /// Amount picked per cart index.
    private(set) var quantities: [Int : Int] = [:]

    init(vendorID: UInt32, shopID: UInt32, title: String, items: [Item]) {
        self.vendorID = vendorID
        self.shopID = shopID
        self.title = title
        self.items = items
    }

    init(from packet: PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC, title: String) {
        self.init(
            vendorID: packet.AID,
            shopID: packet.venderId,
            title: title,
            items: packet.items.map(Item.init(from:))
        )
    }

    // MARK: - Selection

    func quantity(of index: Int) -> Int {
        quantities[index] ?? 0
    }

    /// Picks `quantity` of the item, between none and what the shop has.
    mutating func setQuantity(_ quantity: Int, of index: Int) {
        guard let item = items.first(where: { $0.index == index }) else {
            return
        }

        let quantity = min(max(quantity, 0), item.amount)
        if quantity == 0 {
            quantities.removeValue(forKey: index)
        } else {
            quantities[index] = quantity
        }
    }

    /// The most of the item the buyer can still pick: what the shop has, and what the zeny pays for
    /// next to the other picked items.
    func maxQuantity(of index: Int, zeny: Int) -> Int {
        guard let item = items.first(where: { $0.index == index }) else {
            return 0
        }
        guard item.price > 0 else {
            return item.amount
        }

        let otherTotal = totalPrice - quantity(of: index) * item.price
        let affordable = max(zeny - otherTotal, 0) / item.price
        return min(item.amount, affordable)
    }

    var totalPrice: Int {
        items.reduce(0) { $0 + quantity(of: $1.index) * $1.price }
    }

    /// The items the buyer picked, in the order of the shop.
    var purchases: [Purchase] {
        items.compactMap { item in
            let count = quantity(of: item.index)
            return count > 0 ? Purchase(index: item.index, count: count) : nil
        }
    }

    /// Why the purchase cannot go out, or nil. rAthena checks the same: zeny, a non-empty list within the limit.
    func problem(zeny: Int) -> Problem? {
        let purchases = purchases
        if purchases.isEmpty || purchases.count > Self.maxPurchaseItems {
            return .nothingSelected
        }
        if totalPrice > zeny {
            return .notEnoughZeny
        }
        return nil
    }
}
