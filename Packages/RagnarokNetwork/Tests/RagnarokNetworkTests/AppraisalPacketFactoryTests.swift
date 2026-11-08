//
//  AppraisalPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Item appraisal packet factory")
struct AppraisalPacketFactoryTests {
    private func encode(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    @Test func requestCarriesTheClientIndex() throws {
        // clif_parse_ItemIdentify: 0178 <index>.W
        #expect(try encode(PacketFactory.CZ_REQ_ITEMIDENTIFY(index: 12)) == [0x78, 0x01, 0x0c, 0x00])
    }

    @Test func cancelSendsIndexMinusOne() throws {
        #expect(try encode(PacketFactory.CZ_REQ_ITEMIDENTIFY(index: PACKET_CZ_REQ_ITEMIDENTIFY.cancelIndex)) == [0x78, 0x01, 0xff, 0xff])
    }
}
