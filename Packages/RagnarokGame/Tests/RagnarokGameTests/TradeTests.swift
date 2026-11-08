//
//  TradeTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

/// The state machine of the trade window, against what rAthena's `trade.cpp` does.
struct TradeTests {
    private func makeTrade() -> Trade {
        Trade(partner: Trade.Partner(accountID: 2_000_002, name: "Poring", baseLevel: 50))
    }

    private func offer(index: Int, itemID: Int = 501, amount: Int = 1) -> Trade.Offer {
        Trade.Offer(id: index, itemID: itemID, amount: amount)
    }

    // MARK: - Stages

    @Test func newTradeIsNegotiating() {
        let trade = makeTrade()

        #expect(trade.stage == .negotiating)
        #expect(trade.canChangeOffer)
        #expect(trade.canLock)
        #expect(!trade.canConfirm)
        #expect(trade.mine.isEmpty)
        #expect(trade.theirs.isEmpty)
    }

    @Test func bothLockThenConfirm() {
        var trade = makeTrade()

        trade.lock(partner: false)
        #expect(trade.stage == .waitingForPartnerLock)
        #expect(!trade.canChangeOffer)
        #expect(!trade.canConfirm)

        trade.lock(partner: true)
        #expect(trade.stage == .readyToConfirm)
        #expect(trade.isBothLocked)
        #expect(trade.canConfirm)

        let result1 = trade.confirm()
        #expect(result1)
        #expect(trade.stage == .waitingForPartnerConfirm)
        #expect(!trade.canConfirm)
        let result2 = trade.confirm()
        #expect(!result2)
    }

    @Test func partnerLocksFirst() {
        var trade = makeTrade()

        trade.lock(partner: true)

        #expect(trade.stage == .waitingForOwnLock)
        #expect(trade.canLock)
        #expect(trade.canChangeOffer)
        let result3 = trade.confirm()
        #expect(!result3)
    }

    @Test func confirmNeedsBothLocks() {
        var trade = makeTrade()
        trade.lock(partner: false)

        let result4 = trade.confirm()
        #expect(!result4)
        #expect(!trade.mine.hasConfirmed)
    }

    // MARK: - Own offer

    @Test func addedItemWaitsForTheServerAnswer() {
        var trade = makeTrade()

        let result5 = trade.requestAdd(offer(index: 5, amount: 3))
        #expect(result5)

        #expect(trade.mine.offers.isEmpty)
        #expect(trade.pendingAmount(inventoryIndex: 5) == 3)
        #expect(!trade.canLock)

        let confirmed = trade.confirmAdd(inventoryIndex: 5)

        #expect(confirmed?.amount == 3)
        #expect(trade.mine.offers.map(\.amount) == [3])
        #expect(trade.pendingAmount(inventoryIndex: 5) == 0)
        #expect(trade.canLock)
    }

    @Test func sameInventoryItemAddsUpInOneLine() {
        var trade = makeTrade()

        trade.requestAdd(offer(index: 5, amount: 3))
        trade.requestAdd(offer(index: 5, amount: 2))
        #expect(trade.pendingAmount(inventoryIndex: 5) == 5)
        trade.confirmAdd(inventoryIndex: 5)
        trade.confirmAdd(inventoryIndex: 5)

        #expect(trade.mine.offers.count == 1)
        #expect(trade.mine.offers.first?.amount == 5)
    }

    @Test func refusedItemIsDropped() {
        var trade = makeTrade()
        trade.requestAdd(offer(index: 5, amount: 3))

        let refused = trade.rejectAdd(inventoryIndex: 5)

        #expect(refused?.amount == 3)
        #expect(trade.mine.offers.isEmpty)
        #expect(trade.pendingAmount(inventoryIndex: 5) == 0)
        #expect(trade.canLock)
    }

