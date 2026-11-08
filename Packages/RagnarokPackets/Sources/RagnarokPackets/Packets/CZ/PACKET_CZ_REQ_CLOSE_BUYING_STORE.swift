//
//  PACKET_CZ_REQ_CLOSE_BUYING_STORE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Closes the player's own buying store. See `clif_parse_ReqCloseBuyingStore` and `buyingstore_close`.
///
///     0815
///
/// rAthena removes the sign from everyone else and sends nothing back.
public struct PACKET_CZ_REQ_CLOSE_BUYING_STORE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_CLOSE_BUYING_STORE

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
