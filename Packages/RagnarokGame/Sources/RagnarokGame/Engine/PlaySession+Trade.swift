//
//  PlaySession+Trade.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokNetwork
import RagnarokPackets

@Observable
final class TradeState {
    /// A request from another player that waits for accept or decline.
    var incomingRequest: TradeRequest?

    /// A request this player sent and the other player has not answered.
    var outgoingRequest: TradeRequest?

    /// The open trade window.
    var current: Trade?

    /// The request this player accepted, kept until the server opens the trade. It names the partner,
    /// because `ZC_ACK_EXCHANGE_ITEM` carries only the account id.
    @ObservationIgnored var acceptedRequest: TradeRequest?
}

extension PlaySession {
    /// Handles player trade packets. Returns false when the packet is not a trade packet.
    func handleTradePacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_REQ_EXCHANGE_ITEM:
            handleTradeRequest(packet)
        case let packet as PACKET_ZC_ACK_EXCHANGE_ITEM:
            handleTradeResponse(packet)
        case let packet as PACKET_ZC_ACK_ADD_EXCHANGE_ITEM:
            handleTradeItemAnswer(packet)
        case let packet as PACKET_ZC_ADD_EXCHANGE_ITEM:
            handlePartnerOffer(packet)
        case let packet as PACKET_ZC_CONCLUDE_EXCHANGE_ITEM:
            // `clif_tradedeal_lock`: who is 0 for this player and 1 for the partner.
            trade.current?.lock(partner: packet.who != 0)
        case _ as PACKET_ZC_CANCEL_EXCHANGE_ITEM:
            handleTradeCancelled()
        case let packet as PACKET_ZC_EXEC_EXCHANGE_ITEM:
            handleTradeCompleted(packet)
        case _ as PACKET_ZC_EXCHANGEITEM_UNDO:
            trade.current?.reset()
        default:
            return false
        }
        return true
    }

    // MARK: - Requests

    /// Asks a player on the map to trade. rAthena wants both players within 2 cells.
    func requestTrade(accountID: UInt32, name: String) {
        guard accountID != account.accountID else {
            return
        }
        guard trade.current == nil else {
            addTradeMessage("You are already trading.", type: .error)
            return
        }
        guard trade.incomingRequest == nil else {
            addTradeMessage("Answer the trade request first.", type: .error)
            return
        }

        // rAthena refuses the request with a bare "skill failed" when `basic_skill_check` is on, and the default is on.
        // The request goes out anyway: the server decides.
        if (skillList.skills[Trade.basicSkillID]?.level ?? 0) < 1 {
            addTradeMessage("Trading needs Basic Skill level 1 unless the server waives it.", type: .error)
        }

        trade.outgoingRequest = TradeRequest(accountID: accountID, name: name, baseLevel: 0)
        sendPacket(PacketFactory.CZ_REQ_EXCHANGE_ITEM(accountID: accountID))
        addTradeMessage("Trade request sent to \(name).")
    }

    /// `/exchange` without a selected player.
    func noteTradeNeedsPlayer() {
        addTradeMessage("Select a player to trade with first.", type: .error)
    }

    func answerTradeRequest(accept: Bool) {
        guard let request = trade.incomingRequest else {
            return
        }

        trade.incomingRequest = nil
        trade.acceptedRequest = accept ? request : nil
        sendPacket(PacketFactory.CZ_ACK_EXCHANGE_ITEM(accept: accept))
    }

    /// Withdraws a request nobody answered yet. The server forgets the pending partner on a cancel.
    func cancelTradeRequest() {
        guard trade.outgoingRequest != nil else {
            return
        }

        trade.outgoingRequest = nil
        sendPacket(PacketFactory.CZ_CANCEL_EXCHANGE_ITEM())
    }

    // MARK: - Deal

    /// Offers `amount` of an inventory item. The server answers with the item or the reason.
    func offerTradeItem(index: Int, amount: Int) {
        guard var current = trade.current, current.canChangeOffer,
              let item = inventory.items[index], !item.isEquipped else {
            return
        }

        let available = item.amount - current.pendingAmount(inventoryIndex: index)
        let amount = min(amount, available, Trade.maxAmountPerAdd)
        guard amount > 0 else {
            return
        }
        guard current.canOffer(inventoryIndex: index) else {
            addTradeMessage("A trade holds at most \(Trade.maxOffers) different items.", type: .error)
            return
        }

        let offer = Trade.Offer(
            id: index,
            itemID: item.itemID,
            amount: amount,
            type: item.type.rawValue,
            cards: item.slots.filter { $0 != 0 }
        )
        current.requestAdd(offer)
        trade.current = current
        sendPacket(PacketFactory.CZ_ADD_EXCHANGE_ITEM(index: index, amount: amount))
    }

    /// Sets the zeny this player offers. A new value replaces the last one.
    func offerTradeZeny(_ zeny: Int) {
        guard var current = trade.current else {
            return
        }

        guard current.setZeny(zeny, available: playerStatus.zeny) else {
            if current.canChangeOffer {
                addTradeMessage("You do not have that much zeny.", type: .error)
            }
            return
        }

        trade.current = current
        sendPacket(PacketFactory.CZ_ADD_EXCHANGE_ITEM(index: 0, amount: zeny))
    }

    /// OK: locks this side of the deal.
    func lockTrade() {
        guard let current = trade.current, current.canLock else {
            return
        }
        sendPacket(PacketFactory.CZ_CONCLUDE_EXCHANGE_ITEM())
    }

    /// Trade: confirms the locked deal. The server finishes it when both sides confirmed.
    func confirmTrade() {
        guard var current = trade.current, current.confirm() else {
            return
        }

        trade.current = current
        sendPacket(PacketFactory.CZ_EXEC_EXCHANGE_ITEM())
    }

    /// Cancel: closes the window. The server gives the items back with item packets.
    func cancelTrade() {
        guard trade.current != nil else {
            return
        }

        trade.current = nil
        sendPacket(PacketFactory.CZ_CANCEL_EXCHANGE_ITEM())
        addTradeMessage("You cancelled the trade.")
    }

    // MARK: - Packet Handling

    private func handleTradeRequest(_ packet: PACKET_ZC_REQ_EXCHANGE_ITEM) {
        trade.incomingRequest = TradeRequest(
            accountID: packet.targetId,
            name: packet.requesterName,
            baseLevel: Int(packet.targetLv)
        )
        addTradeMessage("\(packet.requesterName) wants to trade.")
    }

    private func handleTradeResponse(_ packet: PACKET_ZC_ACK_EXCHANGE_ITEM) {
        let response = TradeResponse(result: packet.result)
        let outgoing = trade.outgoingRequest
        let accepted = trade.acceptedRequest

        trade.outgoingRequest = nil
        trade.acceptedRequest = nil

        if response == .accepted {
            guard trade.current == nil else {
                return
            }

            let name = [accepted, outgoing]
                .compactMap { $0 }
                .first { $0.accountID == packet.targetId && !$0.name.isEmpty }?.name
                ?? mapScene?.objects[packet.targetId]?.name
                ?? "Player"
            trade.incomingRequest = nil
            trade.current = Trade(partner: Trade.Partner(
                accountID: packet.targetId,
                name: name,
                baseLevel: Int(packet.targetLv)
            ))
            return
        }

        // The server answers a declined request to both players. Only the one who asked has something to learn.
        if response == .declined, outgoing == nil {
            return
        }

        let name = outgoing?.name ?? accepted?.name
        if let message = response.failureMessage(name: name) {
            addTradeMessage(message, type: .error)
        }
    }

    private func handleTradeItemAnswer(_ packet: PACKET_ZC_ACK_ADD_EXCHANGE_ITEM) {
        // The answer to OK carries index 0 and has nothing to add.
        let index = Int(packet.index)
        guard index != 0, var current = trade.current else {
            return
        }

        if let failure = TradeItemFailure(result: packet.result) {
            current.rejectAdd(inventoryIndex: index)
            trade.current = current
            addTradeMessage(failure.message, type: .error)
            return
        }

        // The server keeps the items in the inventory until the trade completes, the client takes them out of
        // the list right away: a cancel gives them back with item packets, and a completed trade sends no
        // delete for them (`pc_delitem` runs with the packet flag off in `trade_tradecommit`).
        if let offer = current.confirmAdd(inventoryIndex: index) {
            takeFromInventory(index: index, amount: offer.amount)
        }
        trade.current = current
    }

    private func handlePartnerOffer(_ packet: PACKET_ZC_ADD_EXCHANGE_ITEM) {
        guard var current = trade.current else {
            return
        }

        if packet.itemId == 0 {
            current.partnerSetZeny(Int(packet.amount))
        } else {
            current.partnerAdded(Trade.Offer(
                id: 0,
                itemID: Int(packet.itemId),
                amount: Int(packet.amount),
                type: Int(packet.itemType),
                isIdentified: packet.identified != 0,
                refine: Int(packet.refine),
                cards: packet.slot.card.filter { $0 != 0 }.map(Int.init)
            ))
        }
        trade.current = current
    }

    private func handleTradeCancelled() {
        let wasTrading = trade.current != nil
        let hadRequest = trade.incomingRequest != nil

        trade.current = nil
        trade.incomingRequest = nil
        trade.outgoingRequest = nil
        trade.acceptedRequest = nil

        if wasTrading {
            addTradeMessage("The trade was cancelled.", type: .error)
        } else if hadRequest {
            addTradeMessage("The trade request was cancelled.", type: .error)
        }
    }

    private func handleTradeCompleted(_ packet: PACKET_ZC_EXEC_EXCHANGE_ITEM) {
        trade.current = nil
        trade.incomingRequest = nil
        trade.outgoingRequest = nil
        trade.acceptedRequest = nil

        if packet.result == 0 {
            addTradeMessage("The trade is complete.")
        } else {
            addTradeMessage("The trade failed.", type: .error)
        }
    }

    private func takeFromInventory(index: Int, amount: Int) {
        guard var item = inventory.items[index] else {
            return
        }

        item.amount -= amount
        if item.amount > 0 {
            inventory.items[index] = item
        } else {
            inventory.items.removeValue(forKey: index)
        }
    }

    private func addTradeMessage(_ content: String, type: MessageCenter.MessageType = .info) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
