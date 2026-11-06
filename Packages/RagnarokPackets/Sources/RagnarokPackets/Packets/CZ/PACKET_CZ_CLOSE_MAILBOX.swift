//
//  PACKET_CZ_CLOSE_MAILBOX.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// Sent when the RODEX window closes. rAthena parses it with `clif_parse_dull`.
public struct PACKET_CZ_CLOSE_MAILBOX: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_CLOSE_MAILBOX

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
