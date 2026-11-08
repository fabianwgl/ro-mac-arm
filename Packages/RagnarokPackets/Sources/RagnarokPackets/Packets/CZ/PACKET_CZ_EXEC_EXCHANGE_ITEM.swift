//
//  PACKET_CZ_EXEC_EXCHANGE_ITEM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_TradeCommit`, 2 bytes. Confirms the deal (the Trade button). rAthena ignores it until this
/// side is locked, and completes the trade once both sides confirmed.
public struct PACKET_CZ_EXEC_EXCHANGE_ITEM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_EXEC_EXCHANGE_ITEM

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
