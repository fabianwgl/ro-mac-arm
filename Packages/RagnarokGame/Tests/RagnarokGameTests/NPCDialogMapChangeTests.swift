//
//  NPCDialogMapChangeTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// A map change while an NPC window is open, such as the Kafra teleport: `mes`, `select`, `warp`, then `end;` with no
/// `close;`. The window must not survive onto the new map.
@MainActor
struct NPCDialogMapChangeTests {
    private static let kafraID: UInt32 = 110_001_538
    private static let otherID: UInt32 = 110_001_539

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = 2_000_001
        var character = CharacterInfo()
        character.charID = 150_000
        character.name = "Leon"

        let context = GameContext.testing
        return PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )
    }

    private func closePacket(_ npcID: UInt32) -> PACKET_ZC_CLOSE_DIALOG {
        var packet = PACKET_ZC_CLOSE_DIALOG()
        packet.npcId = npcID
        return packet
    }

    /// The Kafra window after the destination was chosen: its text stays, the menu is gone, no button shows.
    private func openKafraWindow(_ session: PlaySession) {
        session.dialog = NPCDialog(npcID: Self.kafraID, message: "[Kafra Employee]\nPlease choose\nyour destination.")
    }

    @Test func mapChangeClosesTheOpenDialog() {
        let session = makeSession()
        openKafraWindow(session)

        session.closeDialogForMapChange()

        #expect(session.dialog == nil)
        #expect(session.npcClosedByMapChange == Self.kafraID)
    }

    @Test func mapChangeClosesADialogThatShowsAMenuOrANextButton() {
        let session = makeSession()
        session.dialog = NPCDialog(npcID: Self.kafraID, message: "Pick one.", menu: ["Save", "Cancel"])
        session.closeDialogForMapChange()
        #expect(session.dialog == nil)

        session.dialog = NPCDialog(npcID: Self.kafraID, message: "Wait.", action: .next)
        session.closeDialogForMapChange()
        #expect(session.dialog == nil)
    }

    @Test func mapChangeWithoutADialogChangesNothing() {
        let session = makeSession()

        session.closeDialogForMapChange()

        #expect(session.dialog == nil)
        #expect(session.npcClosedByMapChange == nil)
    }

    @Test func theCloseButtonThatFollowsTheWarpDoesNotReopenTheWindow() {
        let session = makeSession()
        openKafraWindow(session)
        session.closeDialogForMapChange()

        // `end;` after `warp` sends ZC_CLOSE_DIALOG right after ZC_NPCACK_MAPMOVE.
        let answered = session.handleCloseDialog(closePacket(Self.kafraID))

        #expect(answered)
        #expect(session.dialog == nil)
        #expect(session.npcClosedByMapChange == nil)
    }

    @Test func theCloseButtonIsAnsweredOnlyOnce() {
        let session = makeSession()
        openKafraWindow(session)
        session.closeDialogForMapChange()

        #expect(session.handleCloseDialog(closePacket(Self.kafraID)))
        #expect(!session.handleCloseDialog(closePacket(Self.kafraID)))
    }

    @Test func aCloseButtonOfAnotherNPCIsNotAnswered() {
        let session = makeSession()
        openKafraWindow(session)
        session.closeDialogForMapChange()

        #expect(!session.handleCloseDialog(closePacket(Self.otherID)))
        #expect(session.dialog == nil)
        #expect(session.npcClosedByMapChange == Self.kafraID)
    }

    @Test func aCloseButtonWithoutAMapChangeStillShowsTheCloseButton() {
        let session = makeSession()
        openKafraWindow(session)

        let answered = session.handleCloseDialog(closePacket(Self.kafraID))

        #expect(!answered)
        #expect(session.dialog?.action == .close)
        #expect(session.dialog?.message.contains("destination") == true)
    }

    @Test func aStrayCloseButtonWithNoDialogIsIgnored() {
        let session = makeSession()

        let answered = session.handleCloseDialog(closePacket(Self.kafraID))

        #expect(!answered)
        #expect(session.dialog == nil)
    }

    @Test func aWindowThatIsOpenWhenItsCloseButtonArrivesKeepsItsButton() {
        let session = makeSession()
        openKafraWindow(session)
        session.closeDialogForMapChange()

        // The player talks to someone else on the new map; its window is open when its close button arrives.
        session.npcClosedByMapChange = nil
        session.dialog = NPCDialog(npcID: Self.otherID, message: "Hello.")
        let answered = session.handleCloseDialog(closePacket(Self.otherID))

        #expect(!answered)
        #expect(session.dialog?.action == .close)
    }
}
