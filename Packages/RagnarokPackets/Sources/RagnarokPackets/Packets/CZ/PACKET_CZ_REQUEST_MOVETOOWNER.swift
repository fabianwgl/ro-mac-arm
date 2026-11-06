//
//  PACKET_CZ_REQUEST_MOVETOOWNER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

let ENTRY_CZ_REQUEST_MOVETOOWNER = packetDatabase.entry(forFunctionName: "clif_parse_HomMoveToMaster")!

/// Asks a homunculus or mercenary to walk to its owner, `0234 <id>.L`. See `clif_parse_HomMoveToMaster`.
public struct PACKET_CZ_REQUEST_MOVETOOWNER: EncodablePacket {
    public let packetType: Int16
    public var GID: UInt32

    public init() {
        packetType = ENTRY_CZ_REQUEST_MOVETOOWNER.packetType
        GID = 0
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_REQUEST_MOVETOOWNER.packetLength
        let offsets = ENTRY_CZ_REQUEST_MOVETOOWNER.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)
        data.replaceSubrange(from: offsets[0], with: GID)

        try encoder.encode(data)
    }
}
