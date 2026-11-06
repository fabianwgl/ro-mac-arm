//
//  HEADER_CZ_OPEN_UI.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

/// `clif_parse_open_ui` reads 0x0a68 with one `UIType` byte (``PACKET_CZ_OPEN_UI``).
///
/// The generated packet has no header constant. The UI types rAthena accepts are `IN_UI_MACRO_REGISTER` (2),
/// `IN_UI_MACRO_DETECTOR` (3) and `IN_UI_ATTENDANCE` (5).
public let HEADER_CZ_OPEN_UI: Int16 = 0xa68
