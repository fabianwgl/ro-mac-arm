//
//  PACKET_CZ_REQ_CANCEL_WRITE_MAIL.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_parse_Mail_cancelwrite`
///
/// rAthena blocks movement and item use while a mail is being written (`sd->state.mail_writing`) and only
/// this packet clears the flag, so the client sends it whenever the write window closes.
public struct PACKET_CZ_REQ_CANCEL_WRITE_MAIL: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_CANCEL_WRITE_MAIL

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
