//
//  PACKET_CZ_REQ_EXCHANGE_ITEM.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_TradeRequest`: `00e4 <account id>.L`, 6 bytes.
///
/// rAthena looks the target up with `map_id2sd`, which takes the account id (the object id of a player on the map).
public struct PACKET_CZ_REQ_EXCHANGE_ITEM: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_EXCHANGE_ITEM
    public var AID: UInt32 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
    }
}
