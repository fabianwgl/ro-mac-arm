//
//  BuyingStoreSetup.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets

/// The buying store set up window (`ZC_OPEN_BUYING_STORE`): what to buy, how many and for how much each,
/// the most zeny to spend, and the title of the store.
///
/// The limits are rAthena's, from `buyingstore_create`: `BUYINGSTORE_MAX_PRICE`, `BUYINGSTORE_MAX_AMOUNT`
/// (counted together with what the buyer already owns), the slots the license gives and the title bytes.
struct BuyingStoreSetup: Equatable, Sendable {
    enum Problem: Equatable, Sendable {
        case emptyTitle
        case noItems
        case tooManyItems(slots: Int)
        case missingPrice
        case notOwned
        case noZenyLimit
        case notEnoughZeny

        var message: String {
            switch self {
            case .emptyTitle: "Enter a title for the store."
            case .noItems: "Pick the items to buy."
            case .tooManyItems(let slots): "The store can hold \(slots) different items."
            case .missingPrice: "Set a price for every item."
            case .notOwned: "You need to own at least one of every item you buy."
            case .noZenyLimit: "Set the most zeny to spend."
            case .notEnoughZeny: "You do not have that much zeny."
            }
        }
    }

    /// Bytes of the title without the NUL. `MESSAGE_SIZE` is 80.
    static let maxTitleBytes = 79

    /// `BUYINGSTORE_MAX_PRICE`.
    static let maxPrice = 99_990_000

    /// `BUYINGSTORE_MAX_AMOUNT`: the amount to buy plus what the buyer owns.
    static let maxAmount = 9_999

    /// How many different items the store takes (`ZC_OPEN_BUYING_STORE`'s `slots`).
    let slots: Int

    private(set) var title = ""
    var zenyLimit = 0

    /// Amount to buy per item id.
    private(set) var amounts: [Int : Int] = [:]
    private(set) var prices: [Int : Int] = [:]

    /// The request went out and the server has not answered yet.
    var isSending = false

    init(slots: Int) {
        self.slots = slots
    }

    // MARK: - Editing

    mutating func setTitle(_ title: String) {
        var title = title
        while title.utf8.count > Self.maxTitleBytes {
            title.removeLast()
        }
        self.title = title
    }

    /// Buys `amount` of the item. `owned` is what the buyer has, which counts against `maxAmount`.
    mutating func setAmount(_ amount: Int, for itemID: Int, owned: Int) {
        let amount = min(max(amount, 0), max(Self.maxAmount - owned, 0))
        if amount == 0 {
            amounts.removeValue(forKey: itemID)
        } else {
            amounts[itemID] = amount
        }
    }

    mutating func setPrice(_ price: Int, for itemID: Int) {
        let price = min(max(price, 0), Self.maxPrice)
        if price == 0 {
            prices.removeValue(forKey: itemID)
        } else {
            prices[itemID] = price
        }
    }

    func amount(of itemID: Int) -> Int {
        amounts[itemID] ?? 0
    }

    func price(of itemID: Int) -> Int {
        prices[itemID] ?? 0
    }

    // MARK: - Request

    var pickedItemIDs: [Int] {
        amounts.keys.sorted()
    }

    /// What the store would spend if everything sells.
    var totalCost: Int {
        pickedItemIDs.reduce(0) { $0 + amount(of: $1) * price(of: $1) }
    }

    func problem(inventory: Inventory, zeny: Int) -> Problem? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }

        let picked = pickedItemIDs
        if picked.isEmpty {
            return .noItems
        }
        if picked.count > slots {
            return .tooManyItems(slots: slots)
        }
        for itemID in picked {
            if price(of: itemID) <= 0 {
                return .missingPrice
            }
            if !inventory.items.values.contains(where: { $0.itemID == itemID }) {
                return .notOwned
            }
        }
        if zenyLimit <= 0 {
            return .noZenyLimit
        }
        if zenyLimit > zeny {
            return .notEnoughZeny
        }
        return nil
    }

    /// The items of `CZ_REQ_OPEN_BUYING_STORE`.
    var requestItems: [(itemID: Int, amount: Int, price: Int)] {
        pickedItemIDs.map { (itemID: $0, amount: amount(of: $0), price: price(of: $0)) }
    }
}

/// The player's own buying store, once the server opened it (`ZC_MYITEMLIST_BUYING_STORE`).
struct OwnBuyingStore: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        var itemID: Int
        var price: Int

        /// How many are still wanted.
        var amount: Int

        /// How many were bought since the store opened.
        var bought = 0

        var id: Int {
            itemID
        }
    }

    var title: String
    private(set) var items: [Item]

    /// The zeny the store may still spend.
    private(set) var zenyLimit: Int

    /// The zeny spent so far.
    private(set) var spentZeny = 0

    init(title: String, zenyLimit: Int, items: [Item]) {
        self.title = title
        self.zenyLimit = zenyLimit
        self.items = items
    }

    init(from packet: PACKET_ZC_MYITEMLIST_BUYING_STORE, title: String) {
        self.init(
            title: title,
            zenyLimit: Int(packet.zenyLimit),
            items: packet.items.map { entry in
                Item(itemID: Int(entry.itemId), price: Int(entry.price), amount: Int(entry.amount))
            }
        )
    }

    func item(withID itemID: Int) -> Item? {
        items.first { $0.itemID == itemID }
    }

    /// Records a purchase (`ZC_UPDATE_ITEM_FROM_BUYING_STORE`): `amount` bought, `zeny` paid for them, and the
    /// zeny limit that is left. Returns false for an item that is not in the store.
    @discardableResult
    mutating func recordPurchase(itemID: Int, amount: Int, zeny: Int, zenyLimit: Int) -> Bool {
        guard let position = items.firstIndex(where: { $0.itemID == itemID }) else {
            return false
        }

        let bought = min(amount, items[position].amount)
        items[position].amount -= bought
        items[position].bought += bought
        spentZeny += zeny
        self.zenyLimit = zenyLimit
        return true
    }
}
