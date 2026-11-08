//
//  TradeHeaders.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Client to server trade opcodes at PACKETVER 20211103. clif_packetdb.hpp registers them with raw numbers
// (`parseable_packet(0x00e4, 6, clif_parse_TradeRequest, 2)`) and rAthena has no HEADER_* constant for them
// except `HEADER_CZ_ADD_EXCHANGE_ITEM`, so the names are the ones its comments give.

/// `CZ_REQ_EXCHANGE_ITEM`, `clif_parse_TradeRequest`. Asks another player, by account id, to trade.
public let HEADER_CZ_REQ_EXCHANGE_ITEM: Int16 = 0xe4

/// `CZ_ACK_EXCHANGE_ITEM`, `clif_parse_TradeAck`. Accepts (3) or declines (4) a trade request.
public let HEADER_CZ_ACK_EXCHANGE_ITEM: Int16 = 0xe6

/// `CZ_CONCLUDE_EXCHANGE_ITEM`, `clif_parse_TradeOk`. Locks this side of the deal.
public let HEADER_CZ_CONCLUDE_EXCHANGE_ITEM: Int16 = 0xeb

/// `CZ_CANCEL_EXCHANGE_ITEM`, `clif_parse_TradeCancel`.
public let HEADER_CZ_CANCEL_EXCHANGE_ITEM: Int16 = 0xed

/// `CZ_EXEC_EXCHANGE_ITEM`, `clif_parse_TradeCommit`. Confirms the locked deal.
public let HEADER_CZ_EXEC_EXCHANGE_ITEM: Int16 = 0xef