    @Test func answerWithoutRequestIsIgnored() {
        var trade = makeTrade()

        let result6 = trade.confirmAdd(inventoryIndex: 9)
        #expect(result6 == nil)
        let result7 = trade.rejectAdd(inventoryIndex: 9)
        #expect(result7 == nil)
        #expect(trade.mine.offers.isEmpty)
    }

    @Test func answersGoToTheOldestRequestOfTheSameIndex() {
        var trade = makeTrade()
        trade.requestAdd(offer(index: 5, amount: 3))
        trade.requestAdd(offer(index: 5, amount: 2))

        trade.rejectAdd(inventoryIndex: 5)
        trade.confirmAdd(inventoryIndex: 5)

        #expect(trade.mine.offers.first?.amount == 2)
    }

    @Test func aTradeHoldsTenDifferentItems() {
        var trade = makeTrade()
        for index in 2..<12 {
            let result8 = trade.requestAdd(offer(index: index))
            #expect(result8)
            trade.confirmAdd(inventoryIndex: index)
        }
        #expect(trade.mine.offers.count == Trade.maxOffers)

        #expect(!trade.canOffer(inventoryIndex: 20))
        let result9 = trade.requestAdd(offer(index: 20))
        #expect(!result9)
        // More of an item that is in the trade already is fine.
        #expect(trade.canOffer(inventoryIndex: 4))
        let result10 = trade.requestAdd(offer(index: 4))
        #expect(result10)
    }

    @Test func pendingItemsCountTowardsTheLimit() {
        var trade = makeTrade()
        for index in 2..<12 {
            trade.requestAdd(offer(index: index))
        }

        let result11 = trade.requestAdd(offer(index: 40))
        #expect(!result11)
    }

    @Test func emptyAmountIsRefused() {
        var trade = makeTrade()

        let result12 = trade.requestAdd(offer(index: 5, amount: 0))
        #expect(!result12)
    }

    @Test func lockedSideCannotAdd() {
        var trade = makeTrade()
        trade.lock(partner: false)

        let result13 = trade.requestAdd(offer(index: 5))
        #expect(!result13)
        let result14 = trade.setZeny(100, available: 1_000)
        #expect(!result14)
        #expect(trade.mine.zeny == 0)
    }

    @Test func zenyReplacesTheLastValueAndStaysInRange() {
        var trade = makeTrade()

        let result15 = trade.setZeny(400, available: 1_000)
        #expect(result15)
        let result16 = trade.setZeny(250, available: 1_000)
        #expect(result16)
        #expect(trade.mine.zeny == 250)

        let result17 = trade.setZeny(1_001, available: 1_000)
        #expect(!result17)
        let result18 = trade.setZeny(-1, available: 1_000)
        #expect(!result18)
        #expect(trade.mine.zeny == 250)

        let result19 = trade.setZeny(0, available: 1_000)
        #expect(result19)
        #expect(trade.mine.zeny == 0)
    }

    @Test func zenyIsLimitedToWhatAPlayerCanHold() {
        var trade = makeTrade()

        let result20 = trade.setZeny(Trade.maxZeny + 1, available: Int.max)
        #expect(!result20)
        let result21 = trade.setZeny(Trade.maxZeny, available: Int.max)
        #expect(result21)
    }

    // MARK: - Partner offer

