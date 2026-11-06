//
//  PlaySession+Mail.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokNetwork
import RagnarokPackets

@Observable
final class MailState {
    var mailbox = Mailbox()

    /// The mail being written. The write window is open while this is not nil.
    var draft: MailDraft?

    /// Counts the times the server asked to open or close the mail window (`ZC_MAIL_WINDOWS`, sent for `@mail`).
    /// The play view reacts to the change, it owns which window is shown.
    var openRequestCount = 0
    var closeRequestCount = 0
}

/// How the server answers a request to take the zeny or the items of a mail, `clif_mail_getattachment`.
enum MailTakeResult: Equatable, Sendable {
    case taken
    case tooMuchZeny
    case cannotCarry
    case failed

    init(zenyResult result: Int8) {
        switch result {
        case 0: self = .taken
        case 1: self = .tooMuchZeny
        default: self = .failed
        }
    }

    init(itemResult result: Int8) {
        switch result {
        case 0: self = .taken
        case 2: self = .cannotCarry
        default: self = .failed
        }
    }
}

extension PlaySession {
    /// Handles RODEX packets. Returns false when the packet is not a mail packet.
    func handleMailPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_NOTIFY_UNREADMAIL:
            if mail.mailbox.setUnread(packet.result != 0) {
                addMailMessage("You have new mail.")
            }
        case let packet as PACKET_ZC_MAIL_WINDOWS:
            if packet.type == 0 {
                mail.openRequestCount += 1
            } else {
                mail.closeRequestCount += 1
            }
        case let packet as PACKET_ZC_ACK_MAIL_LIST:
            mail.mailbox.apply(list: packet.mails.compactMap(entry(from:)), isEnd: packet.isEnd != 0)
        case let packet as PACKET_ZC_ACK_READ_MAIL:
            mail.mailbox.apply(letter: letter(from: packet))
        case let packet as PACKET_ZC_ACK_ITEM_FROM_MAIL:
            handleMailTake(packet)
        case let packet as PACKET_ZC_ACK_DELETE_MAIL:
            mail.mailbox.removeMail(mailID: packet.MailID)
            addMailMessage("The mail was deleted.")
        case let packet as PACKET_ZC_ACK_OPEN_WRITE_MAIL:
            handleOpenWriteMail(packet)
        case let packet as PACKET_ZC_CHECKNAME:
            handleMailReceiverCheck(packet)
        case let packet as PACKET_ZC_ACK_ADD_ITEM_RODEX:
            handleMailItemAttached(packet)
        case let packet as PACKET_ZC_ACK_REMOVE_ITEM_MAIL:
            mail.draft?.detach(index: Int(packet.index), count: Int(packet.cnt), weight: Int(packet.weight))
        case let packet as PACKET_ZC_WRITE_MAIL_RESULT:
            handleMailSendResult(packet)
        default:
            return false
        }
        return true
    }

    // MARK: - Mailbox Requests

    /// Asks for the inbox. Call when the mail window opens.
    func openMailbox() {
        sendPacket(PacketFactory.CZ_REQ_OPEN_MAIL())
    }

    /// Tells the server the mail window closed. Call when the mail window closes.
    func closeMailbox() {
        sendPacket(PacketFactory.CZ_CLOSE_MAILBOX())
    }

    /// Asks the char server for the inbox again.
    func refreshMailbox() {
        sendPacket(PacketFactory.CZ_REQ_REFRESH_MAIL_LIST())
    }

    /// Shows the next page. The pages are local because rAthena sends the whole inbox at once,
    /// the request only goes out when a server says more mails follow.
    func showNextMailPage() {
        if mail.mailbox.canGoToNextPage {
            mail.mailbox.goToNextPage()
        } else if mail.mailbox.needsNextPageFromServer, let lastMailID = mail.mailbox.lastMailID {
            sendPacket(PacketFactory.CZ_REQ_NEXT_MAIL_LIST(
                openType: mail.mailbox.selectedTab.rawValue,
                lastMailID: lastMailID
            ))
        }
    }

    func showPreviousMailPage() {
        mail.mailbox.goToPreviousPage()
    }

    func selectMailTab(_ tab: Mailbox.Tab) {
        mail.mailbox.selectTab(tab)
    }

    func readMail(_ entry: Mailbox.Entry) {
        sendPacket(PacketFactory.CZ_REQ_READ_MAIL(openType: entry.tab.rawValue, mailID: entry.mailID))
    }

    func closeMailLetter() {
        mail.mailbox.closeLetter()
    }

    func takeMailZeny(_ letter: Mailbox.Letter) {
        sendPacket(PacketFactory.CZ_REQ_ZENY_FROM_MAIL(openType: letter.tab.rawValue, mailID: letter.mailID))
    }

    func takeMailItems(_ letter: Mailbox.Letter) {
        sendPacket(PacketFactory.CZ_REQ_ITEM_FROM_MAIL(openType: letter.tab.rawValue, mailID: letter.mailID))
    }

    /// rAthena only deletes a mail whose zeny and items were taken, and does not answer otherwise.
    func deleteMail(_ letter: Mailbox.Letter) {
        guard !letter.hasAttachments else {
            addMailMessage("Take the zeny and the items before deleting the mail.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_REQ_DELETE_MAIL(openType: letter.tab.rawValue, mailID: letter.mailID))
    }

    // MARK: - Write Requests

    /// Opens the write window. The server blocks movement and item use until the window closes.
    func beginMailCompose(receiver: String = "", title: String = "") {
        guard mail.draft == nil else {
            return
        }

        var draft = MailDraft(receiverName: receiver)
        draft.title = title
        mail.draft = draft
        sendPacket(PacketFactory.CZ_REQ_OPEN_WRITE_MAIL(receiverName: receiver))
    }

    func replyToMail(_ entry: Mailbox.Entry) {
        guard entry.canReply else {
            return
        }
        beginMailCompose(receiver: entry.sender, title: MailDraft.replyTitle(to: entry.title))
    }

    /// Closes the write window. The cancel request is what lets the player move again.
    func closeMailCompose() {
        guard mail.draft != nil else {
            return
        }
        mail.draft = nil
        sendPacket(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
    }

    func checkMailReceiver() {
        guard var draft = mail.draft, draft.receiver != .checking else {
            return
        }

        let name = draft.trimmedReceiverName
        guard !name.isEmpty, MailDraft.byteCount(of: name) <= MailDraft.maxReceiverBytes else {
            return
        }

        draft.beginNameCheck()
        mail.draft = draft
        sendPacket(PacketFactory.CZ_CHECKNAME2(name: name))
    }

    /// Attaches `amount` of an inventory item to the mail. The server answers with the item or the reason.
    func attachMailItem(index: Int, amount: Int) {
        guard let draft = mail.draft, draft.isServerReady, !draft.isSending, amount > 0 else {
            return
        }
        guard draft.canAttachMore || draft.attachedAmount(index: index) > 0 else {
            addMailMessage("A mail holds at most \(MailDraft.maxAttachments) different items.", type: .error)
            return
        }
        sendPacket(PacketFactory.CZ_ADD_ITEM_TO_MAIL(index: index, count: amount))
    }

    func detachMailItem(_ attachment: MailDraft.Attachment) {
        guard let draft = mail.draft, !draft.isSending else {
            return
        }
        sendPacket(PacketFactory.CZ_REQ_REMOVE_ITEM_MAIL(index: attachment.index, count: attachment.amount))
    }

    /// Sends the mail. When the receiver was not checked yet it is checked first and the mail goes out
    /// when the check finds the character.
    func sendMail() {
        guard var draft = mail.draft, !draft.isSending else {
            return
        }

        if let problem = draft.problem(playerZeny: playerStatus.zeny) {
            addMailMessage(problem.message, type: .error)
            return
        }

        if draft.receiverCharacterID == nil {
            draft.sendWhenChecked = true
            mail.draft = draft
            checkMailReceiver()
            return
        }

        performMailSend(&draft)
        mail.draft = draft
    }

    // MARK: - Packet Handling

    private func performMailSend(_ draft: inout MailDraft) {
        guard let receiverCharacterID = draft.receiverCharacterID else {
            return
        }

        draft.isSending = true
        draft.sendWhenChecked = false
        sendPacket(PacketFactory.CZ_SEND_MAIL(
            receiverName: draft.trimmedReceiverName,
            senderName: character.name,
            receiverCharacterID: receiverCharacterID,
            zeny: draft.zeny,
            title: draft.title,
            body: draft.body
        ))
    }

    private func handleMailTake(_ packet: PACKET_ZC_ACK_ITEM_FROM_MAIL) {
        switch packet.packetType {
        case packet_header_rodexgetzeny:
            switch MailTakeResult(zenyResult: packet.result) {
            case .taken:
                mail.mailbox.zenyTaken(mailID: packet.MailID)
                addMailMessage("You took the zeny from the mail.")
            case .tooMuchZeny:
                addMailMessage("You cannot carry that much zeny.", type: .error)
            default:
                addMailMessage("Could not take the zeny.", type: .error)
            }
        case packet_header_rodexgetitem:
            switch MailTakeResult(itemResult: packet.result) {
            case .taken:
                mail.mailbox.itemsTaken(mailID: packet.MailID)
                addMailMessage("You took the items from the mail.")
            case .cannotCarry:
                addMailMessage("You cannot carry these items: the inventory is full or they are too heavy.", type: .error)
            default:
                addMailMessage("Could not take the items.", type: .error)
            }
        default:
            break
        }
    }

    private func handleOpenWriteMail(_ packet: PACKET_ZC_ACK_OPEN_WRITE_MAIL) {
        let accepted = packet.result != 0

        guard var draft = mail.draft else {
            // The window closed before the answer came, the server must not keep waiting for a mail.
            if accepted {
                sendPacket(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
            }
            return
        }

        guard accepted else {
            // Storage, a trade or another mail being written. The cancel clears a stale writing state.
            mail.draft = nil
            sendPacket(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
            addMailMessage("You cannot write a mail right now. Close the storage or the trade first.", type: .error)
            return
        }

        draft.isServerReady = true
        mail.draft = draft

        if draft.receiver == .unchecked, !draft.trimmedReceiverName.isEmpty {
            checkMailReceiver()
        }
    }

    private func handleMailReceiverCheck(_ packet: PACKET_ZC_CHECKNAME) {
        guard var draft = mail.draft else {
            return
        }

        let found = draft.applyNameCheck(
            name: packet.Name,
            characterID: UInt32(bitPattern: packet.CharId),
            job: Int(packet.Class),
            baseLevel: Int(packet.BaseLevel)
        )
        guard found else {
            return
        }

        if draft.receiverCharacterID != nil {
            if draft.sendWhenChecked {
                performMailSend(&draft)
            }
        } else {
            draft.sendWhenChecked = false
            addMailMessage("The receiver does not exist.", type: .error)
        }
        mail.draft = draft
    }

    private func handleMailItemAttached(_ packet: PACKET_ZC_ACK_ADD_ITEM_RODEX) {
        // `mail_attach_result` in mail.hpp.
        switch packet.result {
        case 0:
            let attachment = MailDraft.Attachment(
                index: Int(packet.index),
                itemID: Int(packet.itemId),
                amount: Int(packet.count),
                type: Int(packet.type),
                isIdentified: packet.IsIdentified != 0,
                refine: Int(packet.refiningLevel),
                cards: packet.slot.card.filter { $0 != 0 }.map(Int.init)
            )
            mail.draft?.attach(attachment, weight: Int(packet.weight))
        case 1:
            addMailMessage("The attachments would be too heavy for one mail.", type: .error)
        case 3:
            addMailMessage("A mail holds at most \(MailDraft.maxAttachments) different items.", type: .error)
        case 4:
            addMailMessage("That item cannot be sent by mail.", type: .error)
        default:
            addMailMessage("Could not attach the item.", type: .error)
        }
    }

    private func handleMailSendResult(_ packet: PACKET_ZC_WRITE_MAIL_RESULT) {
        // `enum mail_send_result` in clif.hpp.
        guard packet.result == 0 else {
            mailSendFailed(result: packet.result)
            return
        }

        addMailMessage("Mail sent.")
        mail.draft = nil
        // Writing mails stays on in the server until it is cancelled, the real client cancels after a send too.
        sendPacket(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
    }

    private func mailSendFailed(result: Int8) {
        switch result {
        case 2:
            addMailMessage("You cannot send more mails today.", type: .error)
        case 3:
            addMailMessage("The items could not be sent.", type: .error)
        case 4:
            addMailMessage("The receiver does not exist.", type: .error)
        case 5:
            addMailMessage("The receiver does not accept mail from you.", type: .error)
        default:
            addMailMessage("Failed to send the mail.", type: .error)
        }

        guard var draft = mail.draft else {
            return
        }

        draft.isSending = false
        draft.sendWhenChecked = false

        // After a failed send the server's idea of the attachments may differ from ours (it clears them for some
        // failures and keeps them for others). Starting the mail again on the server makes both empty.
        if !draft.attachments.isEmpty {
            draft.removeAllAttachments()
            draft.isServerReady = false
            sendPacket(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
            sendPacket(PacketFactory.CZ_REQ_OPEN_WRITE_MAIL(receiverName: draft.trimmedReceiverName))
        }
        mail.draft = draft
    }

    // MARK: - Packet Conversion

    private func entry(from packet: PACKET_ZC_ACK_MAIL_LIST_sub) -> Mailbox.Entry? {
        guard let tab = Mailbox.Tab(rawValue: packet.tab) else {
            return nil
        }

        // `enum mail_type` in clif.cpp: 0x2 zeny, 0x4 items, 0x8 NPC.
        let expiresIn = TimeInterval(packet.expiresIn)
        return Mailbox.Entry(
            mailID: packet.mailID,
            tab: tab,
            isRead: packet.isRead != 0,
            hasZeny: packet.type & 0x2 != 0,
            hasItems: packet.type & 0x4 != 0,
            isFromNPC: packet.type & 0x8 != 0,
            sender: packet.sender,
            title: packet.title,
            expiresIn: expiresIn >= Mailbox.noExpiry ? nil : expiresIn
        )
    }

    private func letter(from packet: PACKET_ZC_ACK_READ_MAIL) -> Mailbox.Letter {
        let items = packet.items.enumerated().map { offset, item in
            Mailbox.Attachment(
                id: offset,
                itemID: Int(item.ITID),
                amount: Int(item.count),
                type: Int(item.type),
                isIdentified: item.IsIdentified != 0,
                isDamaged: item.IsDamaged != 0,
                refine: Int(item.refiningLevel),
                cards: item.slot.card.filter { $0 != 0 }.map(Int.init)
            )
        }

        return Mailbox.Letter(
            mailID: packet.mailID,
            tab: Mailbox.Tab(rawValue: packet.tab) ?? .normal,
            text: packet.text,
            zeny: packet.zeny,
            items: items
        )
    }

    private func addMailMessage(_ content: String, type: MessageCenter.MessageType = .info) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
