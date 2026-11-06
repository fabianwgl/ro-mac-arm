//
//  AttendancePacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Attendance packet factory")
struct AttendancePacketFactoryTests {
    @Test func openAttendanceUI() throws {
        // IN_UI_ATTENDANCE is 5 in rAthena's clif.hpp.
        let packet = PacketFactory.CZ_OPEN_UI(uiType: 5)

        #expect(packet.packetType == HEADER_CZ_OPEN_UI)
        #expect(packet.UIType == 5)
        #expect([UInt8](try PacketEncoder().encode(packet)) == [0x68, 0x0a, 0x05])
    }

    @Test func checkAttendance() throws {
        let packet = PacketFactory.CZ_REQ_CHECK_ATTENDANCE()

        #expect(packet.packetType == HEADER_CZ_REQ_CHECK_ATTENDANCE)
        #expect([UInt8](try PacketEncoder().encode(packet)) == [0xef, 0x0a])
    }
}
