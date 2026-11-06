//
//  PACKET_CZ_WHISPER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO
import Foundation

public let HEADER_CZ_WHISPER: Int16 = 0x96

public struct PACKET_CZ_WHISPER: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_WHISPER
    public var packetLength: Int16 = 0
    public var receiver: String = ""
    public var message: String = ""

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(packetLength)
        try encoder.encode(receiver, lengthOfBytes: 24, encoding: .utf8)
        try encoder.encode(message, encoding: .utf8)
    }
}
