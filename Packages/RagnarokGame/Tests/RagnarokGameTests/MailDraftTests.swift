//
//  MailDraftTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

struct MailDraftTests {
    @Test func nameCheckFindsOrRejectsTheReceiver() {
        var draft = MailDraft(receiverName: " Poring ")
        #expect(draft.receiver == .unchecked)

        draft.beginNameCheck()
        #expect(draft.receiver == .checking)

        let applied = draft.applyNameCheck(name: "Poring", characterID: 150_001, job: 4001, baseLevel: 55)
        #expect(applied)
        #expect(draft.receiver == .found(characterID: 150_001, job: 4001, baseLevel: 55))
        #expect(draft.receiverCharacterID == 150_001)

        // The char server answers with character id 0 for a name it does not know.
        draft.setReceiverName("Nobody")
        draft.beginNameCheck()
        draft.applyNameCheck(name: "Nobody", characterID: 0, job: 0, baseLevel: 0)
        #expect(draft.receiver == .notFound)
        #expect(draft.receiverCharacterID == nil)
    }

    @Test func staleNameCheckIsIgnored() {
        var draft = MailDraft(receiverName: "Poring")
        draft.beginNameCheck()
        draft.setReceiverName("Lunatic")
        #expect(draft.receiver == .unchecked)

        let applied = draft.applyNameCheck(name: "Poring", characterID: 5, job: 0, baseLevel: 1)

        #expect(applied == false)
        #expect(draft.receiver == .unchecked)
    }

    @Test func editingTheNameDropsTheCheckAndTheSendIntent() {
        var draft = MailDraft(receiverName: "Poring")
        draft.applyNameCheck(name: "Poring", characterID: 5, job: 0, baseLevel: 1)
        draft.sendWhenChecked = true

        draft.setReceiverName("Poring2")

        #expect(draft.receiver == .unchecked)
        #expect(draft.sendWhenChecked == false)

        draft.setReceiverName("Poring2")
        #expect(draft.receiver == .unchecked)
    }

    @Test func attachingTheSameItemAddsToItsAmount() {
        var draft = MailDraft()

        draft.attach(item(index: 5, amount: 10), weight: 100)
        draft.attach(item(index: 6, amount: 1), weight: 150)
        draft.attach(item(index: 5, amount: 5), weight: 250)

        #expect(draft.attachments.map(\.index) == [5, 6])
        #expect(draft.attachedAmount(index: 5) == 15)
        #expect(draft.attachedAmount(index: 7) == 0)
        #expect(draft.attachedWeight == 250)
    }

    @Test func detachingRemovesTheItemOnlyWhenNothingIsLeft() {
        var draft = MailDraft()
        draft.attach(item(index: 5, amount: 10), weight: 100)

        draft.detach(index: 5, count: 4, weight: 60)
        #expect(draft.attachedAmount(index: 5) == 6)
        #expect(draft.attachedWeight == 60)

        draft.detach(index: 5, count: 6, weight: 0)
        #expect(draft.attachments.isEmpty)
        #expect(draft.attachedWeight == 0)

        draft.detach(index: 9, count: 1, weight: 0)
        #expect(draft.attachments.isEmpty)
    }

    @Test func attachmentsAreLimitedToFiveItems() {
        var draft = MailDraft()
        #expect(draft.canAttachMore)

        for index in 2..<7 {
            draft.attach(item(index: index, amount: 1), weight: 0)
        }

        #expect(draft.attachments.count == MailDraft.maxAttachments)
        #expect(draft.canAttachMore == false)
    }

    @Test func feeIsTwoPercentOfZenyPlusPriceOfEveryItem() {
        var draft = MailDraft()
        #expect(draft.fee == 0)

        draft.zeny = 10_000
        #expect(draft.fee == 200)
        #expect(draft.totalCost == 10_200)

        draft.attach(item(index: 5, amount: 20), weight: 0)
        draft.attach(item(index: 6, amount: 1), weight: 0)
        // Every attached item costs the same, whatever its amount.
        #expect(draft.fee == 200 + 2 * 2_500)
    }

