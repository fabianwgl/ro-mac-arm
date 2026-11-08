//
//  MailboxView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokModels
import SwiftUI

struct MailboxView: View {
    var mailbox: Mailbox
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        GameWindow {
            HStack(alignment: .top, spacing: 0) {
                GameVerticalTabBar(tabs: mailbox.tabs, selection: tabSelection) { tab in
                    Text(verbatim: tab.title)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .background {
                    GameStripeView()
                }

                VStack(spacing: 0) {
                    mailList
                    pager
                    Rectangle()
                        .fill(Color.gameBoxBorder)
                        .frame(height: 1)
                    MailLetterView(mailbox: mailbox)
                }
            }
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: summary)
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)

                Spacer(minLength: 0)

                Button {
                    playSession.refreshMailbox()
                } label: {
                    Text(verbatim: "Refresh")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)

                Button {
                    playSession.beginMailCompose()
                } label: {
                    Text(verbatim: "Write")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)
                .disabled(playSession.mail.draft != nil)
            }
        }
        .gameWindowTitle(Text(verbatim: "Mail"))
        .gameWindowCloseAction(onClose)
        .frame(width: 400)
        .onAppear {
            playSession.openMailbox()
        }
        .onDisappear {
            playSession.closeMailbox()
        }
    }

    private var tabSelection: Binding<Mailbox.Tab> {
        Binding {
            mailbox.selectedTab
        } set: { tab in
            playSession.selectMailTab(tab)
        }
    }

    private var summary: String {
        let unread = mailbox.unreadCount(in: mailbox.selectedTab)
        let total = mailbox.entries(in: mailbox.selectedTab).count
        return unread > 0 ? "\(total) mails, \(unread) unread" : "\(total) mails"
    }

    private var mailList: some View {
        VStack(spacing: 0) {
            if !mailbox.hasLoadedList {
                Text(verbatim: "Loading mail...")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else if mailbox.visibleEntries.isEmpty {
                Text(verbatim: "No mail.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }

            ForEach(mailbox.visibleEntries) { entry in
                MailRow(entry: entry, isSelected: mailbox.letter?.mailID == entry.mailID)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 22 * CGFloat(Mailbox.pageSize))
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))
    }

    private var pager: some View {
        HStack(spacing: 5) {
            Button {
                playSession.showPreviousMailPage()
            } label: {
                Text(verbatim: "<")
            }
            .buttonStyle(.game)
            .frame(width: 26, height: 18)
            .disabled(!mailbox.canGoToPreviousPage)

            Text(verbatim: "\(mailbox.page + 1) / \(mailbox.pageCount)")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)

            Button {
                playSession.showNextMailPage()
            } label: {
                Text(verbatim: ">")
            }
            .buttonStyle(.game)
            .frame(width: 26, height: 18)
            .disabled(!mailbox.canGoToNextPage && !mailbox.needsNextPageFromServer)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }
}

private struct MailRow: View {
    var entry: Mailbox.Entry
    var isSelected: Bool

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(entry.isRead ? Color.clear : Color.red)
                .frame(width: 6, height: 6)

            Text(verbatim: entry.sender.isEmpty ? "System" : entry.sender)
                .font(.game(size: 11, weight: entry.isRead ? nil : .bold))
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)
                .frame(width: 86, alignment: .leading)

            Text(verbatim: entry.title)
                .font(.game(size: 11, weight: entry.isRead ? nil : .bold))
                .foregroundStyle(Color.gameProminentLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.hasZeny {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.orange)
            }

            if entry.hasItems {
                Image(systemName: "shippingbox.fill")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.brown)
            }

            if let text = expiryText {
                Text(verbatim: text)
                    .font(.game(size: 10))
                    .foregroundStyle(Color.gameProminentLabel)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(isSelected ? Color(#colorLiteral(red: 0.8039215686, green: 0.8549019608, blue: 0.9529411765, alpha: 1)) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            playSession.readMail(entry)
        }
    }

    /// Days left. rAthena only reports a deletion time for mails that have one scheduled.
    private var expiryText: String? {
        guard let expiresIn = entry.expiresIn else {
            return nil
        }
        let days = Int(expiresIn / 86_400)
        return days > 0 ? "\(days)d" : "<1d"
    }
}

