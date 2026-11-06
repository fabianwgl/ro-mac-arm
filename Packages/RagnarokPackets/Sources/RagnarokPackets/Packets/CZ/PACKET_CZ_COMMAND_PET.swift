//
//  PACKET_CZ_COMMAND_PET.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

let ENTRY_CZ_COMMAND_PET = packetDatabase.entry(forFunctionName: "clif_parse_PetMenu")!

/// A pet menu action, `01a1 <type>.B`. See `clif_parse_PetMenu` and `pet_menu`.
public struct PACKET_CZ_COMMAND_PET: EncodablePacket {
    public enum Command: UInt8, Sendable {
        /// Asks for `ZC_PROPERTY_PET`.
        case information = 0
        case feed = 1
        case performance = 2
        case returnToEgg = 3
        case unequipAccessory = 4
    }

    public let packetType: Int16
    public var command: UInt8

    public init() {
        packetType = ENTRY_CZ_COMMAND_PET.packetType
        command = 0
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_COMMAND_PET.packetLength
        let offsets = ENTRY_CZ_COMMAND_PET.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)
        data.replaceSubrange(from: offsets[0], with: command)

        try encoder.encode(data)
    }
}
