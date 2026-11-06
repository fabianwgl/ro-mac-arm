//
//  PACKET_ZC_PETEGG_LIST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_PETEGG_LIST: Int16 = 0x1a6

/// The pet eggs which can be hatched, sent when a pet incubator is used.
///
/// `01a6 <packet len>.W { <index>.W }*`. The indices are client inventory indices
/// (server index + 2) and go back unchanged in `CZ_SELECT_PETEGG`. See `clif_sendegg`.
public struct PACKET_ZC_PETEGG_LIST: DecodablePacket {
    public static var size: Int {
        -1
    }

    public var packetType: Int16
    public var packetLength: Int16
    public var indices: [UInt16]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)

        let count = max((Int(packetLength) - 4) / 2, 0)
        indices = []
        indices.reserveCapacity(count)
        for _ in 0..<count {
            indices.append(try decoder.decode(UInt16.self))
        }
    }
}
