//
//  PACKET_ZC_ACK_CHECK_ATTENDANCE.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_ACK_CHECK_ATTENDANCE: Int16 = 0xaf0

/// Answers ``PACKET_CZ_REQ_CHECK_ATTENDANCE`` after the server rewarded the day.
///
/// rAthena does not name this packet; `clif_attendence_response` writes 0x0af0 as `<unknown>.L <data>.L`
/// with `unknown` always 0 and `data` the number of days rewarded in the period, counting today.
public struct PACKET_ZC_ACK_CHECK_ATTENDANCE: DecodablePacket {
    public static var size: Int {
        2 + 4 + 4
    }

    public var packetType: Int16
    public var unknown: UInt32
    public var rewardedDays: UInt32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        unknown = try decoder.decode(UInt32.self)
        rewardedDays = try decoder.decode(UInt32.self)
    }
}
