//
//  PACKET_CZ_RENAME_PET.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

let ENTRY_CZ_RENAME_PET = packetDatabase.entry(forFunctionName: "clif_parse_ChangePetName")!

/// `01a5 <name>.24B`. See `clif_parse_ChangePetName`.
public struct PACKET_CZ_RENAME_PET: EncodablePacket {
    public let packetType: Int16
    public var name: String

    public init() {
        packetType = ENTRY_CZ_RENAME_PET.packetType
        name = ""
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_RENAME_PET.packetLength
        let offsets = ENTRY_CZ_RENAME_PET.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)

        // The server reads a NUL terminated string, so at most 23 bytes of the 24 are used.
        let nameBytes = Array(name.utf8.prefix(23))
        data.replaceSubrange(from: offsets[0], with: nameBytes)

        try encoder.encode(data)
    }
}