private struct MailLetterView: View {
    var mailbox: Mailbox

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let letter = mailbox.letter {
                header(for: letter)

                ScrollView {
                    Text(verbatim: letter.text)
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 40)

                attachments(of: letter)
                actions(for: letter)
            } else {
                Text(verbatim: "Select a mail to read it.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(6)
        .frame(height: 170)
    }

    private func header(for letter: Mailbox.Letter) -> some View {
        let entry = mailbox.entry(mailID: letter.mailID)
        let sender = entry.map { $0.sender.isEmpty ? "System" : $0.sender } ?? ""
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: entry?.title ?? "")
                .font(.game(size: 12, weight: .bold))
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Text(verbatim: "From: \(sender)")
                .font(.game(size: 10))
                .foregroundStyle(Color.gameProminentLabel)
                .lineLimit(1)
        }
    }

    @ViewBuilder private func attachments(of letter: Mailbox.Letter) -> some View {
        if letter.zeny > 0 {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(Color.orange)

                Text(verbatim: "\(letter.zeny.formatted()) zeny")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)

                Spacer(minLength: 0)

                Button {
                    playSession.takeMailZeny(letter)
                } label: {
                    Text(verbatim: "Take zeny")
                }
                .buttonStyle(.game)
                .frame(width: 70, height: 18)
            }
        }

        if !letter.items.isEmpty {
            HStack(spacing: 4) {
                ForEach(letter.items) { item in
                    MailAttachmentView(
                        itemID: item.itemID,
                        amount: item.amount,
                        refine: item.refine,
                        cards: item.cards,
                        isIdentified: item.isIdentified
                    )
                }

                Spacer(minLength: 0)

                Button {
                    playSession.takeMailItems(letter)
                } label: {
                    Text(verbatim: "Take items")
                }
                .buttonStyle(.game)
                .frame(width: 70, height: 18)
            }
        }
    }

    private func actions(for letter: Mailbox.Letter) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            if let entry = mailbox.entry(mailID: letter.mailID), entry.canReply {
                Button {
                    playSession.replyToMail(entry)
                } label: {
                    Text(verbatim: "Reply")
                }
                .buttonStyle(.game)
                .frame(width: 50, height: 18)
                .disabled(playSession.mail.draft != nil)
            }

            Button {
                playSession.deleteMail(letter)
            } label: {
                Text(verbatim: "Delete")
            }
            .buttonStyle(.game)
            .frame(width: 50, height: 18)
            .disabled(letter.hasAttachments)
        }
    }
}

/// An item in a mail: its icon with the amount, and its name and cards on hover.
struct MailAttachmentView: View {
    var itemID: Int
    var amount: Int
    var refine: Int
    var cards: [Int]
    var isIdentified: Bool

    @Environment(GameContext.self) private var gameContext

    var body: some View {
        InventoryItemView(item: inventoryItem)
            .help(helpText)
    }

    private var inventoryItem: InventoryItem {
        var item = InventoryItem()
        item.itemID = itemID
        item.amount = amount
        return item
    }

    private var helpText: String {
        var text = gameContext.itemInfoTable.localizedItemName(forItemID: itemID, isIdentified: isIdentified) ?? "\(itemID)"
        if refine > 0 {
            text = "+\(refine) " + text
        }
        if !isIdentified {
            text += " (unidentified)"
        }
        let cardNames = cards.map { gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: $0) ?? "\($0)" }
        if !cardNames.isEmpty {
            text += " [" + cardNames.joined(separator: ", ") + "]"
        }
        return "\(text) x\(amount)"
    }
}

#Preview {
    let mailbox: Mailbox = {
        var mailbox = Mailbox()
        mailbox.apply(list: [
            Mailbox.Entry(
                mailID: 2,
                tab: .normal,
                isRead: false,
                hasZeny: true,
                hasItems: true,
                isFromNPC: false,
                sender: "Poring",
                title: "Your reward",
                expiresIn: 86_400 * 12
            ),
            Mailbox.Entry(
                mailID: 1,
                tab: .normal,
                isRead: true,
                hasZeny: false,
                hasItems: false,
                isFromNPC: false,
                sender: "Leon",
                title: "Hello",
                expiresIn: nil
            ),
        ], isEnd: true)
        mailbox.apply(letter: Mailbox.Letter(
            mailID: 2,
            tab: .normal,
            text: "Thank you for the help.",
            zeny: 1_500,
            items: [
                Mailbox.Attachment(id: 0, itemID: 501, amount: 20, type: 0, isIdentified: true, isDamaged: false, refine: 0, cards: [])
            ]
        ))
        return mailbox
    }()

    MailboxView(mailbox: mailbox)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
