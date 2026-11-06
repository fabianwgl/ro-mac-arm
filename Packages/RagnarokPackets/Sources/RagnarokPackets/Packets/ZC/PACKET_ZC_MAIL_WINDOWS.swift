//
//  PACKET_ZC_MAIL_WINDOWS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_MAIL_WINDOWS: Int16 = 0x260

/// Opens or closes the mail window.
///
/// rAthena sends it from `clif_Mail_window`, which `@mail` (`mail_openmail`) calls. The `openmail` script command
/// does not call it at PACKETVER 20150513 and later, it only logs that it is unsupported.
public struct PACKET_ZC_MAIL_WINDOWS: DecodablePacket {
    public static var size: Int {
        2 + 4
    }

    public var packetType: Int16

    /// 0 = open, 1 = close.
    public var type: Int32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        type = try decoder.decode(Int32.self)
    }
}
