//
//  MailDraft.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// A mail that is being written.
///
/// The limits and fees are rAthena's: `MAIL_TITLE_LENGTH`, `MAIL_BODY_LENGTH` and `MAIL_MAX_ITEM` in mmo.hpp,
/// `mail_zeny_fee`, `mail_attachment_price` and `mail_attachment_weight` in conf/battle/misc.conf. The real
/// client hardcodes the fees as well (the conf says so), so they are fixed here too.
struct MailDraft: Equatable, Sendable {
    /// What the name check (`CZ_CHECKNAME2` / `ZC_CHECKNAME`) found out about the receiver.
    enum Receiver: Equatable, Sendable {
        case unchecked
        case checking
        case found(characterID: UInt32, job: Int, baseLevel: Int)
        case notFound
    }

    /// An item of the player's inventory that goes with the mail.
    struct Attachment: Identifiable, Equatable, Sendable {
        /// The inventory index, which the attach and detach requests use.
        var index: Int
        var itemID: Int
        var amount: Int
        var type: Int
        var isIdentified: Bool
        var refine: Int
        var cards: [Int]

        var id: Int {
            index
        }
    }

    enum Problem: Equatable, Sendable {
        case emptyReceiver
        case receiverTooLong
        case receiverNotFound
        case emptyTitle
        case titleTooLong
        case bodyTooLong
        case notEnoughZeny
        case notReady

        var message: String {
            switch self {
            case .emptyReceiver: "Enter the name of the receiver."
            case .receiverTooLong: "The receiver name is too long."
            case .receiverNotFound: "The receiver does not exist."
            case .emptyTitle: "Enter a title."
            case .titleTooLong: "The title is too long."
            case .bodyTooLong: "The message is too long."
            case .notEnoughZeny: "You do not have enough zeny for the zeny and the fees."
            case .notReady: "The mail is not ready yet."
            }
        }
    }

    /// Bytes without the NUL. `NAME_LENGTH` is 24.
    static let maxReceiverBytes = 23

    /// `MAIL_TITLE_LENGTH` is 40, the server copies at most 39 bytes.
    static let maxTitleBytes = 39

    /// `MAIL_BODY_LENGTH` is 500 at PACKETVER 20150513 and later.
    static let maxBodyBytes = 499

    /// `MAIL_MAX_ITEM`.
    static let maxAttachments = 5

    /// `mail_zeny_fee`, percent of the zeny that is sent.
    static let zenyFeePercent: Int64 = 2

    /// `mail_attachment_price`, for every attached item.
    static let attachmentFee: Int64 = 2500

    /// `mail_attachment_weight`, in the unit of `attachedWeight`.
    static let maxAttachmentWeight = 2000

    var receiverName: String
    private(set) var receiver: Receiver = .unchecked
    var title = ""
    var body = ""
    var zeny: Int64 = 0
    private(set) var attachments: [Attachment] = []

    /// The total weight of the attachments as the server last reported it.
    private(set) var attachedWeight = 0

    /// The server accepted `CZ_REQ_OPEN_WRITE_MAIL`. Attachments need it.
    var isServerReady = false
    var isSending = false

    /// The player pressed send before the receiver was checked: send when the check succeeds.
    var sendWhenChecked = false

    init(receiverName: String = "") {
        self.receiverName = receiverName
    }

    // MARK: - Receiver

    var trimmedReceiverName: String {
        receiverName.trimmingCharacters(in: .whitespaces)
    }

    /// Editing the name drops the result of the last check.
    mutating func setReceiverName(_ name: String) {
        guard name != receiverName else {
            return
        }
        receiverName = name
        receiver = .unchecked
        sendWhenChecked = false
    }

    mutating func beginNameCheck() {
        receiver = .checking
    }

    /// Stores the answer of the name check. Returns false when it is for a name that is not in the field anymore.
    ///
    /// The char server answers with the name it was asked for, and with character id 0 when it knows no such
    /// character (`mapif_parse_Mail_receiver_check`).
    @discardableResult
    mutating func applyNameCheck(name: String, characterID: UInt32, job: Int, baseLevel: Int) -> Bool {
        guard name == trimmedReceiverName else {
            return false
        }
        receiver = characterID == 0 ? .notFound : .found(characterID: characterID, job: job, baseLevel: baseLevel)
        return true
    }

    var receiverCharacterID: UInt32? {
        if case .found(let characterID, _, _) = receiver {
            characterID
        } else {
            nil
        }
    }

    // MARK: - Attachments

    var canAttachMore: Bool {
        attachments.count < Self.maxAttachments
    }

    func attachedAmount(index: Int) -> Int {
        attachments.first { $0.index == index }?.amount ?? 0
    }

    /// The server accepted an item. Another request for an item already attached adds to its amount.
    mutating func attach(_ attachment: Attachment, weight: Int) {
        if let position = attachments.firstIndex(where: { $0.index == attachment.index }) {
            attachments[position].amount += attachment.amount
        } else {
            attachments.append(attachment)
        }
        attachedWeight = weight
    }

    /// The server removed `count` of the item from the mail.
    mutating func detach(index: Int, count: Int, weight: Int) {
        if let position = attachments.firstIndex(where: { $0.index == index }) {
            attachments[position].amount -= count
            if attachments[position].amount <= 0 {
                attachments.remove(at: position)
            }
        }
        attachedWeight = weight
    }

    mutating func removeAllAttachments() {
        attachments = []
        attachedWeight = 0
    }

    // MARK: - Fees and checks

    /// What the server takes besides the zeny: the zeny fee and the price of every attached item
    /// (`mail_setattachment`, `mail_removezeny`).
    var fee: Int64 {
        zeny * Self.zenyFeePercent / 100 + Int64(attachments.count) * Self.attachmentFee
    }

    var totalCost: Int64 {
        zeny + fee
    }

    static func byteCount(of text: String) -> Int {
        text.utf8.count
    }

    /// The title of a reply: "RE: " and the title, cut to what the server keeps.
    static func replyTitle(to title: String) -> String {
        let prefix = "RE: "
        var reply = title.hasPrefix(prefix) ? title : prefix + title
        while byteCount(of: reply) > maxTitleBytes {
            reply.removeLast()
        }
        return reply
    }

    /// The first thing that stops the mail from being sent. A receiver that was not checked yet is not one,
    /// the check runs when the mail is sent.
    func problem(playerZeny: Int) -> Problem? {
        let receiverName = trimmedReceiverName
        if receiverName.isEmpty {
            return .emptyReceiver
        }
        if Self.byteCount(of: receiverName) > Self.maxReceiverBytes {
            return .receiverTooLong
        }
        if receiver == .notFound {
            return .receiverNotFound
        }
        // The server drops a mail without a title and does not answer.
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }
        if Self.byteCount(of: title) > Self.maxTitleBytes {
            return .titleTooLong
        }
        if Self.byteCount(of: body) > Self.maxBodyBytes {
            return .bodyTooLong
        }
        if totalCost > Int64(playerZeny) {
            return .notEnoughZeny
        }
        if !isServerReady {
            return .notReady
        }
        return nil
    }
}
