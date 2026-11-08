//
//  PACKET_CZ_REQ_CLICK_TO_BUYING_STORE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Asks a buying store for its item list. See `clif_parse_ReqClickBuyingStore` and `buyingstore_open`.
///
///     0817 <buyer account id>.L
///
/// rAthena answers with `ZC_ACK_ITEMLIST_BUYING_STORE` (0x818). It stays silent when the buyer is not
/// buying, or farther away than the view range.
public struct PACKET_CZ_REQ_CLICK_TO_BUYING_STORE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_CLICK_TO_BUYING_STORE
    public var AID: UInt32

    public init(AID: UInt32 = 0) {
        self.AID = AID
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
    }
}