    @Test func partnerItemsAreListed() {
        var trade = makeTrade()

        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 5))
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 502, amount: 1))

        #expect(trade.theirs.offers.map(\.itemID) == [501, 502])
        #expect(trade.theirs.offers.map(\.id) == [0, 1])
    }

    @Test func partnerItemsOfOneKindAddUp() {
        var trade = makeTrade()

        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 5))
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 7))

        #expect(trade.theirs.offers.count == 1)
        #expect(trade.theirs.offers.first?.amount == 12)
    }

    @Test func partnerItemsWithOtherCardsOrRefineStaySeparate() {
        var trade = makeTrade()

        trade.partnerAdded(Trade.Offer(id: 0, itemID: 1201, amount: 1, refine: 0, cards: []))
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 1201, amount: 1, refine: 4, cards: []))
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 1201, amount: 1, refine: 0, cards: [4001]))

        #expect(trade.theirs.offers.count == 3)
    }

    @Test func partnerOffersAtMostTenLines() {
        var trade = makeTrade()
        for itemID in 500..<512 {
            trade.partnerAdded(Trade.Offer(id: 0, itemID: itemID, amount: 1))
        }

        #expect(trade.theirs.offers.count == Trade.maxOffers)
    }

    @Test func partnerZenyReplacesTheLastValue() {
        var trade = makeTrade()

        trade.partnerSetZeny(5_000)
        trade.partnerSetZeny(1_200)

        #expect(trade.theirs.zeny == 1_200)
    }

    // MARK: - Changes after the lock

    @Test func partnerChangeBeforeOwnLockIsFine() {
        var trade = makeTrade()
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 1))
        trade.lock(partner: false)
        trade.lock(partner: true)

        #expect(!trade.partnerChangedAfterLock)
        #expect(trade.canConfirm)
    }

    @Test func partnerItemAfterOwnLockBlocksTheConfirmation() {
        var trade = makeTrade()
        trade.lock(partner: false)

        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 1))
        trade.lock(partner: true)

        #expect(trade.partnerChangedAfterLock)
        #expect(trade.stage == .partnerChangedAfterLock)
        #expect(!trade.canConfirm)
        let result22 = trade.confirm()
        #expect(!result22)
    }

    @Test func partnerZenyChangeAfterOwnLockBlocksTheConfirmation() {
        var trade = makeTrade()
        trade.partnerSetZeny(100)
        trade.lock(partner: false)

        trade.partnerSetZeny(100)
        #expect(!trade.partnerChangedAfterLock)

        trade.partnerSetZeny(5_000)
        #expect(trade.partnerChangedAfterLock)
    }

    @Test func undoStartsTheWindowOver() {
        var trade = makeTrade()
        trade.requestAdd(offer(index: 5))
        trade.confirmAdd(inventoryIndex: 5)
        trade.requestAdd(offer(index: 6))
        trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 1))
        trade.lock(partner: false)

        trade.reset()

        #expect(trade.stage == .negotiating)
        #expect(trade.mine.isEmpty)
        #expect(trade.theirs.isEmpty)
        #expect(trade.pendingAdds.isEmpty)
    }

    // MARK: - Server codes

    @Test func responseCodesFollowRathena() {
        #expect(TradeResponse(result: 0) == .tooFar)
        #expect(TradeResponse(result: 1) == .characterNotFound)
        #expect(TradeResponse(result: 2) == .failed)
        #expect(TradeResponse(result: 3) == .accepted)
        #expect(TradeResponse(result: 4) == .declined)
        #expect(TradeResponse(result: 5) == .busy)
        #expect(TradeResponse(result: 9) == .unknown(9))
    }

    @Test func failuresHaveMessagesAndAcceptDoesNot() {
        #expect(TradeResponse.tooFar.failureMessage(name: "Poring") == "Poring is too far away to trade.")
        #expect(TradeResponse.declined.failureMessage(name: "Poring") == "Poring declined the trade.")
        #expect(TradeResponse.busy.failureMessage(name: nil) == "The player is busy.")
        #expect(TradeResponse.accepted.failureMessage(name: "Poring") == nil)
    }

    @Test func itemResultCodesFollowRathena() {
        #expect(TradeItemFailure(result: 0) == nil)
        #expect(TradeItemFailure(result: 1) == .overweight)
        #expect(TradeItemFailure(result: 2) == .cannotTrade)
        #expect(TradeItemFailure(result: 3) == .inventoryFull)
        #expect(TradeItemFailure(result: 4) == .stackLimit)
        #expect(TradeItemFailure(result: 7) == .unknown)
    }
}
