//
//  TradePacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//
//  The bytes of the trade requests against what rAthena reads at PACKETVER 20211103
//  (clif_parse_Trade* in clif.cpp, sizes and offsets from clif_packetdb.hpp).
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Trade packet factory")
struct TradePacketFactoryTests {
    private func bytes(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func int16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func int32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << UInt32($1 * 8) }
    }

    @Test func requestCarriesTheAccountID() throws {
        let data = try bytes(PacketFactory.CZ_REQ_EXCHANGE_ITEM(accountID: 2_000_001))
        #expect(data.count == 6)
        #expect(int16(data, at: 0) == 0xe4)
        #expect(int32(data, at: 2) == 2_000_001)
    }

    @Test func answerIsThreeToAcceptAndFourToDecline() throws {
        let accept = try bytes(PacketFactory.CZ_ACK_EXCHANGE_ITEM(accept: true))
        #expect(accept.count == 3)
        #expect(int16(accept, at: 0) == 0xe6)
        #expect(accept[2] == 3)

        let decline = try bytes(PacketFactory.CZ_ACK_EXCHANGE_ITEM(accept: false))
        #expect(decline.count == 3)
        #expect(decline[2] == 4)
    }

    @Test func addItemIsIndexThenAmount() throws {
        let data = try bytes(PacketFactory.CZ_ADD_EXCHANGE_ITEM(index: 7, amount: 250))
        #expect(data.count == 8)
        #expect(int16(data, at: 0) == 0xe8)
        #expect(int16(data, at: 2) == 7)
        #expect(int32(data, at: 4) == 250)
    }

    @Test func addZenyUsesIndexZero() throws {
        let data = try bytes(PacketFactory.CZ_ADD_EXCHANGE_ITEM(index: 0, amount: 1_000_000))
        #expect(data.count == 8)
        #expect(int16(data, at: 2) == 0)
        #expect(int32(data, at: 4) == 1_000_000)
    }

    @Test func lockCancelAndExecAreTwoBytes() throws {
        #expect(try bytes(PacketFactory.CZ_CONCLUDE_EXCHANGE_ITEM()) == [0xeb, 0x00])
        #expect(try bytes(PacketFactory.CZ_CANCEL_EXCHANGE_ITEM()) == [0xed, 0x00])
        #expect(try bytes(PacketFactory.CZ_EXEC_EXCHANGE_ITEM()) == [0xef, 0x00])
    }
}
