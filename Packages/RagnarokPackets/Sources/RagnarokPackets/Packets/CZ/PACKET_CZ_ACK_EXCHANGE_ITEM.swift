//
//  PACKET_CZ_ACK_EXCHANGE_ITEM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_TradeAck`: `00e6 <result>.B`, 3 bytes.
///
/// `result`: 3 = accept, 4 = decline. rAthena ignores any other value.
public struct PACKET_CZ_ACK_EXCHANGE_ITEM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_ACK_EXCHANGE_ITEM
    public var result: UInt8 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(result)
    }
}
