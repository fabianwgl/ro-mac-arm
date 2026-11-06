//
//  PACKET_CZ_CHANGE_GROUP_MASTER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_CZ_CHANGE_GROUP_MASTER: Int16 = 0x7da

public struct PACKET_CZ_CHANGE_GROUP_MASTER: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_CHANGE_GROUP_MASTER
    public var AID: UInt32 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
    }
}
