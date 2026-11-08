//
//  PACKET_CZ_REQ_ITEMIDENTIFY+Cancel.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

extension PACKET_CZ_REQ_ITEMIDENTIFY {
    /// The index that cancels the appraisal. `0178 <index>.W`, where -1 means cancel: the server turns it into
    /// an out of range slot, leaves the appraisal menu and identifies nothing. See `clif_parse_ItemIdentify`.
    public static let cancelIndex: UInt16 = 0xFFFF
}

extension PACKET_ZC_ACK_ITEMIDENTIFY {
    /// `0179 <index>.W <result>.B`, where 0 is success and 1 is failure. See `clif_item_identified`.
    public var isSuccess: Bool {
        result == 0
    }
}
