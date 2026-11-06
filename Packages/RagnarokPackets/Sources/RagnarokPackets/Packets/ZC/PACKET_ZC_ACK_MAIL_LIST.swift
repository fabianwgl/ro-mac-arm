//
//  PACKET_ZC_ACK_MAIL_LIST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

extension BinaryDecoder {
    /// Reads `lengthOfBytes` bytes and returns the text up to the first NUL.
    ///
    /// Mail text is typed by players in whatever encoding their client uses, so invalid UTF-8 is replaced
    /// instead of failing the whole packet.
    func decodeLossyString(lengthOfBytes length: Int) throws -> String {
        guard length > 0 else {
            return ""
        }
        let bytes = try decode([UInt8].self, count: length)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// Lists the mails of the inbox.
///
/// See `clif_Mail_refreshinbox`. At PACKETVER 20170419 and later rAthena sends 0xac2 with every mail of all
/// three tabs at once, newest first, and never pages:
///
///     0ac2 <packet len>.W <is end>.B
///         { <tab>.B <mail id>.Q <read>.B <type>.B <sender>.24B <expires in>.L <title length>.W <title>.?B }*
///
/// Before that the list was 0x9f0 and 0xa7d, one tab and one page of 7 mails at a time.
public struct PACKET_ZC_ACK_MAIL_LIST: DecodablePacket {
    public static var size: Int {
        -1
    }

    /// Bytes of one entry before the title.
    static let entryHeaderSize = 1 + 8 + 1 + 1 + 24 + 4 + 2

    public var packetType: Int16
    public var packetLength: Int16

    /// rAthena writes 1 here (its source comment says "unknown").
    public var isEnd: UInt8
    public var mails: [PACKET_ZC_ACK_MAIL_LIST_sub]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)
        isEnd = try decoder.decode(UInt8.self)

        mails = []
        var remaining = Int(packetLength) - (2 + 2 + 1)
        while remaining >= Self.entryHeaderSize {
            let mail = try decoder.decode(PACKET_ZC_ACK_MAIL_LIST_sub.self)
            remaining -= Self.entryHeaderSize + mail.titleLength
            guard remaining >= 0 else {
                throw PacketDecodingError.invalidPacketLength(packetType, Int(packetLength))
            }
            mails.append(mail)
        }
    }
}

public struct PACKET_ZC_ACK_MAIL_LIST_sub: BinaryDecodable, Sendable {
    /// 0 = mail, 1 = account, 2 = returned (`enum mail_inbox_type`).
    public var tab: UInt8
    public var mailID: Int64
    public var isRead: UInt8

    /// Bit flags: 0x2 zeny, 0x4 items, 0x8 sent by an NPC (`enum mail_type`).
    public var type: UInt8
    public var sender: String

    /// Seconds until the mail is deleted. rAthena sends one year when no deletion is scheduled.
    public var expiresIn: UInt32

    /// Length of the title in the packet, with its terminating NUL.
    public var titleLength: Int
    public var title: String

    public init(from decoder: BinaryDecoder) throws {
        tab = try decoder.decode(UInt8.self)
        mailID = try decoder.decode(Int64.self)
        isRead = try decoder.decode(UInt8.self)
        type = try decoder.decode(UInt8.self)
        sender = try decoder.decodeLossyString(lengthOfBytes: 24)
        expiresIn = try decoder.decode(UInt32.self)
        titleLength = Int(try decoder.decode(UInt16.self))
        title = try decoder.decodeLossyString(lengthOfBytes: titleLength)
    }
}
