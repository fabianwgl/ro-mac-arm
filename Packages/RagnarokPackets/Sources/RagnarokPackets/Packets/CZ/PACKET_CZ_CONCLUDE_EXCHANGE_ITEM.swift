//
//  PACKET_CZ_CONCLUDE_EXCHANGE_ITEM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_TradeOk`, 2 bytes. Locks this side of the deal (the OK button).
/// rAthena answers with `ZC_CONCLUDE_EXCHANGE_ITEM` to both players.
public struct PACKET_CZ_CONCLUDE_EXCHANGE_ITEM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_CONCLUDE_EXCHANGE_ITEM

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
