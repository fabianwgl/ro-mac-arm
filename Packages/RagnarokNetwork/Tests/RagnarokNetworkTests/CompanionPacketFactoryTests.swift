//
//  CompanionPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Pet and homunculus packet factory")
struct CompanionPacketFactoryTests {
    private func encode(_ packet: some EncodablePacket) throws -> [UInt8] {
        [UInt8](try PacketEncoder().encode(packet))
    }

    private func paddedName(_ string: String) -> [UInt8] {
        let bytes = Array(string.utf8)
        return bytes + [UInt8](repeating: 0, count: 24 - bytes.count)
    }

    @Test func petCommands() throws {
        // clif_parse_PetMenu: 01a1 <type>.B
        #expect(try encode(PacketFactory.CZ_COMMAND_PET(command: .information)) == [0xa1, 0x01, 0x00])
        #expect(try encode(PacketFactory.CZ_COMMAND_PET(command: .feed)) == [0xa1, 0x01, 0x01])
        #expect(try encode(PacketFactory.CZ_COMMAND_PET(command: .performance)) == [0xa1, 0x01, 0x02])
        #expect(try encode(PacketFactory.CZ_COMMAND_PET(command: .returnToEgg)) == [0xa1, 0x01, 0x03])
        #expect(try encode(PacketFactory.CZ_COMMAND_PET(command: .unequipAccessory)) == [0xa1, 0x01, 0x04])
    }

    @Test func renamePet() throws {
        // clif_parse_ChangePetName: 01a5 <name>.24B
        let data = try encode(PacketFactory.CZ_RENAME_PET(name: "Poring"))
        #expect(data == [0xa5, 0x01] + paddedName("Poring"))
    }

    @Test func selectPetEgg() throws {
        // clif_parse_SelectEgg: 01a7 <index>.W
        #expect(try encode(PacketFactory.CZ_SELECT_PETEGG(index: 7)) == [0xa7, 0x01, 0x07, 0x00])
        #expect(try encode(PacketFactory.CZ_SELECT_PETEGG(index: PACKET_CZ_SELECT_PETEGG.cancelIndex)) == [0xa7, 0x01, 0xff, 0xff])
    }

    @Test func homunculusCommands() throws {
        // clif_parse_HomMenu: 022d <type>.W <command>.B
        #expect(try encode(PacketFactory.CZ_COMMAND_MER(command: .feed)) == [0x2d, 0x02, 0x00, 0x00, 0x01])
        #expect(try encode(PacketFactory.CZ_COMMAND_MER(command: .delete)) == [0x2d, 0x02, 0x00, 0x00, 0x02])
    }

    @Test func renameHomunculus() throws {
        // clif_parse_ChangeHomunculusName: 0231 <name>.24B
        let data = try encode(PacketFactory.CZ_RENAME_MER(name: "Lif"))
        #expect(data == [0x31, 0x02] + paddedName("Lif"))
    }

    @Test func moveToOwner() throws {
        // clif_parse_HomMoveToMaster: 0234 <id>.L
        let data = try encode(PacketFactory.CZ_REQUEST_MOVETOOWNER(objectID: 0x0100_0002))
        #expect(data == [0x34, 0x02, 0x02, 0x00, 0x00, 0x01])
    }

    @Test func autoFeedConfig() throws {
        // clif_parse_configuration: 02d8 <type>.L <flag>.L
        let petOn = try encode(PacketFactory.CZ_CONFIG(type: .petAutofeed, enabled: true))
        #expect(petOn == [0xd8, 0x02, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])

        let homunculusOff = try encode(PacketFactory.CZ_CONFIG(type: .homunculusAutofeed, enabled: false))
        #expect(homunculusOff == [0xd8, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
}
