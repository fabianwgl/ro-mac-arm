//
//  RodexPacketTests.swift
//  RagnarokPacketsTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  Byte level checks of the RODEX packets at PACKETVER 20211103. The layouts are the ones in rAthena's
//  clif.cpp (clif_Mail_refreshinbox, clif_Mail_read, clif_mail_getattachment, ...) and packets_struct.hpp.
//

import BinaryIO
import Foundation
import XCTest
@testable import RagnarokPackets

final class RodexPacketTests: XCTestCase {

    // MARK: - Byte helpers

    private func le(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8(value >> 8)]
    }

    private func le(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> ($0 * 8)) & 0xff) }
    }

    private func le(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((value >> ($0 * 8)) & 0xff) }
    }

    private func fixed(_ text: String, length: Int) -> [UInt8] {
        var bytes = [UInt8](text.utf8)
        bytes += [UInt8](repeating: 0, count: length - bytes.count)
        return bytes
    }

    /// One entry of 0xac2, as clif_Mail_refreshinbox writes it.
    private func listEntry(tab: UInt8, mailID: UInt64, isRead: UInt8, type: UInt8, sender: String, expiresIn: UInt32, title: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [tab]
        bytes += le(mailID)
        bytes += [isRead, type]
        bytes += fixed(sender, length: 24)
        bytes += le(expiresIn)
        bytes += le(UInt16(title.count + 1))
        bytes += title + [0]
        return bytes
    }

    private func listPacket(entries: [[UInt8]]) -> [UInt8] {
        var body: [UInt8] = [1]
        body += entries.flatMap { $0 }
        return le(UInt16(0xac2)) + le(UInt16(body.count + 4)) + body
    }

    private func decodeAll(_ bytes: [UInt8]) throws -> [any DecodablePacket] {
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: Data(bytes)) { packets.append($0) }
        return packets
    }

    // MARK: - Mail list, 0xac2

    func testMailListDecodesEveryTab() throws {
        let bytes = listPacket(entries: [
            listEntry(tab: 0, mailID: 42, isRead: 0, type: 0x6, sender: "Poring", expiresIn: 86_400, title: [UInt8]("Hello".utf8)),
            listEntry(tab: 1, mailID: 7, isRead: 1, type: 0x8, sender: "Server", expiresIn: 31_536_000, title: [UInt8]("Welcome".utf8)),
        ])

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let list = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_MAIL_LIST)
        XCTAssertEqual(list.packetType, packet_header_rodexmailList)
        XCTAssertEqual(list.isEnd, 1)
        XCTAssertEqual(list.mails.count, 2)

        XCTAssertEqual(list.mails[0].tab, 0)
        XCTAssertEqual(list.mails[0].mailID, 42)
        XCTAssertEqual(list.mails[0].isRead, 0)
        XCTAssertEqual(list.mails[0].type, 0x6)
        XCTAssertEqual(list.mails[0].sender, "Poring")
        XCTAssertEqual(list.mails[0].expiresIn, 86_400)
        XCTAssertEqual(list.mails[0].title, "Hello")

        XCTAssertEqual(list.mails[1].tab, 1)
        XCTAssertEqual(list.mails[1].mailID, 7)
        XCTAssertEqual(list.mails[1].isRead, 1)
        XCTAssertEqual(list.mails[1].type, 0x8)
        XCTAssertEqual(list.mails[1].title, "Welcome")
    }

    func testEmptyMailListIsFramed() throws {
        let notify: [UInt8] = le(UInt16(0x9e7)) + [1]
        let packets = try decodeAll(listPacket(entries: []) + notify)

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual((packets[0] as? PACKET_ZC_ACK_MAIL_LIST)?.mails.count, 0)
        XCTAssertEqual((packets[1] as? PACKET_ZC_NOTIFY_UNREADMAIL)?.result, 1)
    }

    func testMailListReplacesInvalidUTF8() throws {
        let bytes = listPacket(entries: [
            listEntry(tab: 0, mailID: 1, isRead: 0, type: 0, sender: "A", expiresIn: 1, title: [0x48, 0xff, 0x49]),
        ])

        let list = try XCTUnwrap(try decodeAll(bytes).first as? PACKET_ZC_ACK_MAIL_LIST)
        XCTAssertEqual(list.mails.first?.title, "H\u{FFFD}I")
    }

    func testMailListWithTruncatedTitleIsRejected() throws {
        var bytes = listPacket(entries: [
            listEntry(tab: 0, mailID: 1, isRead: 0, type: 0, sender: "A", expiresIn: 1, title: [UInt8]("Title".utf8)),
        ])
        // Claim a title longer than the packet.
        let titleLengthOffset = 5 + 1 + 8 + 1 + 1 + 24 + 4
        bytes[titleLengthOffset] = 200

        let stream = MemoryStream(data: Data(bytes))
        defer { stream.close() }
        XCTAssertThrowsError(try PACKET_ZC_ACK_MAIL_LIST(from: BinaryDecoder(stream: stream)))
    }

    // MARK: - Read mail, 0xb63

    private func item(itemID: UInt32, count: Int16, refine: Int8, cards: [UInt32]) throws -> [UInt8] {
        var sub = PACKET_ZC_ACK_READ_RODEX_SUB()
        sub.count = count
        sub.ITID = itemID
        sub.IsIdentified = 1
        sub.refiningLevel = refine
        var slot = EQUIPSLOTINFO()
        slot.card = cards
        sub.slot = slot

        let stream = MemoryStream()
        defer { stream.close() }
        try BinaryEncoder(stream: stream).encode(sub)
        return [UInt8](Data(stream: stream))
    }

    private func readPacket(text: String, zeny: UInt64, items: [[UInt8]]) -> [UInt8] {
        let textBytes = [UInt8](text.utf8) + [0]
        var bytes: [UInt8] = le(UInt16(0xb63))
        bytes += [0, 0]
        bytes += [1]                                 // tab
        bytes += le(UInt64(99))                      // mail id
        bytes += le(UInt16(textBytes.count))
        bytes += le(zeny)
        bytes += [UInt8(items.count)]
        bytes += textBytes
        bytes += items.flatMap { $0 }
        let length = UInt16(bytes.count)
        bytes[2] = UInt8(length & 0xff)
        bytes[3] = UInt8(length >> 8)
        return bytes
    }

    func testReadMailSplitsTextAndItems() throws {
        let bytes = readPacket(
            text: "Take the sword.",
            zeny: 1_500,
            items: [
                try item(itemID: 1101, count: 1, refine: 7, cards: [4001, 0, 0, 0]),
                try item(itemID: 501, count: 20, refine: 0, cards: [0, 0, 0, 0]),
            ]
        )

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 1)

        let mail = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_READ_MAIL)
        XCTAssertEqual(mail.tab, 1)
        XCTAssertEqual(mail.mailID, 99)
        XCTAssertEqual(mail.zeny, 1_500)
        XCTAssertEqual(mail.text, "Take the sword.")
        XCTAssertEqual(mail.items.count, 2)
        XCTAssertEqual(mail.items[0].ITID, 1101)
        XCTAssertEqual(mail.items[0].count, 1)
        XCTAssertEqual(mail.items[0].refiningLevel, 7)
        XCTAssertEqual(mail.items[0].slot.card, [4001, 0, 0, 0])
        XCTAssertEqual(mail.items[1].ITID, 501)
        XCTAssertEqual(mail.items[1].count, 20)
    }

    func testReadMailWithoutItems() throws {
        let packets = try decodeAll(readPacket(text: "(no message)", zeny: 0, items: []))
        let mail = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_READ_MAIL)
        XCTAssertEqual(mail.text, "(no message)")
        XCTAssertTrue(mail.items.isEmpty)
    }

    func testReadMailWithItemCountBeyondPacketIsRejected() throws {
        var bytes = readPacket(text: "x", zeny: 0, items: [])
        bytes[2 + 2 + 1 + 8 + 2 + 8] = 3   // item count with no item bytes behind it

        let stream = MemoryStream(data: Data(bytes))
        defer { stream.close() }
        XCTAssertThrowsError(try PACKET_ZC_ACK_READ_MAIL(from: BinaryDecoder(stream: stream)))
    }

    // MARK: - Small server packets

    func testMailWindowsAndResults() throws {
        let bytes: [UInt8] =
            le(UInt16(0x260)) + le(UInt32(0))                                  // open the window
            + le(UInt16(0x9f2)) + le(UInt64(5)) + [0, 1]                        // zeny from mail 5, tab 0, result 1
            + le(UInt16(0x9f4)) + le(UInt64(6)) + [1, 2]                        // item from mail 6, tab 1, result 2
            + le(UInt16(0x9f6)) + [0] + le(UInt64(8))                           // mail 8 deleted
            + le(UInt16(0x9ed)) + [4]                                           // send failed, receiver check
            + le(UInt16(0xa07)) + [1] + le(UInt16(3)) + le(UInt16(2)) + le(UInt16(40))

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 6)

        XCTAssertEqual((packets[0] as? PACKET_ZC_MAIL_WINDOWS)?.type, 0)

        let zeny = try XCTUnwrap(packets[1] as? PACKET_ZC_ACK_ITEM_FROM_MAIL)
        XCTAssertEqual(zeny.packetType, packet_header_rodexgetzeny)
        XCTAssertEqual(zeny.MailID, 5)
        XCTAssertEqual(zeny.opentype, 0)
        XCTAssertEqual(zeny.result, 1)

        let items = try XCTUnwrap(packets[2] as? PACKET_ZC_ACK_ITEM_FROM_MAIL)
        XCTAssertEqual(items.packetType, packet_header_rodexgetitem)
        XCTAssertEqual(items.MailID, 6)
        XCTAssertEqual(items.opentype, 1)
        XCTAssertEqual(items.result, 2)

        let deleted = try XCTUnwrap(packets[3] as? PACKET_ZC_ACK_DELETE_MAIL)
        XCTAssertEqual(deleted.MailID, 8)
        XCTAssertEqual(deleted.opentype, 0)

        XCTAssertEqual((packets[4] as? PACKET_ZC_WRITE_MAIL_RESULT)?.result, 4)

        let removed = try XCTUnwrap(packets[5] as? PACKET_ZC_ACK_REMOVE_ITEM_MAIL)
        XCTAssertEqual(removed.result, 1)
        XCTAssertEqual(removed.index, 3)
        XCTAssertEqual(removed.cnt, 2)
        XCTAssertEqual(removed.weight, 40)
    }

    func testWriteAndNameCheckPackets() throws {
        let bytes: [UInt8] =
            le(UInt16(0xa12)) + fixed("Poring", length: 24) + [1]
            + le(UInt16(0xa51)) + le(UInt32(150_001)) + le(UInt16(4001)) + le(UInt16(55)) + fixed("Poring", length: 24)

        let packets = try decodeAll(bytes)
        XCTAssertEqual(packets.count, 2)

        let open = try XCTUnwrap(packets[0] as? PACKET_ZC_ACK_OPEN_WRITE_MAIL)
        XCTAssertEqual(open.receiveName, "Poring")
        XCTAssertEqual(open.result, 1)

        let check = try XCTUnwrap(packets[1] as? PACKET_ZC_CHECKNAME)
        XCTAssertEqual(check.CharId, 150_001)
        XCTAssertEqual(check.Class, 4001)
        XCTAssertEqual(check.BaseLevel, 55)
        XCTAssertEqual(check.Name, "Poring")
    }

    func testAddItemAcknowledgeSize() throws {
        // rAthena sends sizeof(PACKET_ZC_ACK_ADD_ITEM_RODEX) for 0xb3f, with the result in the first byte.
        var bytes: [UInt8] = le(UInt16(0xb3f)) + [3]
        bytes += [UInt8](repeating: 0, count: PACKET_ZC_ACK_ADD_ITEM_RODEX.size - bytes.count)

        let packets = try decodeAll(bytes)
        let ack = try XCTUnwrap(packets.first as? PACKET_ZC_ACK_ADD_ITEM_RODEX)
        XCTAssertEqual(ack.result, 3)
    }
}
