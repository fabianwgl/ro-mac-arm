//
//  PACKET_CZ_REQ_CLOSESTORE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Closes the player's own shop. See `clif_parse_CloseVending` and `vending_closevending`.
///
///     012e
///
/// rAthena removes the shop sign from everyone else and sends nothing back. It does not close an empty
/// shop by itself either, so the client sends this when the last item is sold.
public struct PACKET_CZ_REQ_CLOSESTORE: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_CLOSESTORE

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
