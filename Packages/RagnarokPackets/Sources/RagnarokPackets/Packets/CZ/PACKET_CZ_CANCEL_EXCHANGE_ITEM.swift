//
//  PACKET_CZ_CANCEL_EXCHANGE_ITEM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_TradeCancel`, 2 bytes. Cancels the trade or, before the partner accepted, the trade request.
public struct PACKET_CZ_CANCEL_EXCHANGE_ITEM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_CANCEL_EXCHANGE_ITEM

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
