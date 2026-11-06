//
//  PACKET_ZC_ACK_READ_MAIL.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Content of one mail.
///
/// See `clif_Mail_read`. This is rAthena's `PACKET_ZC_ACK_READ_RODEX` (0xb63 at PACKETVER 20211103), which the
/// generated type cannot decode: rAthena writes the text right after the header and the items after the text,
/// but the generated type reads everything up to the packet end as text.
///
///     0b63 <packet len>.W <tab>.B <mail id>.Q <text length>.W <zeny>.Q <item count>.B
///         <text>.?B { <item> }*
public struct PACKET_ZC_ACK_READ_MAIL: DecodablePacket {
    public static var size: Int {
        -1
    }

    public var packetType: Int16
    public var packetLength: Int16

    /// 0 = mail, 1 = account, 2 = returned.
    public var tab: UInt8
    public var mailID: Int64
    public var zeny: Int64

    /// The text without its terminating NUL.
    public var text: String
    public var items: [PACKET_ZC_ACK_READ_RODEX_SUB]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)
        tab = try decoder.decode(UInt8.self)
        mailID = try decoder.decode(Int64.self)
        let textLength = Int(try decoder.decode(Int16.self))
        zeny = try decoder.decode(Int64.self)
        let itemCount = Int(try decoder.decode(UInt8.self))

        let headerSize = 2 + 2 + 1 + 8 + 2 + 8 + 1
        let expectedSize = headerSize + max(textLength, 0) + itemCount * PACKET_ZC_ACK_READ_RODEX_SUB.size
        guard textLength >= 0, expectedSize <= Int(packetLength) else {
            throw PacketDecodingError.invalidPacketLength(packetType, Int(packetLength))
        }

        text = try decoder.decodeLossyString(lengthOfBytes: textLength)
        items = try decoder.decode([PACKET_ZC_ACK_READ_RODEX_SUB].self, count: itemCount)
    }
}
