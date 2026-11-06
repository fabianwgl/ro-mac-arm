//
//  PACKET_CZ_SELECT_PETEGG.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

let ENTRY_CZ_SELECT_PETEGG = packetDatabase.entry(forFunctionName: "clif_parse_SelectEgg")!

/// The answer to `ZC_PETEGG_LIST`, `01a7 <index>.W`. See `clif_parse_SelectEgg`.
public struct PACKET_CZ_SELECT_PETEGG: EncodablePacket {
    /// An index no inventory slot has. The server ignores it and still leaves the egg menu,
    /// which is how the dialog is cancelled.
    public static let cancelIndex: UInt16 = 0xFFFF

    public let packetType: Int16
    public var index: UInt16

    public init() {
        packetType = ENTRY_CZ_SELECT_PETEGG.packetType
        index = Self.cancelIndex
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_SELECT_PETEGG.packetLength
        let offsets = ENTRY_CZ_SELECT_PETEGG.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)
        data.replaceSubrange(from: offsets[0], with: index)

        try encoder.encode(data)
    }
}
