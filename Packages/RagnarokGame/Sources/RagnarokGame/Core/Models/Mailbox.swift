//
//  Mailbox.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The RODEX inbox as the player sees it: the mails of every tab, the open mail and the unread flag.
///
/// rAthena at PACKETVER 20170419 and later (`clif_Mail_refreshinbox`) sends every mail of every tab in one
/// list, newest first, and answers every refresh with the whole list again. So the list is replaced as a
/// whole and paging (7 mails a page, `MAIL_PAGE_SIZE`) happens here.
struct Mailbox: Equatable, Sendable {
    /// `enum mail_inbox_type`.
    enum Tab: UInt8, CaseIterable, Identifiable, Sendable {
        case normal = 0
        case account = 1
        case returned = 2

        var id: UInt8 {
            rawValue
        }

        var title: String {
            switch self {
            case .normal: "Mail"
            case .account: "Account"
            case .returned: "Returned"
            }
        }
    }

    struct Entry: Identifiable, Equatable, Sendable {
        var mailID: Int64
        var tab: Tab
        var isRead: Bool
        var hasZeny: Bool
        var hasItems: Bool

        /// Sent by a script or the server, there is nobody to reply to.
        var isFromNPC: Bool
        var sender: String
        var title: String

        /// Time until the mail is deleted. nil when rAthena schedules no deletion.
        var expiresIn: TimeInterval?

        var id: Int64 {
            mailID
        }

        var hasAttachments: Bool {
            hasZeny || hasItems
        }

        var canReply: Bool {
            !isFromNPC && !sender.isEmpty
        }
    }

    /// An item attached to a mail that was received.
    struct Attachment: Identifiable, Equatable, Sendable {
        var id: Int
        var itemID: Int
        var amount: Int
        var type: Int
        var isIdentified: Bool
        var isDamaged: Bool
        var refine: Int
        var cards: [Int]
    }

    /// The content of one mail.
    struct Letter: Equatable, Sendable {
        var mailID: Int64
        var tab: Tab
        var text: String
        var zeny: Int64
        var items: [Attachment]

        var hasAttachments: Bool {
            zeny > 0 || !items.isEmpty
        }
    }

    /// rAthena has no deletion scheduled when it sends one year ("fake the scheduled deletion", clif.cpp).
    static let noExpiry: TimeInterval = 365 * 24 * 60 * 60

    /// `MAIL_PAGE_SIZE`.
    static let pageSize = 7

    private(set) var entries: [Entry] = []

    /// False when the server says more mails follow (the `is end` byte of the list).
    private(set) var isListComplete = true
    private(set) var hasLoadedList = false

    /// The server's mail icon: unread or unchecked mails exist (`ZC_NOTIFY_UNREADMAIL`).
    private(set) var hasUnread = false

    private(set) var selectedTab: Tab = .normal
    private(set) var page = 0
    private(set) var letter: Letter?

    init() {
    }

    // MARK: - Reading

    /// Normal and account always, returned only when there is one.
    var tabs: [Tab] {
        Tab.allCases.filter { $0 != .returned || !entries(in: $0).isEmpty }
    }

    func entries(in tab: Tab) -> [Entry] {
        entries.filter { $0.tab == tab }
    }

    func unreadCount(in tab: Tab) -> Int {
        entries.count { $0.tab == tab && !$0.isRead }
    }

    func entry(mailID: Int64) -> Entry? {
        entries.first { $0.mailID == mailID }
    }

    var pageCount: Int {
        max(1, (entries(in: selectedTab).count + Self.pageSize - 1) / Self.pageSize)
    }

    /// The mails of the selected tab on the current page.
    var visibleEntries: [Entry] {
        let tabEntries = entries(in: selectedTab)
        let start = min(page * Self.pageSize, tabEntries.count)
        let end = min(start + Self.pageSize, tabEntries.count)
        return Array(tabEntries[start..<end])
    }

    var canGoToPreviousPage: Bool {
        page > 0
    }

    var canGoToNextPage: Bool {
        page + 1 < pageCount
    }

    /// True on the last page while the server has more mails: the next page is a request.
    var needsNextPageFromServer: Bool {
        !isListComplete && !canGoToNextPage
    }

    /// The oldest mail of the selected tab, which `CZ_REQ_NEXT_MAIL_LIST` names as the last one the client has.
    var lastMailID: Int64? {
        entries(in: selectedTab).last?.mailID
    }

    // MARK: - Changes

    /// Replaces the list. The open mail stays open while it is still in the list.
    mutating func apply(list: [Entry], isEnd: Bool) {
        entries = list
        isListComplete = isEnd
        hasLoadedList = true

        if let letter, !list.contains(where: { $0.mailID == letter.mailID }) {
            self.letter = nil
        }

        if !tabs.contains(selectedTab) {
            selectedTab = .normal
        }
        clampPage()
    }

    /// Stores the mail the server sent and marks it read, as the server does.
    mutating func apply(letter: Letter) {
        self.letter = letter

        if let index = entries.firstIndex(where: { $0.mailID == letter.mailID }) {
            entries[index].isRead = true
        }
    }

    /// Sets the unread flag. Returns true when it just turned on, which is when to tell the player.
    @discardableResult
    mutating func setUnread(_ unread: Bool) -> Bool {
        let isNew = unread && !hasUnread
        hasUnread = unread
        return isNew
    }

    mutating func selectTab(_ tab: Tab) {
        guard tab != selectedTab else {
            return
        }
        selectedTab = tab
        page = 0
    }

    mutating func goToPreviousPage() {
        if canGoToPreviousPage {
            page -= 1
        }
    }

    mutating func goToNextPage() {
        if canGoToNextPage {
            page += 1
        }
    }

    mutating func closeLetter() {
        letter = nil
    }

    mutating func removeMail(mailID: Int64) {
        entries.removeAll { $0.mailID == mailID }
        if letter?.mailID == mailID {
            letter = nil
        }
        if !tabs.contains(selectedTab) {
            selectedTab = .normal
        }
        clampPage()
    }

    /// The zeny of the mail was taken.
    mutating func zenyTaken(mailID: Int64) {
        if letter?.mailID == mailID {
            letter?.zeny = 0
        }
        if let index = entries.firstIndex(where: { $0.mailID == mailID }) {
            entries[index].hasZeny = false
        }
    }

    /// The items of the mail were taken.
    mutating func itemsTaken(mailID: Int64) {
        if letter?.mailID == mailID {
            letter?.items = []
        }
        if let index = entries.firstIndex(where: { $0.mailID == mailID }) {
            entries[index].hasItems = false
        }
    }

    private mutating func clampPage() {
        page = min(page, pageCount - 1)
    }
}
