//
//  PlaySession+Appraisal.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets

/// Item appraisal: a Magnifier or the Item Appraisal skill makes the server list the unidentified items
/// (`ZC_ITEMIDENTIFY_LIST`), the player picks one (`CZ_REQ_ITEMIDENTIFY`) and the server answers with the result
/// (`ZC_ACK_ITEMIDENTIFY`).
struct AppraisalState {
    /// Client inventory indices of the items the server offers, while the picker is open.
    var candidateIndices: [Int]?

    var isPickerOpen: Bool {
        candidateIndices != nil
    }
}

extension PlaySession {
    /// Handles appraisal packets. Returns false when the packet is not one of them.
    func handleAppraisalPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_ITEMIDENTIFY_LIST:
            appraisal.candidateIndices = packet.indices.map(Int.init)
        case let packet as PACKET_ZC_ACK_ITEMIDENTIFY:
            handleAppraisalResult(packet)
        default:
            return false
        }
        return true
    }

    /// Sends the pick. The window closes at once, the server answers with the result.
    func appraiseItem(at inventoryIndex: Int) {
        guard let indices = appraisal.candidateIndices, indices.contains(inventoryIndex) else {
            return
        }

        appraisal.candidateIndices = nil
        sendPacket(PacketFactory.CZ_REQ_ITEMIDENTIFY(index: UInt16(truncatingIfNeeded: inventoryIndex)))
    }

    /// Leaves the picker. rAthena stays in the appraisal menu, and refuses other actions while it does, until it
    /// hears an answer, so the cancel goes out as well.
    func cancelAppraisal() {
        guard appraisal.isPickerOpen else {
            return
        }

        appraisal.candidateIndices = nil
        sendPacket(PacketFactory.CZ_REQ_ITEMIDENTIFY(index: PACKET_CZ_REQ_ITEMIDENTIFY.cancelIndex))
    }

    private func handleAppraisalResult(_ packet: PACKET_ZC_ACK_ITEMIDENTIFY) {
        if let item = inventory.update(from: packet) {
            let name = messageCenter.itemInfoTable.localizedItemName(forItemID: item.itemID, isIdentified: true) ?? "item \(item.itemID)"
            addAppraisalMessage("Appraised: \(name).", type: .system)
        } else {
            addAppraisalMessage("The item could not be appraised.", type: .error)
        }
    }

    private func addAppraisalMessage(_ content: String, type: MessageCenter.MessageType) {
        let message = MessageCenter.Message(content: content, type: type, category: .item)
        messageCenter.messages.append(message)
    }
}