    @Test func problemsFollowTheServerRules() {
        var draft = readyDraft()
        #expect(draft.problem(playerZeny: 0) == nil)

        draft.isServerReady = false
        #expect(draft.problem(playerZeny: 0) == .notReady)
        draft.isServerReady = true

        draft.title = "   "
        #expect(draft.problem(playerZeny: 0) == .emptyTitle)
        draft.title = String(repeating: "a", count: 40)
        #expect(draft.problem(playerZeny: 0) == .titleTooLong)
        draft.title = String(repeating: "a", count: 39)
        #expect(draft.problem(playerZeny: 0) == nil)

        draft.body = String(repeating: "b", count: 500)
        #expect(draft.problem(playerZeny: 0) == .bodyTooLong)
        draft.body = String(repeating: "b", count: 499)
        #expect(draft.problem(playerZeny: 0) == nil)

        draft.setReceiverName("")
        #expect(draft.problem(playerZeny: 0) == .emptyReceiver)
        draft.setReceiverName(String(repeating: "n", count: 24))
        #expect(draft.problem(playerZeny: 0) == .receiverTooLong)
    }

    @Test func limitsCountUTF8BytesNotCharacters() {
        var draft = readyDraft()
        // 14 characters of 3 bytes are 42 bytes.
        draft.title = String(repeating: "\u{3042}", count: 14)
        #expect(draft.problem(playerZeny: 0) == .titleTooLong)
        draft.title = String(repeating: "\u{3042}", count: 13)
        #expect(draft.problem(playerZeny: 0) == nil)
    }

    @Test func notFoundReceiverBlocksSendingButUncheckedDoesNot() {
        var draft = readyDraft()
        draft.setReceiverName("Nobody")
        #expect(draft.problem(playerZeny: 0) == nil)

        draft.applyNameCheck(name: "Nobody", characterID: 0, job: 0, baseLevel: 0)
        #expect(draft.problem(playerZeny: 0) == .receiverNotFound)
    }

    @Test func zenyAndFeesMustBeAffordable() {
        var draft = readyDraft()
        draft.zeny = 1_000

        #expect(draft.problem(playerZeny: 1_019) == .notEnoughZeny)
        #expect(draft.problem(playerZeny: 1_020) == nil)

        draft.attach(item(index: 5, amount: 1), weight: 0)
        #expect(draft.problem(playerZeny: 1_020) == .notEnoughZeny)
        #expect(draft.problem(playerZeny: 3_520) == nil)
    }

    @Test func replyTitleAddsThePrefixOnceAndFitsTheLimit() {
        #expect(MailDraft.replyTitle(to: "Hello") == "RE: Hello")
        #expect(MailDraft.replyTitle(to: "RE: Hello") == "RE: Hello")

        let reply = MailDraft.replyTitle(to: String(repeating: "a", count: 60))
        #expect(MailDraft.byteCount(of: reply) <= MailDraft.maxTitleBytes)
        #expect(reply.hasPrefix("RE: aaa"))

        let wide = MailDraft.replyTitle(to: String(repeating: "\u{3042}", count: 30))
        #expect(MailDraft.byteCount(of: wide) <= MailDraft.maxTitleBytes)
    }

    @Test func takeResultsFollowClifMailGetattachment() {
        #expect(MailTakeResult(zenyResult: 0) == .taken)
        #expect(MailTakeResult(zenyResult: 1) == .tooMuchZeny)
        #expect(MailTakeResult(itemResult: 0) == .taken)
        #expect(MailTakeResult(itemResult: 2) == .cannotCarry)
        #expect(MailTakeResult(itemResult: 1) == .failed)
    }

    // MARK: - Helpers

    private func item(index: Int, amount: Int) -> MailDraft.Attachment {
        MailDraft.Attachment(index: index, itemID: 501, amount: amount, type: 0, isIdentified: true, refine: 0, cards: [])
    }

    private func readyDraft() -> MailDraft {
        var draft = MailDraft(receiverName: "Poring")
        draft.title = "Hello"
        draft.isServerReady = true
        return draft
    }
}
