//
//  RodexPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  The bytes of the RODEX requests against what rAthena reads at PACKETVER 20211103
//  (clif_parse_Mail_* in clif.cpp, offsets and sizes from clif_packetdb.hpp).
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("RODEX packet factory")
struct RodexPacketFactoryTests {
    private func bytes(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func int16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func int64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(bytes[offset + $1]) << UInt64($1 * 8) }
    }

    @Test func openMailboxIsTwentySixBytes() throws {
        let data = try bytes(PacketFactory.CZ_REQ_OPEN_MAIL())
        #expect(data.count == 26)
        #expect(int16(data, at: 0) == 0xac0)
        #expect(int64(data, at: 2) == 0)
    }

    @Test func refreshIsTwentySixBytes() throws {
        let data = try bytes(PacketFactory.CZ_REQ_REFRESH_MAIL_LIST())
        #expect(data.count == 26)
        #expect(int16(data, at: 0) == 0xac1)
    }

    @Test func nextPageCarriesTabAndLastMailID() throws {
        let data = try bytes(PacketFactory.CZ_REQ_NEXT_MAIL_LIST(openType: 1, lastMailID: 77))
        #expect(data.count == 11)
        #expect(int16(data, at: 0) == 0x9ee)
        #expect(data[2] == 1)
        #expect(int64(data, at: 3) == 77)
    }

    @Test func readAndDeleteUseTabThenMailID() throws {
        let read = try bytes(PacketFactory.CZ_REQ_READ_MAIL(openType: 0, mailID: 1234))
        #expect(read.count == 11)
        #expect(int16(read, at: 0) == 0x9ea)
        #expect(read[2] == 0)
        #expect(int64(read, at: 3) == 1234)

        let delete = try bytes(PacketFactory.CZ_REQ_DELETE_MAIL(openType: 1, mailID: 1234))
        #expect(delete.count == 11)
        #expect(int16(delete, at: 0) == 0x9f5)
        #expect(delete[2] == 1)
        #expect(int64(delete, at: 3) == 1234)
    }

    @Test func takeRequestsUseMailIDThenTab() throws {
        let zeny = try bytes(PacketFactory.CZ_REQ_ZENY_FROM_MAIL(openType: 1, mailID: 55))
        #expect(zeny.count == 11)
        #expect(int16(zeny, at: 0) == 0x9f1)
        #expect(int64(zeny, at: 2) == 55)
        #expect(zeny[10] == 1)

        let items = try bytes(PacketFactory.CZ_REQ_ITEM_FROM_MAIL(openType: 0, mailID: 55))
        #expect(items.count == 11)
        #expect(int16(items, at: 0) == 0x9f3)
        #expect(int64(items, at: 2) == 55)
        #expect(items[10] == 0)
    }

    @Test func closeAndCancelAreTwoBytes() throws {
        let close = try bytes(PacketFactory.CZ_CLOSE_MAILBOX())
        #expect(close == [0xe9, 0x09])

        let cancel = try bytes(PacketFactory.CZ_REQ_CANCEL_WRITE_MAIL())
        #expect(cancel == [0x03, 0x0a])
    }

    @Test func openWriteCarriesReceiverName() throws {
        let data = try bytes(PacketFactory.CZ_REQ_OPEN_WRITE_MAIL(receiverName: "Poring"))
        #expect(data.count == 26)
        #expect(int16(data, at: 0) == 0xa08)
        #expect(Array(data[2..<8]) == [UInt8]("Poring".utf8))
        #expect(data[8] == 0)
    }

    @Test func nameCheckHasOwnCharacterFlag() throws {
        let data = try bytes(PacketFactory.CZ_CHECKNAME2(name: "Poring"))
        #expect(data.count == 27)
        #expect(int16(data, at: 0) == 0xb97)
        #expect(Array(data[2..<8]) == [UInt8]("Poring".utf8))
        #expect(data[26] == 0)
    }

    @Test func attachAndDetachItem() throws {
        let add = try bytes(PacketFactory.CZ_ADD_ITEM_TO_MAIL(index: 5, count: 20))
        #expect(add.count == 6)
        #expect(int16(add, at: 0) == 0xa04)
        #expect(int16(add, at: 2) == 5)
        #expect(int16(add, at: 4) == 20)

        let remove = try bytes(PacketFactory.CZ_REQ_REMOVE_ITEM_MAIL(index: 5, count: 20))
        #expect(remove.count == 6)
        #expect(int16(remove, at: 0) == 0xa06)
        #expect(int16(remove, at: 2) == 5)
        #expect(int16(remove, at: 4) == 20)
    }

    @Test func sendMailLayoutMatchesClifParseMailSend() throws {
        let packet = PacketFactory.CZ_SEND_MAIL(
            receiverName: "Poring",
            senderName: "Leon",
            receiverCharacterID: 150_001,
            zeny: 5_000,
            title: "Hi",
            body: "Take this."
        )
        let data = try bytes(packet)

        // headerLength is 68 for PACKETVER > 20160330, the title and the text follow with their NUL.
        let titleLength = "Hi".utf8.count + 1
        let bodyLength = "Take this.".utf8.count + 1
        #expect(data.count == 68 + titleLength + bodyLength)
        #expect(Int(int16(data, at: 2)) == data.count)

        #expect(int16(data, at: 0) == 0xa6e)
        #expect(Array(data[4..<10]) == [UInt8]("Poring".utf8))
        #expect(data[10] == 0)
        #expect(Array(data[28..<32]) == [UInt8]("Leon".utf8))
        #expect(int64(data, at: 52) == 5_000)
        #expect(Int(int16(data, at: 60)) == titleLength)
        #expect(Int(int16(data, at: 62)) == bodyLength)
        #expect(int16(data, at: 64) == UInt16(150_001 & 0xffff))
        #expect(int16(data, at: 66) == UInt16(150_001 >> 16))
        #expect(Array(data[68..<(68 + titleLength)]) == [UInt8]("Hi".utf8) + [0])
        #expect(Array(data[(68 + titleLength)...]) == [UInt8]("Take this.".utf8) + [0])
    }

    @Test func sendMailWithEmptyBodyStillCountsTheNul() throws {
        let packet = PacketFactory.CZ_SEND_MAIL(
            receiverName: "Poring",
            senderName: "Leon",
            receiverCharacterID: 1,
            zeny: 0,
            title: "Hi",
            body: ""
        )
        let data = try bytes(packet)

        #expect(Int(int16(data, at: 62)) == 1)
        #expect(data.count == 68 + 3 + 1)
        #expect(data.last == 0)
    }
}
