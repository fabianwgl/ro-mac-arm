//
//  PACKET_CZ_REQ_CHECK_ATTENDANCE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_CZ_REQ_CHECK_ATTENDANCE: Int16 = 0xaef

/// Asks the map server for today's attendance reward.
///
/// rAthena does not name this packet; `clif_parse_attendance_request` reads 0x0aef with no fields.
/// The server answers with ``PACKET_ZC_ACK_CHECK_ATTENDANCE`` and mails the reward, or stays silent when
/// it refuses the request (no running period, already rewarded today, not permitted).
public struct PACKET_CZ_REQ_CHECK_ATTENDANCE: CodablePacket {
    public static var size: Int {
        2
    }

    public var packetType: Int16 = HEADER_CZ_REQ_CHECK_ATTENDANCE

    public init() {
    }

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
    }
}
