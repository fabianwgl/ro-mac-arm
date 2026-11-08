//
//  AppraisalTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

@MainActor
struct AppraisalTests {
    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = 2_000_010
        var character = CharacterInfo()
        character.charID = 150_010
        character.name = "Appraiser"

        let context = GameContext.testing
        let session = PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )

        var knife = InventoryItem()
        knife.index = 4
        knife.itemID = 1201
        knife.type = .weapon
        knife.amount = 1
        knife.isIdentified = false
        session.inventory.append(item: knife)

        var cap = InventoryItem()
        cap.index = 5
        cap.itemID = 2220
        cap.type = .armor
        cap.amount = 1
        cap.isIdentified = false
        session.inventory.append(item: cap)
        return session
    }

    private func list(_ indices: [UInt16]) throws -> PACKET_ZC_ITEMIDENTIFY_LIST {
        let data = Data(
            [0x77, 0x01]
                + withUnsafeBytes(of: UInt16(4 + indices.count * 2).littleEndian) { Array($0) }
                + indices.flatMap { withUnsafeBytes(of: $0.littleEndian) { Array($0) } }
        )
        var packets: [any DecodablePacket] = []
        try PacketDecoder().decode(from: data) { packets.append($0) }
        return try #require(packets.first as? PACKET_ZC_ITEMIDENTIFY_LIST)
    }

    private func ack(index: UInt16, result: UInt8) -> PACKET_ZC_ACK_ITEMIDENTIFY {
        var packet = PACKET_ZC_ACK_ITEMIDENTIFY()
        packet.packetType = HEADER_ZC_ACK_ITEMIDENTIFY
        packet.index = index
        packet.result = result
        return packet
    }

    @Test func noPickerBeforeTheServerSendsTheList() {
        let session = makeSession()

        #expect(session.appraisal.isPickerOpen == false)
        #expect(session.appraisal.candidateIndices == nil)
    }

    @Test func listOpensThePickerWithTheClientIndices() throws {
        let session = makeSession()

        #expect(session.handleAppraisalPacket(try list([4, 5])))

        #expect(session.appraisal.isPickerOpen)
        #expect(session.appraisal.candidateIndices == [4, 5])
    }

    @Test func aNewListReplacesTheOldOne() throws {
        let session = makeSession()
        _ = session.handleAppraisalPacket(try list([4, 5]))

        _ = session.handleAppraisalPacket(try list([5]))

        #expect(session.appraisal.candidateIndices == [5])
    }

    @Test func pickingAnOfferedItemClosesThePicker() throws {
        let session = makeSession()
        _ = session.handleAppraisalPacket(try list([4, 5]))

        session.appraiseItem(at: 5)

        #expect(session.appraisal.isPickerOpen == false)
    }

    @Test func pickingAnItemTheServerDidNotOfferKeepsThePicker() throws {
        let session = makeSession()
        _ = session.handleAppraisalPacket(try list([4]))

        session.appraiseItem(at: 5)

        #expect(session.appraisal.candidateIndices == [4])
    }

    @Test func pickingWithoutAPickerDoesNothing() {
        let session = makeSession()

        session.appraiseItem(at: 4)

        #expect(session.appraisal.isPickerOpen == false)
    }

    @Test func cancelClosesThePicker() throws {
        let session = makeSession()
        _ = session.handleAppraisalPacket(try list([4, 5]))

        session.cancelAppraisal()

        #expect(session.appraisal.isPickerOpen == false)
        // Nothing was identified.
        #expect(session.inventory.items[4]?.isIdentified == false)
        #expect(session.inventory.items[5]?.isIdentified == false)
    }

    @Test func successIdentifiesTheItemAndSaysSo() {
        let session = makeSession()

        #expect(session.handleAppraisalPacket(ack(index: 4, result: 0)))

        #expect(session.inventory.items[4]?.isIdentified == true)
        #expect(session.inventory.items[5]?.isIdentified == false)
        #expect(session.messageCenter.messages.last?.content.hasPrefix("Appraised: ") == true)
        #expect(session.messageCenter.messages.last?.type == .system)
    }

    @Test func failureKeepsTheFlagAndShowsAnError() {
        let session = makeSession()

        #expect(session.handleAppraisalPacket(ack(index: 4, result: 1)))

        #expect(session.inventory.items[4]?.isIdentified == false)
        #expect(session.messageCenter.messages.last?.content == "The item could not be appraised.")
        #expect(session.messageCenter.messages.last?.type == .error)
    }

    @Test func successForAnItemNotInTheInventoryIsReportedAsFailure() {
        let session = makeSession()

        _ = session.handleAppraisalPacket(ack(index: 40, result: 0))

        #expect(session.messageCenter.messages.last?.type == .error)
    }

    @Test func otherPacketsAreNotHandled() {
        let session = makeSession()

        #expect(session.handleAppraisalPacket(PACKET_ZC_CARTOFF()) == false)
    }
}
