//
//  PACKET_CZ_COMMAND_MER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

let ENTRY_CZ_COMMAND_MER = packetDatabase.entry(forFunctionName: "clif_parse_HomMenu")!

/// A homunculus menu action, `022d <type>.W <command>.B`. See `clif_parse_HomMenu` and `hom_menu`.
public struct PACKET_CZ_COMMAND_MER: EncodablePacket {
    public enum Command: UInt8, Sendable {
        /// The server does nothing for it. The information comes with `ZC_PROPERTY_HOMUN`.
        case information = 0
        case feed = 1
        /// Deletes the homunculus for good.
        case delete = 2
    }

    public let packetType: Int16
    /// Always 0.
    public var type: UInt16
    public var command: UInt8

    public init() {
        packetType = ENTRY_CZ_COMMAND_MER.packetType
        type = 0
        command = 0
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_COMMAND_MER.packetLength
        let offsets = ENTRY_CZ_COMMAND_MER.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)
        data.replaceSubrange(from: offsets[0], with: type)
        data.replaceSubrange(from: offsets[1], with: command)

        try encoder.encode(data)
    }
}
