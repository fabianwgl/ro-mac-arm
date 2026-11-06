//
//  PACKET_CZ_RENAME_MER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

let ENTRY_CZ_RENAME_MER = packetDatabase.entry(forFunctionName: "clif_parse_ChangeHomunculusName")!

/// `0231 <name>.24B`. See `clif_parse_ChangeHomunculusName`.
public struct PACKET_CZ_RENAME_MER: EncodablePacket {
    public let packetType: Int16
    public var name: String

    public init() {
        packetType = ENTRY_CZ_RENAME_MER.packetType
        name = ""
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_RENAME_MER.packetLength
        let offsets = ENTRY_CZ_RENAME_MER.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)

        // The server reads a NUL terminated string, so at most 23 bytes of the 24 are used.
        let nameBytes = Array(name.utf8.prefix(23))
        data.replaceSubrange(from: offsets[0], with: nameBytes)

        try encoder.encode(data)
    }
}
