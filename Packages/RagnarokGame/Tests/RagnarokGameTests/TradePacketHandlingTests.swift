//
//  TradePacketHandlingTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokConstants
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Feeds the trade packets of rAthena (PACKETVER 20211103) to a play session without a connection.
@MainActor
struct TradePacketHandlingTests {
    private static let accountID: UInt32 = 2_000_001
    private static let partnerID: UInt32 = 2_000_002

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
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

    private func give(_ session: PlaySession, index: Int, itemID: Int, amount: Int) {
        var item = InventoryItem()
        item.index = index
        item.itemID = itemID
        item.type = .etc
        item.amount = amount
        session.inventory.append(item: item)
    }

    /// Opens a trade with Poring through the packets the server sends.
    private func openTrade(_ session: PlaySession) {
        var request = PACKET_ZC_REQ_EXCHANGE_ITEM()
        request.requesterName = "Poring"
        request.targetId = Self.partnerID
        request.targetLv = 50
        _ = session.handleTradePacket(request)
        session.answerTradeRequest(accept: true)

        var response = PACKET_ZC_ACK_EXCHANGE_ITEM()
        response.result = 3
        response.targetId = Self.partnerID
        response.targetLv = 50
        _ = session.handleTradePacket(response)
    }

    private func itemAnswer(index: UInt16, result: UInt8) -> PACKET_ZC_ACK_ADD_EXCHANGE_ITEM {
        var packet = PACKET_ZC_ACK_ADD_EXCHANGE_ITEM()
        packet.index = index
        packet.result = result
        return packet
    }

    private func lastMessage(_ session: PlaySession) -> String? {
        session.messageCenter.messages.last?.content
    }

    // MARK: - Requests

    @Test func incomingRequestWaitsForTheAnswer() {
        let session = makeSession()
        var request = PACKET_ZC_REQ_EXCHANGE_ITEM()
        request.requesterName = "Poring"
        request.targetId = Self.partnerID
        request.targetLv = 77

        let handled = session.handleTradePacket(request)

        #expect(handled)
        #expect(session.trade.incomingRequest == TradeRequest(accountID: Self.partnerID, name: "Poring", baseLevel: 77))
        #expect(session.trade.current == nil)
    }

    @Test func decliningClearsTheRequest() {
        let session = makeSession()
        var request = PACKET_ZC_REQ_EXCHANGE_ITEM()
        request.requesterName = "Poring"
        request.targetId = Self.partnerID
        _ = session.handleTradePacket(request)

        session.answerTradeRequest(accept: false)

        #expect(session.trade.incomingRequest == nil)
        #expect(session.trade.acceptedRequest == nil)

        // The server tells both players. The one who declined hears nothing.
        let before = session.messageCenter.messages.count
        var response = PACKET_ZC_ACK_EXCHANGE_ITEM()
        response.result = 4
        _ = session.handleTradePacket(response)
        #expect(session.messageCenter.messages.count == before)
    }

    @Test func acceptedRequestOpensTheTradeWithTheRequestersName() {
        let session = makeSession()

        openTrade(session)

        let trade = session.trade.current
        #expect(trade?.partner == Trade.Partner(accountID: Self.partnerID, name: "Poring", baseLevel: 50))
        #expect(trade?.stage == .negotiating)
        #expect(session.trade.incomingRequest == nil)
        #expect(session.trade.acceptedRequest == nil)
    }

    @Test func requesterOpensTheTradeWhenTheTargetAccepts() {
        let session = makeSession()
        session.requestTrade(accountID: Self.partnerID, name: "Poring")
        #expect(session.trade.outgoingRequest?.accountID == Self.partnerID)

        var response = PACKET_ZC_ACK_EXCHANGE_ITEM()
        response.result = 3
        response.targetId = Self.partnerID
        response.targetLv = 12
        _ = session.handleTradePacket(response)

        #expect(session.trade.outgoingRequest == nil)
        #expect(session.trade.current?.partner == Trade.Partner(accountID: Self.partnerID, name: "Poring", baseLevel: 12))
    }

    @Test func requestToYourselfIsNotSent() {
        let session = makeSession()

        session.requestTrade(accountID: Self.accountID, name: "Leon")

        #expect(session.trade.outgoingRequest == nil)
    }

