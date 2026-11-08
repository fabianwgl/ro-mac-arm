//
//  PlaySession+NPCDialog.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets

extension PlaySession {
    /// A map change ends the conversation: the NPC is not on the new map (or is far away), so its window goes away
    /// at once, the way the reference client drops every window when the map loads. A script such as the Kafra
    /// teleport warps and then ends with its text still on screen; without this the window stayed up on the new map
    /// until the player clicked it. The server's own close packet for this dialog arrives right after the map move
    /// and is answered in `handleCloseDialog`.
    func closeDialogForMapChange() {
        guard let npcID = dialog?.npcID else {
            return
        }

        dialog = nil
        npcClosedByMapChange = npcID
    }

    /// `ZC_CLOSE_DIALOG` asks for the Close button. When the window is still open the button appears. When a map
    /// change already closed the window, the client presses Close for the player: the server, if the script is still
    /// attached (`close;` or `close2;` after a `warp`), waits for `CZ_CLOSE_DIALOG` and refuses walking and item use
    /// until it gets it. After `end;` the script is already gone and the server ignores the packet.
    /// Returns true when the client pressed Close for a window a map change had closed.
    @discardableResult
    func handleCloseDialog(_ packet: PACKET_ZC_CLOSE_DIALOG) -> Bool {
        if dialog != nil {
            npcClosedByMapChange = nil
            dialog?.update(from: packet)
            return false
        }

        guard npcClosedByMapChange == packet.npcId else {
            return false
        }

        npcClosedByMapChange = nil
        sendPacket(PacketFactory.CZ_CLOSE_DIALOG(npcID: packet.npcId))
        return true
    }
}
