//
//  PACKET_CZ_ACK_REQ_ADD_FRIENDS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_CZ_ACK_REQ_ADD_FRIENDS: Int16 = 0x208

public struct PACKET_CZ_ACK_REQ_ADD_FRIENDS: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_ACK_REQ_ADD_FRIENDS
    public var AID: UInt32 = 0
    public var CID: UInt32 = 0
    public var flag: UInt32 = 0  // 0x0208 is 14 bytes at PACKETVER 20211103

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
        try encoder.encode(CID)
        try encoder.encode(flag)
    }
}
