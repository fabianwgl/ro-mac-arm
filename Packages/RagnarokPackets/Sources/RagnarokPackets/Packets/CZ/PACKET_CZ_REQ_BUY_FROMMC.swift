//
//  PACKET_CZ_REQ_BUY_FROMMC.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Asks a vendor's shop for its item list. See `clif_parse_VendingListReq` and `vending_vendinglistreq`.
///
///     0130 <vender account id>.L
///
/// rAthena answers with `ZC_PC_PURCHASE_ITEMLIST_FROMMC` (0xb3d) and remembers the shop id the player
/// is looking at. It stays silent when the target is not vending, so the client may get no answer at all.
public struct PACKET_CZ_REQ_BUY_FROMMC: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_BUY_FROMMC
    public var AID: UInt32

    public init(AID: UInt32 = 0) {
        self.AID = AID
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
    }
}
