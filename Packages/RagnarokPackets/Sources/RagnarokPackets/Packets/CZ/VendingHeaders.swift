//
//  VendingHeaders.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Client to server vending opcodes at PACKETVER 20211103. clif_packetdb.hpp registers them with raw
// numbers (`parseable_packet(0x0130, ...)`) and rAthena has no HEADER_* constant for them, so the
// names are the ones its comments give.

/// `CZ_REQ_BUY_FROMMC`, `clif_parse_VendingListReq`. Asks for the item list of a shop
/// (the click on a vendor, `CZ_REQ_CLICK_TO_BUY_FROMMC` in other client docs).
public let HEADER_CZ_REQ_BUY_FROMMC: Int16 = 0x130
