//
//  VendingSetup.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets

/// The shop set up window that the Vending skill opens (`ZC_OPENSTORE`): the cart items to sell, their
/// prices, and the title of the shop.
///
/// The limits are rAthena's: the number of items is `2 + skill level` (`vending_openvending`), the title
/// has `MESSAGE_SIZE` bytes, a price is cut to `vending_max_value` in conf/battle/items.conf.
struct VendingSetup: Equatable, Sendable {
    enum Problem: Equatable, Sendable {
        case emptyTitle
        case noItems
        case tooManyItems(slots: Int)
        case missingPrice
        case notInCart

        var message: String {
            switch self {
            case .emptyTitle: "Enter a title for the shop."
            case .noItems: "Pick the items to sell."
            case .tooManyItems(let slots): "The shop can hold \(slots) different items."
            case .missingPrice: "Set a price for every item."
            case .notInCart: "An item is no longer in the cart."
            }
        }
    }

    /// Bytes of the title without the NUL. `MESSAGE_SIZE` is 80.
    static let maxTitleBytes = 79

    /// `vending_max_value`, which rAthena applies as a silent cap.
    static let maxPrice = 1_000_000_000

    /// How many different items the shop takes (`ZC_OPENSTORE`'s `num`).
    let slots: Int

    private(set) var title = ""

    /// Amount to sell per cart index. An item with no amount is not part of the shop.
    private(set) var amounts: [Int : Int] = [:]
    private(set) var prices: [Int : Int] = [:]

    /// The request went out and the server has not answered yet.
    var isSending = false

    init(slots: Int) {
        self.slots = slots
    }

    // MARK: - Editing

    /// The title is cut at the bytes rAthena keeps, never inside a character.
    mutating func setTitle(_ title: String) {
        var title = title
        while title.utf8.count > Self.maxTitleBytes {
            title.removeLast()
        }
        self.title = title
    }

    /// Sells `amount` of the cart item. `available` is what the cart holds.
    mutating func setAmount(_ amount: Int, for index: Int, available: Int) {
        let amount = min(max(amount, 0), available)
        if amount == 0 {
            amounts.removeValue(forKey: index)
        } else {
            amounts[index] = amount
        }
    }

    mutating func setPrice(_ price: Int, for index: Int) {
        let price = min(max(price, 0), Self.maxPrice)
        if price == 0 {
            prices.removeValue(forKey: index)
        } else {
            prices[index] = price
        }
    }

    func amount(of index: Int) -> Int {
        amounts[index] ?? 0
    }

    func price(of index: Int) -> Int {
        prices[index] ?? 0
    }

    // MARK: - Request

    /// The picked items, in cart order.
    var pickedIndices: [Int] {
        amounts.keys.sorted()
    }

    /// What the shop would earn if everything sells.
    var totalValue: Int {
        pickedIndices.reduce(0) { $0 + amount(of: $1) * price(of: $1) }
    }

    func problem(cart: Cart) -> Problem? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }

        let picked = pickedIndices
        if picked.isEmpty {
            return .noItems
        }
        if picked.count > slots {
            return .tooManyItems(slots: slots)
        }
        for index in picked {
            guard let item = cart.items[index], item.amount >= amount(of: index) else {
                return .notInCart
            }
            if price(of: index) <= 0 {
                return .missingPrice
            }
        }
        return nil
    }

    /// The items of `CZ_REQ_OPENSTORE2`.
    var requestItems: [(index: Int, amount: Int, price: Int)] {
        pickedIndices.map { (index: $0, amount: amount(of: $0), price: price(of: $0)) }
    }
}

/// The player's own shop, once the server opened it (`ZC_PC_PURCHASE_MYITEMLIST`).
struct OwnVendingShop: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        /// The cart index, which the sold notices call `index`.
        var index: Int
        var itemID: Int
        var price: Int

        /// What is still for sale.
        var amount: Int

        /// What was sold since the shop opened.
        var sold = 0

        var id: Int {
            index
        }

        var isSoldOut: Bool {
            amount == 0
        }
    }

    var title: String
    private(set) var items: [Item]

    /// The zeny the sales brought in, as the notices report it (after tax).
    private(set) var earnedZeny = 0

    init(title: String, items: [Item]) {
        self.title = title
        self.items = items
    }

    init(from packet: PACKET_ZC_PC_PURCHASE_MYITEMLIST, title: String) {
        self.init(
            title: title,
            items: packet.items.map { entry in
                Item(index: Int(entry.index), itemID: Int(entry.itemId), price: Int(entry.price), amount: Int(entry.amount))
            }
        )
    }

    /// Nothing is left to sell.
    var isSoldOut: Bool {
        items.allSatisfy(\.isSoldOut)
    }

    func item(at index: Int) -> Item? {
        items.first { $0.index == index }
    }

    /// Records a sold notice (`ZC_DELETEITEM_FROM_MCSTORE`). Returns false for an item that is not in the shop.
    @discardableResult
    mutating func recordSale(index: Int, amount: Int, zeny: Int) -> Bool {
        guard let position = items.firstIndex(where: { $0.index == index }) else {
            return false
        }

        let sold = min(amount, items[position].amount)
        items[position].amount -= sold
        items[position].sold += sold
        earnedZeny += zeny
        return true
    }
}
