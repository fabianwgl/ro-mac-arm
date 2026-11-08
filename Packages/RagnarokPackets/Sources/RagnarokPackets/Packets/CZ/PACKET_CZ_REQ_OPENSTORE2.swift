//
//  PACKET_CZ_REQ_OPENSTORE2.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Confirms or cancels the shop set up window, which `ZC_OPENSTORE` opened. See `clif_parse_OpenVending`.
///
///     01b2 <packet len>.W <shop name>.80B <result>.B { <index>.W <amount>.W <price>.L }*
///
/// `result` is 1 to open the shop and 0 to cancel. rAthena blocks the player (`state.prevend`) from the skill
/// until one of the two arrives, so a window that closes must send the cancel.
/// `index` is the cart index of the server (the cart slot plus 2).
public struct PACKET_CZ_REQ_OPENSTORE2: EncodablePacket {
    /// Bytes before the items.
    public static let headerSize = 2 + 2 + 80 + 1

    public var packetType: Int16 = HEADER_CZ_REQ_OPENSTORE2
    public var packetLength: Int16
    public var storeName: String
    public var result: UInt8
    public var items: [PACKET_CZ_REQ_OPENSTORE2_sub]

    public init(storeName: String = "", isOpening: Bool = false, items: [PACKET_CZ_REQ_OPENSTORE2_sub] = []) {
        self.packetLength = Int16(truncatingIfNeeded: Self.headerSize + items.count * PACKET_CZ_REQ_OPENSTORE2_sub.size)
        self.storeName = storeName
        self.result = isOpening ? 1 : 0
        self.items = items
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(packetLength)
        try encoder.encode(storeName, lengthOfBytes: 80, encoding: .utf8)
        try encoder.encode(result)
        try encoder.encode(items)
    }
}

public struct PACKET_CZ_REQ_OPENSTORE2_sub: BinaryEncodable, Sendable {
    public static var size: Int {
        2 + 2 + 4
    }

    public var index: UInt16
    public var amount: UInt16
    public var price: UInt32

    public init(index: UInt16, amount: UInt16, price: UInt32) {
        self.index = index
        self.amount = amount
        self.price = price
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(index)
        try encoder.encode(amount)
        try encoder.encode(price)
    }
}
