//
//  PACKET_CZ_CONFIG.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

let ENTRY_CZ_CONFIG = packetDatabase.entry(forFunctionName: "clif_parse_configuration")!

/// A client option, `02d8 <type>.L <flag>.L`. The server answers with `ZC_CONFIG` when it accepts
/// the change. See `clif_parse_configuration` and `e_config_type`.
public struct PACKET_CZ_CONFIG: EncodablePacket {
    public enum ConfigType: UInt32, Sendable {
        case openEquipmentWindow = 0
        case call = 1
        case petAutofeed = 2
        case homunculusAutofeed = 3
        case disableShowCostumes = 5
    }

    public let packetType: Int16
    public var type: UInt32
    public var flag: UInt32

    public init() {
        packetType = ENTRY_CZ_CONFIG.packetType
        type = 0
        flag = 0
    }

    public func encode(to encoder: BinaryEncoder) throws {
        let packetLength = ENTRY_CZ_CONFIG.packetLength
        let offsets = ENTRY_CZ_CONFIG.offsets

        var data = [UInt8](repeating: 0, count: Int(packetLength))
        data.replaceSubrange(from: 0, with: packetType)
        data.replaceSubrange(from: offsets[0], with: type)
        data.replaceSubrange(from: offsets[1], with: flag)

        try encoder.encode(data)
    }
}
