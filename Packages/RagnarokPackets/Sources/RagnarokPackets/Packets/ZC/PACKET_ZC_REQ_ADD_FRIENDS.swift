//
//  PACKET_ZC_REQ_ADD_FRIENDS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

public let HEADER_ZC_REQ_ADD_FRIENDS: Int16 = 0x207

public struct PACKET_ZC_REQ_ADD_FRIENDS: DecodablePacket {
    public static var size: Int {
        2 + 4 + 4 + 24
    }

    public var packetType: Int16
    public var AID: UInt32
    public var CID: UInt32
    public var name: String

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        AID = try decoder.decode(UInt32.self)
        CID = try decoder.decode(UInt32.self)
        name = try decoder.decode(String.self, lengthOfBytes: 24, encoding: .utf8)
    }
}
