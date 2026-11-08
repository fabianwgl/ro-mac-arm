//
//  Trade.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// A request to trade, in either direction.
struct TradeRequest: Equatable, Sendable {
    var accountID: UInt32
    var name: String
    var baseLevel: Int
}

/// What `ZC_ACK_EXCHANGE_ITEM` says about a trade request, `e_ack_trade_response` in clif.hpp.
enum TradeResponse: Equatable, Sendable {
    case tooFar
    case characterNotFound
    case failed
    case accepted
    case declined
    case busy
    case unknown(Int)

    init(result: UInt8) {
        switch result {
        case 0: self = .tooFar
        case 1: self = .characterNotFound
        case 2: self = .failed
        case 3: self = .accepted
        case 4: self = .declined
        case 5: self = .busy
        default: self = .unknown(Int(result))
        }
    }

    /// The message for a request that did not lead to a trade. `name` is the other player when it is known.
    func failureMessage(name: String?) -> String? {
        let who = name ?? "The player"
        switch self {
        case .tooFar: return "\(who) is too far away to trade."
        case .characterNotFound: return "\(who) cannot be found."
        case .failed: return "The trade could not start. \(who) may be busy or the trade is not allowed here."
        case .declined: return "\(who) declined the trade."
        case .busy: return "\(who) is busy."
        case .unknown: return "The trade request failed."
        case .accepted: return nil
        }
    }
}

/// Why the server refused an item (`ZC_ACK_ADD_EXCHANGE_ITEM`, `e_exitem_add_result` in clif.hpp).
enum TradeItemFailure: Equatable, Sendable {
    case overweight
    case cannotTrade
    case inventoryFull
    case stackLimit
    case unknown

    /// `nil` for success.
    init?(result: UInt8) {
        switch result {
        case 0: return nil
        case 1: self = .overweight
        case 2: self = .cannotTrade
        case 3: self = .inventoryFull
        case 4: self = .stackLimit
        default: self = .unknown
        }
    }

    var message: String {
        switch self {
        case .overweight: "The other player cannot carry that much weight."
        case .cannotTrade: "This item cannot be traded."
        case .inventoryFull: "The other player has no room for another item."
        case .stackLimit: "The other player cannot hold that many of this item."
        case .unknown: "The item could not be added to the trade."
        }
    }
}

/// An open trade window: what both players offer, and how far each side is.
///
/// The flow is rAthena's (`trade.cpp`): both sides add items and zeny, each side locks its offer with OK
/// (`CZ_CONCLUDE_EXCHANGE_ITEM`), and once both are locked each side confirms with Trade (`CZ_EXEC_EXCHANGE_ITEM`).
/// The server finishes the trade when the second confirmation arrives. A locked side cannot add anything, but
/// rAthena does not stop the partner from changing an unlocked offer after this side locked, so the model records
/// that and refuses to confirm (`partnerChangedAfterLock`).
struct Trade: Equatable, Sendable {
    /// Items per side: the `deal.item[10]` of rAthena.
    static let maxOffers = 10

    /// The most items of one kind in one add: rAthena casts the amount of `CZ_ADD_EXCHANGE_ITEM` to 16 bits.
    static let maxAmountPerAdd = Int(Int16.max)

    /// The most zeny a player can hold (`MAX_ZENY`).
    static let maxZeny = 1_000_000_000

    /// `NV_BASIC`: rAthena wants level 1 of it to trade (`basic_skill_check` in conf/battle/skill.conf).
    static let basicSkillID = 1

    struct Partner: Equatable, Sendable {
        var accountID: UInt32
        var name: String
        var baseLevel: Int
    }

    /// One item line of a side.
    struct Offer: Identifiable, Equatable, Sendable {
        /// The inventory index of an own offer, a running number for the partner's.
        var id: Int
        var itemID: Int
        var amount: Int
        var type: Int
        var isIdentified: Bool
        var refine: Int
        var cards: [Int]

        init(id: Int, itemID: Int, amount: Int, type: Int = 0, isIdentified: Bool = true, refine: Int = 0, cards: [Int] = []) {
            self.id = id
            self.itemID = itemID
            self.amount = amount
            self.type = type
            self.isIdentified = isIdentified
            self.refine = refine
            self.cards = cards
        }

        /// The server shows equal items of the partner as one line.
        fileprivate func isSameKind(as other: Offer) -> Bool {
            itemID == other.itemID && isIdentified == other.isIdentified && refine == other.refine && cards == other.cards
        }
    }

    struct Side: Equatable, Sendable {
        var offers: [Offer] = []
        var zeny = 0
        /// OK pressed: the offer is final.
        var isLocked = false
        /// Trade pressed: waiting for the other side.
        var hasConfirmed = false

        var isEmpty: Bool {
            offers.isEmpty && zeny == 0
        }
    }

    let partner: Partner
    private(set) var mine = Side()
    private(set) var theirs = Side()

    /// Own items that were sent to the server and wait for the answer, oldest first.
    private(set) var pendingAdds: [Offer] = []

    /// The partner changed the offer after this side was locked.
    private(set) var partnerChangedAfterLock = false

    private var nextPartnerOfferID = 0

    init(partner: Partner) {
        self.partner = partner
    }

    // MARK: - State

