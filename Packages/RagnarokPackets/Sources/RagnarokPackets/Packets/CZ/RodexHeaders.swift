//
//  RodexHeaders.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Client to server RODEX opcodes at PACKETVER 20211103. clif_packetdb.hpp registers them with raw
// numbers (`parseable_packet(0x09EA, ...)`) and rAthena has no HEADER_* constant for them, so the
// names are the ones its comments give. The structs are the generated PACKET_CZ_* types of the same name.

/// `CZ_CLOSE_MAILBOX`, parsed by `clif_parse_dull`.
public let HEADER_CZ_CLOSE_MAILBOX: Int16 = 0x9e9

/// `CZ_REQ_READ_MAIL`, `clif_parse_Mail_read`.
public let HEADER_CZ_REQ_READ_MAIL: Int16 = 0x9ea

/// `CZ_REQ_NEXT_MAIL_LIST`, `clif_parse_Mail_refreshinbox`.
public let HEADER_CZ_REQ_NEXT_MAIL_LIST: Int16 = 0x9ee

/// `CZ_REQ_ZENY_FROM_MAIL`, `clif_parse_Mail_getattach`.
public let HEADER_CZ_REQ_ZENY_FROM_MAIL: Int16 = 0x9f1

/// `CZ_REQ_ITEM_FROM_MAIL`, `clif_parse_Mail_getattach`.
public let HEADER_CZ_REQ_ITEM_FROM_MAIL: Int16 = 0x9f3

/// `CZ_REQ_DELETE_MAIL`, `clif_parse_Mail_delete`.
public let HEADER_CZ_REQ_DELETE_MAIL: Int16 = 0x9f5

/// `CZ_REQ_CANCEL_WRITE_MAIL`, `clif_parse_Mail_cancelwrite`.
public let HEADER_CZ_REQ_CANCEL_WRITE_MAIL: Int16 = 0xa03

/// `CZ_REQ_ADD_ITEM_TO_MAIL`, `clif_parse_Mail_setattach`.
public let HEADER_CZ_REQ_ADD_ITEM_TO_MAIL: Int16 = 0xa04

/// `CZ_REQ_REMOVE_ITEM_MAIL`, `clif_parse_Mail_winopen`.
public let HEADER_CZ_REQ_REMOVE_ITEM_MAIL: Int16 = 0xa06

/// `CZ_REQ_OPEN_WRITE_MAIL`, `clif_parse_Mail_beginwrite`.
public let HEADER_CZ_REQ_OPEN_WRITE_MAIL: Int16 = 0xa08

/// `CZ_REQ_WRITE_MAIL2`, `clif_parse_Mail_send`. The layout with the receiver's character id.
public let HEADER_CZ_REQ_WRITE_MAIL2: Int16 = 0xa6e

/// `CZ_OPEN_MAILBOX2`, `clif_parse_Mail_refreshinbox`. Three mail ids, one per tab.
public let HEADER_CZ_OPEN_MAILBOX2: Int16 = 0xac0

/// `CZ_REQ_REFRESH_MAIL_LIST2`, `clif_parse_Mail_refreshinbox`. Asks the char server for the inbox again.
public let HEADER_CZ_REQ_REFRESH_MAIL_LIST2: Int16 = 0xac1