    @Test func refusedRequestsExplainThemselves() {
        let expected = [
            (UInt8(0), "Poring is too far away to trade."),
            (UInt8(1), "Poring cannot be found."),
            (UInt8(4), "Poring declined the trade."),
            (UInt8(5), "Poring is busy."),
        ]

        for (result, message) in expected {
            let session = makeSession()
            session.requestTrade(accountID: Self.partnerID, name: "Poring")

            var response = PACKET_ZC_ACK_EXCHANGE_ITEM()
            response.result = result
            _ = session.handleTradePacket(response)

            #expect(lastMessage(session) == message)
            #expect(session.trade.outgoingRequest == nil)
            #expect(session.trade.current == nil)
        }
    }

    @Test func cancelledRequestClosesThePrompt() {
        let session = makeSession()
        var request = PACKET_ZC_REQ_EXCHANGE_ITEM()
        request.requesterName = "Poring"
        request.targetId = Self.partnerID
        _ = session.handleTradePacket(request)

        _ = session.handleTradePacket(PACKET_ZC_CANCEL_EXCHANGE_ITEM())

        #expect(session.trade.incomingRequest == nil)
        #expect(lastMessage(session) == "The trade request was cancelled.")
    }

    // MARK: - Items

    @Test func offeredItemLeavesTheInventoryWhenTheServerAcceptsIt() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 10)
        openTrade(session)

        session.offerTradeItem(index: 5, amount: 4)

        // Nothing moved yet.
        #expect(session.inventory.items[5]?.amount == 10)
        #expect(session.trade.current?.pendingAmount(inventoryIndex: 5) == 4)

        _ = session.handleTradePacket(itemAnswer(index: 5, result: 0))

        #expect(session.inventory.items[5]?.amount == 6)
        #expect(session.trade.current?.mine.offers.map(\.amount) == [4])
        #expect(session.trade.current?.pendingAdds.isEmpty == true)
    }

    @Test func offeringTheWholeStackRemovesItFromTheInventory() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 3)
        openTrade(session)

        session.offerTradeItem(index: 5, amount: 99)
        #expect(session.trade.current?.pendingAmount(inventoryIndex: 5) == 3)
        _ = session.handleTradePacket(itemAnswer(index: 5, result: 0))

        #expect(session.inventory.items[5] == nil)
    }

    @Test func pendingItemsCannotBeOfferedTwice() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 3)
        openTrade(session)

        session.offerTradeItem(index: 5, amount: 3)
        session.offerTradeItem(index: 5, amount: 3)

        #expect(session.trade.current?.pendingAmount(inventoryIndex: 5) == 3)
    }

    @Test func refusedItemStaysInTheInventory() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 10)
        openTrade(session)
        session.offerTradeItem(index: 5, amount: 4)

        _ = session.handleTradePacket(itemAnswer(index: 5, result: 1))

        #expect(session.inventory.items[5]?.amount == 10)
        #expect(session.trade.current?.mine.offers.isEmpty == true)
        #expect(session.trade.current?.pendingAdds.isEmpty == true)
        #expect(lastMessage(session) == "The other player cannot carry that much weight.")
    }

    @Test func equippedItemsCannotBeOffered() {
        let session = makeSession()
        var item = InventoryItem()
        item.index = 6
        item.itemID = 1201
        item.type = .weapon
        item.amount = 1
        item.equippedLocation = .right_hand
        session.inventory.append(item: item)
        openTrade(session)

        session.offerTradeItem(index: 6, amount: 1)

        #expect(session.trade.current?.pendingAdds.isEmpty == true)
    }

    @Test func answerToOKHasNoItem() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 10)
        openTrade(session)

        // trade_tradeok sends index 0 with success before the lock packet.
        _ = session.handleTradePacket(itemAnswer(index: 0, result: 0))

        #expect(session.inventory.items[5]?.amount == 10)
        #expect(session.trade.current?.mine.offers.isEmpty == true)
    }

    // MARK: - Zeny

    @Test func ownZenyIsKeptUnderTheBalance() {
        let session = makeSession()
        session.playerStatus.zeny = 1_000
        openTrade(session)

        session.offerTradeZeny(400)
        #expect(session.trade.current?.mine.zeny == 400)

        session.offerTradeZeny(5_000)
        #expect(session.trade.current?.mine.zeny == 400)
        #expect(lastMessage(session) == "You do not have that much zeny.")
    }

    @Test func partnerPacketsFillTheirSide() {
        let session = makeSession()
        openTrade(session)

        var item = PACKET_ZC_ADD_EXCHANGE_ITEM()
        item.itemId = 1201
        item.itemType = 4
        item.amount = 1
        item.identified = 1
        item.refine = 5
        var slot = EQUIPSLOTINFO()
        slot.card = [4001, 0, 0, 0]
        item.slot = slot
        _ = session.handleTradePacket(item)

        var zeny = PACKET_ZC_ADD_EXCHANGE_ITEM()
        zeny.amount = 25_000
        _ = session.handleTradePacket(zeny)

        let theirs = session.trade.current?.theirs
        #expect(theirs?.offers.count == 1)
        #expect(theirs?.offers.first?.itemID == 1201)
        #expect(theirs?.offers.first?.refine == 5)
        #expect(theirs?.offers.first?.cards == [4001])
        #expect(theirs?.zeny == 25_000)
    }

    // MARK: - Lock, confirm, end

    @Test func lockPacketsMarkTheSides() {
        let session = makeSession()
        openTrade(session)

        var own = PACKET_ZC_CONCLUDE_EXCHANGE_ITEM()
        own.who = 0
        _ = session.handleTradePacket(own)
        #expect(session.trade.current?.mine.isLocked == true)
        #expect(session.trade.current?.theirs.isLocked == false)

        var partner = PACKET_ZC_CONCLUDE_EXCHANGE_ITEM()
        partner.who = 1
        _ = session.handleTradePacket(partner)
        #expect(session.trade.current?.stage == .readyToConfirm)

        session.confirmTrade()
        #expect(session.trade.current?.stage == .waitingForPartnerConfirm)
    }

    @Test func tradeCannotBeConfirmedBeforeBothLocked() {
        let session = makeSession()
        openTrade(session)

        session.confirmTrade()

        #expect(session.trade.current?.mine.hasConfirmed == false)
    }

    @Test func completedTradeClosesTheWindowAndKeepsTheInventory() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 10)
        openTrade(session)
        session.offerTradeItem(index: 5, amount: 4)
        _ = session.handleTradePacket(itemAnswer(index: 5, result: 0))

        _ = session.handleTradePacket(PACKET_ZC_EXEC_EXCHANGE_ITEM())

        #expect(session.trade.current == nil)
        #expect(lastMessage(session) == "The trade is complete.")
        // The server sends no delete for the traded items, the 6 left are the truth.
        #expect(session.inventory.items[5]?.amount == 6)
    }

    @Test func cancelByThePartnerClosesTheWindow() {
        let session = makeSession()
        openTrade(session)

        _ = session.handleTradePacket(PACKET_ZC_CANCEL_EXCHANGE_ITEM())

        #expect(session.trade.current == nil)
        #expect(lastMessage(session) == "The trade was cancelled.")
    }

    @Test func cancelGivesTheItemsBackThroughPickupPackets() {
        let session = makeSession()
        give(session, index: 5, itemID: 501, amount: 4)
        openTrade(session)
        session.offerTradeItem(index: 5, amount: 4)
        _ = session.handleTradePacket(itemAnswer(index: 5, result: 0))
        #expect(session.inventory.items[5] == nil)

        // trade_tradecancel runs clif_additem for every deal item before the cancel packet.
        var pickup = PACKET_ZC_ITEM_PICKUP_ACK()
        pickup.Index = 5
        pickup.count = 4
        pickup.nameid = 501
        pickup.type = 3
        session.inventory.update(from: pickup)
        _ = session.handleTradePacket(PACKET_ZC_CANCEL_EXCHANGE_ITEM())

        #expect(session.trade.current == nil)
        #expect(session.inventory.items[5]?.amount == 4)
    }

    @Test func cancellingYourselfClosesTheWindowAtOnce() {
        let session = makeSession()
        openTrade(session)

        session.cancelTrade()

        #expect(session.trade.current == nil)
        #expect(lastMessage(session) == "You cancelled the trade.")

        // The server's cancel packet that follows has nothing to report.
        let before = session.messageCenter.messages.count
        _ = session.handleTradePacket(PACKET_ZC_CANCEL_EXCHANGE_ITEM())
        #expect(session.messageCenter.messages.count == before)
    }

    @Test func otherPacketsAreNotHandled() {
        let session = makeSession()

        #expect(!session.handleTradePacket(PACKET_ZC_NOTIFY_UNREADMAIL()))
    }
}