    var isBothLocked: Bool {
        mine.isLocked && theirs.isLocked
    }

    /// Items and zeny can be added until this side is locked.
    var canChangeOffer: Bool {
        !mine.isLocked
    }

    /// OK waits for the answers to the items that are on their way.
    var canLock: Bool {
        !mine.isLocked && pendingAdds.isEmpty
    }

    var canConfirm: Bool {
        isBothLocked && !mine.hasConfirmed && !partnerChangedAfterLock
    }

    enum Stage: Equatable, Sendable {
        case negotiating
        case waitingForPartnerLock
        case waitingForOwnLock
        case readyToConfirm
        case waitingForPartnerConfirm
        case partnerChangedAfterLock
    }

    var stage: Stage {
        if mine.hasConfirmed {
            return .waitingForPartnerConfirm
        }
        if partnerChangedAfterLock {
            return .partnerChangedAfterLock
        }
        switch (mine.isLocked, theirs.isLocked) {
        case (true, true): return .readyToConfirm
        case (true, false): return .waitingForPartnerLock
        case (false, true): return .waitingForOwnLock
        case (false, false): return .negotiating
        }
    }

    // MARK: - Own Offer

    /// Whether `addItem` would accept a line for this inventory index.
    func canOffer(inventoryIndex: Int) -> Bool {
        guard canChangeOffer else {
            return false
        }
        return knownIndices.contains(inventoryIndex) || knownIndices.count < Self.maxOffers
    }

    /// The amount of an inventory item that is on its way to the trade and not yet taken out of the inventory.
    func pendingAmount(inventoryIndex: Int) -> Int {
        pendingAdds.filter { $0.id == inventoryIndex }.reduce(0) { $0 + $1.amount }
    }

    /// Records an item that is sent to the server. Returns false when the offer cannot take it.
    @discardableResult
    mutating func requestAdd(_ offer: Offer) -> Bool {
        guard offer.amount > 0, canOffer(inventoryIndex: offer.id) else {
            return false
        }
        pendingAdds.append(offer)
        return true
    }

    /// The server accepted the oldest pending item with this inventory index. Returns the offer so the caller
    /// can take it out of the inventory.
    @discardableResult
    mutating func confirmAdd(inventoryIndex: Int) -> Offer? {
        guard let position = pendingAdds.firstIndex(where: { $0.id == inventoryIndex }) else {
            return nil
        }

        let offer = pendingAdds.remove(at: position)
        if let existing = mine.offers.firstIndex(where: { $0.id == offer.id }) {
            mine.offers[existing].amount += offer.amount
        } else {
            mine.offers.append(offer)
        }
        return offer
    }

    /// The server refused the oldest pending item with this inventory index.
    @discardableResult
    mutating func rejectAdd(inventoryIndex: Int) -> Offer? {
        guard let position = pendingAdds.firstIndex(where: { $0.id == inventoryIndex }) else {
            return nil
        }
        return pendingAdds.remove(at: position)
    }

    /// Sets the zeny this side offers. rAthena keeps one value, a new one replaces the last. Returns false when
    /// the side is locked or the value is out of range.
    @discardableResult
    mutating func setZeny(_ zeny: Int, available: Int) -> Bool {
        guard canChangeOffer, zeny >= 0, zeny <= min(available, Self.maxZeny) else {
            return false
        }
        mine.zeny = zeny
        return true
    }

    // MARK: - Partner Offer

    /// The partner added an item (`ZC_ADD_EXCHANGE_ITEM` with an item id).
    mutating func partnerAdded(_ offer: Offer) {
        guard offer.amount > 0 else {
            return
        }

        noteChangeByPartner()

        var offer = offer
        if let existing = theirs.offers.firstIndex(where: { $0.isSameKind(as: offer) }) {
            theirs.offers[existing].amount += offer.amount
        } else if theirs.offers.count < Self.maxOffers {
            offer.id = nextPartnerOfferID
            nextPartnerOfferID += 1
            theirs.offers.append(offer)
        }
    }

    /// The partner set the zeny (`ZC_ADD_EXCHANGE_ITEM` with item id 0).
    mutating func partnerSetZeny(_ zeny: Int) {
        if zeny != theirs.zeny {
            noteChangeByPartner()
        }
        theirs.zeny = max(zeny, 0)
    }

    private mutating func noteChangeByPartner() {
        if mine.isLocked {
            partnerChangedAfterLock = true
        }
    }

    // MARK: - Locking

    /// `ZC_CONCLUDE_EXCHANGE_ITEM`: one side locked its offer.
    mutating func lock(partner isPartner: Bool) {
        if isPartner {
            theirs.isLocked = true
        } else {
            mine.isLocked = true
        }
    }

    /// Trade was pressed. Returns false when the deal is not ready.
    @discardableResult
    mutating func confirm() -> Bool {
        guard canConfirm else {
            return false
        }
        mine.hasConfirmed = true
        return true
    }

    /// `ZC_EXCHANGEITEM_UNDO`: rAthena defines it to reset the window but never sends it. The window starts over.
    mutating func reset() {
        mine = Side()
        theirs = Side()
        pendingAdds = []
        partnerChangedAfterLock = false
    }

    private var knownIndices: Set<Int> {
        Set(mine.offers.map(\.id)).union(pendingAdds.map(\.id))
    }
}
