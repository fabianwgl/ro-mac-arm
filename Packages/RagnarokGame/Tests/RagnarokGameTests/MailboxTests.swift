//
//  MailboxTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

struct MailboxTests {
    @Test func applyListReplacesEntriesAndKeepsOrder() {
        var mailbox = Mailbox()
        #expect(mailbox.hasLoadedList == false)

        mailbox.apply(list: [entry(3), entry(2), entry(1)], isEnd: true)
        #expect(mailbox.hasLoadedList)
        #expect(mailbox.visibleEntries.map(\.mailID) == [3, 2, 1])

        mailbox.apply(list: [entry(9)], isEnd: true)
        #expect(mailbox.visibleEntries.map(\.mailID) == [9])
    }

    @Test func tabsFilterEntriesAndReturnedTabAppearsOnlyWithMail() {
        var mailbox = Mailbox()
        mailbox.apply(list: [
            entry(4, tab: .normal),
            entry(3, tab: .account),
            entry(2, tab: .normal),
        ], isEnd: true)

        #expect(mailbox.tabs == [.normal, .account])
        #expect(mailbox.entries(in: .normal).map(\.mailID) == [4, 2])
        #expect(mailbox.entries(in: .account).map(\.mailID) == [3])

        mailbox.selectTab(.account)
        #expect(mailbox.visibleEntries.map(\.mailID) == [3])

        mailbox.apply(list: [entry(5, tab: .returned), entry(4, tab: .normal)], isEnd: true)
        #expect(mailbox.tabs == [.normal, .account, .returned])
    }

