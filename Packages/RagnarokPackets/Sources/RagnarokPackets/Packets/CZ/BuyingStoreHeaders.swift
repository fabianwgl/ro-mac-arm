//
//  BuyingStoreHeaders.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Client to server buying store opcodes at PACKETVER 20211103. clif_shuffle.hpp registers the unshuffled
// ones for PACKETVER > 20180307 (`parseable_packet(0x0817, ...)`) and rAthena has no HEADER_* constant for
// them, so the names are the ones its comments give. The structs of the ones that carry a list are the
// generated PACKET_CZ_REQ_OPEN_BUYING_STORE and PACKET_CZ_REQ_TRADE_BUYING_STORE.

/// `CZ_REQ_OPEN_BUYING_STORE`, `clif_parse_ReqOpenBuyingStore`. Confirms or cancels the buying store set up window.
public let HEADER_CZ_REQ_OPEN_BUYING_STORE: Int16 = 0x811

/// `CZ_REQ_CLOSE_BUYING_STORE`, `clif_parse_ReqCloseBuyingStore`. Closes the player's own buying store.
public let HEADER_CZ_REQ_CLOSE_BUYING_STORE: Int16 = 0x815

/// `CZ_REQ_CLICK_TO_BUYING_STORE`, `clif_parse_ReqClickBuyingStore`. Asks for the item list of a buying store.
public let HEADER_CZ_REQ_CLICK_TO_BUYING_STORE: Int16 = 0x817

/// `CZ_REQ_TRADE_BUYING_STORE`, `clif_parse_ReqTradeBuyingStore`. Sells items to a buying store.
public let HEADER_CZ_REQ_TRADE_BUYING_STORE: Int16 = 0x819
