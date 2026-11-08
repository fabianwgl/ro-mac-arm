//
//  BuyingStorePackets.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

// The small buying store notifications that the generated packets lack: rAthena writes them with
// WFIFOW/WFIFOL at fixed offsets (clif_buyingstore_*) and has no struct or HEADER_* constant for them.

/// `ZC_OPEN_BUYING_STORE`.
public let HEADER_ZC_OPEN_BUYING_STORE: Int16 = 0x810

/// `ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER`.
public let HEADER_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER: Int16 = 0x812

/// `ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER`.
public let HEADER_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER: Int16 = 0x81a

/// `ZC_ITEM_DELETE_BUYING_STORE`.
public let HEADER_ZC_ITEM_DELETE_BUYING_STORE: Int16 = 0x81c

/// Opens the buying store set up window. See `clif_buyingstore_open`, which the `buyingstore` script command calls.
///
///     0810 <slots>.B
public struct PACKET_ZC_OPEN_BUYING_STORE: DecodablePacket {
    public static var size: Int {
        2 + 1
    }

    public var packetType: Int16

    /// How many different items the store takes.
    public var slots: UInt8

    public init(slots: UInt8 = 0) {
        self.packetType = HEADER_ZC_OPEN_BUYING_STORE
        self.slots = slots
    }

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        slots = try decoder.decode(UInt8.self)
    }
}

/// The store could not be created. See `clif_buyingstore_open_failed`.
///
///     0812 <result>.W <total weight>.L
///
/// `result`: 1 failed, 2 the items would overweight the buyer (the weight is in tenths), 8 no sale information.
public struct PACKET_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER: DecodablePacket {
    public static var size: Int {
        2 + 2 + 4
    }

    public var packetType: Int16
    public var result: UInt16
    public var totalWeight: UInt32

    public init(result: UInt16 = 0, totalWeight: UInt32 = 0) {
        self.packetType = HEADER_ZC_FAILED_OPEN_BUYING_STORE_TO_BUYER
        self.result = result
        self.totalWeight = totalWeight
    }

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        result = try decoder.decode(UInt16.self)
        totalWeight = try decoder.decode(UInt32.self)
    }
}

/// The buyer's store closed after a trade. See `clif_buyingstore_trade_failed_buyer`.
///
///     081a <result>.W
///
/// `result`: 3 the zeny limit is reached ("All items within the buy limit were purchased."),
/// 4 everything was bought ("All items were purchased.").
public struct PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER: DecodablePacket {
    public static var size: Int {
        2 + 2
    }

    public var packetType: Int16
    public var result: UInt16

    public init(result: UInt16 = 0) {
        self.packetType = HEADER_ZC_FAILED_TRADE_BUYING_STORE_TO_BUYER
        self.result = result
    }

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        result = try decoder.decode(UInt16.self)
    }
}

/// The seller's items that went to a buying store. See `clif_buyingstore_delete_item`.
///
///     081c <index>.W <amount>.W <price>.L
///
/// rAthena sends it instead of the usual item delete (`ZC_DELETE_ITEM_FROM_BODY`), so the inventory loses the
/// items here. `price` is the price of one item, the client works the total out.
public struct PACKET_ZC_ITEM_DELETE_BUYING_STORE: DecodablePacket {
    public static var size: Int {
        2 + 2 + 2 + 4
    }

    public var packetType: Int16
    public var index: UInt16
    public var amount: UInt16
    public var price: UInt32

    public init(index: UInt16 = 0, amount: UInt16 = 0, price: UInt32 = 0) {
        self.packetType = HEADER_ZC_ITEM_DELETE_BUYING_STORE
        self.index = index
        self.amount = amount
        self.price = price
    }

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        index = try decoder.decode(UInt16.self)
        amount = try decoder.decode(UInt16.self)
        price = try decoder.decode(UInt32.self)
    }
}