    @Test func selectedTabFallsBackWhenItDisappears() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2, tab: .returned), entry(1)], isEnd: true)
        mailbox.selectTab(.returned)
        #expect(mailbox.selectedTab == .returned)

        mailbox.apply(list: [entry(1)], isEnd: true)
        #expect(mailbox.selectedTab == .normal)
    }

    @Test func pagesHoldSevenMailsAndClampWhenTheListShrinks() {
        var mailbox = Mailbox()
        mailbox.apply(list: (1...16).reversed().map { entry(Int64($0)) }, isEnd: true)

        #expect(mailbox.pageCount == 3)
        #expect(mailbox.visibleEntries.map(\.mailID) == [16, 15, 14, 13, 12, 11, 10])
        #expect(mailbox.canGoToPreviousPage == false)
        #expect(mailbox.canGoToNextPage)

        mailbox.goToNextPage()
        mailbox.goToNextPage()
        #expect(mailbox.page == 2)
        #expect(mailbox.visibleEntries.map(\.mailID) == [2, 1])
        #expect(mailbox.canGoToNextPage == false)

        mailbox.goToNextPage()
        #expect(mailbox.page == 2)

        mailbox.apply(list: (1...5).reversed().map { entry(Int64($0)) }, isEnd: true)
        #expect(mailbox.page == 0)
        #expect(mailbox.pageCount == 1)
    }

    @Test func switchingTabStartsOnTheFirstPage() {
        var mailbox = Mailbox()
        mailbox.apply(list: (1...10).map { entry(Int64($0)) } + [entry(100, tab: .account)], isEnd: true)

        mailbox.goToNextPage()
        #expect(mailbox.page == 1)

        mailbox.selectTab(.account)
        #expect(mailbox.page == 0)
    }

    @Test func nextPageIsAServerRequestOnlyWhenTheListIsIncomplete() {
        var mailbox = Mailbox()
        mailbox.apply(list: (1...7).reversed().map { entry(Int64($0)) }, isEnd: true)
        #expect(mailbox.needsNextPageFromServer == false)

        mailbox.apply(list: (1...7).reversed().map { entry(Int64($0)) }, isEnd: false)
        #expect(mailbox.needsNextPageFromServer)
        #expect(mailbox.lastMailID == 1)

        mailbox.apply(list: (1...10).reversed().map { entry(Int64($0)) }, isEnd: false)
        #expect(mailbox.needsNextPageFromServer == false)
        #expect(mailbox.canGoToNextPage)
    }

    @Test func readingAMailMarksItRead() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2, isRead: false), entry(1, isRead: true)], isEnd: true)
        #expect(mailbox.unreadCount(in: .normal) == 1)

        mailbox.apply(letter: letter(2, text: "Hello"))

        #expect(mailbox.letter?.text == "Hello")
        #expect(mailbox.entry(mailID: 2)?.isRead == true)
        #expect(mailbox.unreadCount(in: .normal) == 0)
    }

    @Test func openMailStaysWhileItIsInTheNewListAndClosesOtherwise() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2), entry(1)], isEnd: true)
        mailbox.apply(letter: letter(2))

        mailbox.apply(list: [entry(2, isRead: true), entry(1)], isEnd: true)
        #expect(mailbox.letter?.mailID == 2)

        mailbox.apply(list: [entry(1)], isEnd: true)
        #expect(mailbox.letter == nil)
    }

    @Test func deletingTheOpenMailClosesIt() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2), entry(1)], isEnd: true)
        mailbox.apply(letter: letter(2))

        mailbox.removeMail(mailID: 2)

        #expect(mailbox.entries.map(\.mailID) == [1])
        #expect(mailbox.letter == nil)

        mailbox.removeMail(mailID: 99)
        #expect(mailbox.entries.map(\.mailID) == [1])
    }

    @Test func takingZenyAndItemsClearsTheAttachments() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2, hasZeny: true, hasItems: true)], isEnd: true)
        mailbox.apply(letter: letter(2, zeny: 1_000, items: [attachment(0, itemID: 501, amount: 5)]))
        #expect(mailbox.letter?.hasAttachments == true)

        mailbox.zenyTaken(mailID: 2)
        #expect(mailbox.letter?.zeny == 0)
        #expect(mailbox.entry(mailID: 2)?.hasZeny == false)
        #expect(mailbox.entry(mailID: 2)?.hasItems == true)
        #expect(mailbox.letter?.hasAttachments == true)

        mailbox.itemsTaken(mailID: 2)
        #expect(mailbox.letter?.items.isEmpty == true)
        #expect(mailbox.entry(mailID: 2)?.hasItems == false)
        #expect(mailbox.letter?.hasAttachments == false)
    }

    @Test func takingFromAnotherMailLeavesTheOpenOneAlone() {
        var mailbox = Mailbox()
        mailbox.apply(list: [entry(2, hasZeny: true), entry(1, hasZeny: true)], isEnd: true)
        mailbox.apply(letter: letter(2, zeny: 1_000))

        mailbox.zenyTaken(mailID: 1)

        #expect(mailbox.letter?.zeny == 1_000)
        #expect(mailbox.entry(mailID: 1)?.hasZeny == false)
        #expect(mailbox.entry(mailID: 2)?.hasZeny == true)
    }

    @Test func unreadFlagReportsOnlyTheChangeToUnread() {
        var mailbox = Mailbox()

        var isNew = mailbox.setUnread(false)
        #expect(isNew == false)

        isNew = mailbox.setUnread(true)
        #expect(isNew)
        #expect(mailbox.hasUnread)

        // The server repeats the icon after every read.
        isNew = mailbox.setUnread(true)
        #expect(isNew == false)

        isNew = mailbox.setUnread(false)
        #expect(isNew == false)
        #expect(mailbox.hasUnread == false)

        isNew = mailbox.setUnread(true)
        #expect(isNew)
    }

    @Test func replyNeedsARealSender() {
        #expect(entry(1, sender: "Poring").canReply)
        #expect(entry(1, sender: "").canReply == false)
        #expect(entry(1, sender: "Server", isFromNPC: true).canReply == false)
    }

    // MARK: - Helpers

    private func entry(
        _ mailID: Int64,
        tab: Mailbox.Tab = .normal,
        isRead: Bool = true,
        hasZeny: Bool = false,
        hasItems: Bool = false,
        sender: String = "Poring",
        isFromNPC: Bool = false
    ) -> Mailbox.Entry {
        Mailbox.Entry(
            mailID: mailID,
            tab: tab,
            isRead: isRead,
            hasZeny: hasZeny,
            hasItems: hasItems,
            isFromNPC: isFromNPC,
            sender: sender,
            title: "Mail \(mailID)",
            expiresIn: nil
        )
    }

    private func attachment(_ id: Int, itemID: Int, amount: Int) -> Mailbox.Attachment {
        Mailbox.Attachment(id: id, itemID: itemID, amount: amount, type: 0, isIdentified: true, isDamaged: false, refine: 0, cards: [])
    }

    private func letter(
        _ mailID: Int64,
        text: String = "",
        zeny: Int64 = 0,
        items: [Mailbox.Attachment] = []
    ) -> Mailbox.Letter {
        Mailbox.Letter(mailID: mailID, tab: .normal, text: text, zeny: zeny, items: items)
    }
}
