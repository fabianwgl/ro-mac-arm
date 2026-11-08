//
//  PACKET_ZC_ITEMIDENTIFY_LIST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_ITEMIDENTIFY_LIST: Int16 = 0x177

/// The unidentified inventory items which can be appraised, sent when a Magnifier or the Item Appraisal skill
/// is used.
///
/// `0177 <packet len>.W { <index>.W }*`. The indices are client inventory indices (server index + 2) and go back
/// unchanged in `CZ_REQ_ITEMIDENTIFY`. See `clif_item_identify_list`.
public struct PACKET_ZC_ITEMIDENTIFY_LIST: DecodablePacket {
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
