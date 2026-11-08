//
//  ChatRoomPacketHandlingTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Feeds the chat room packets of rAthena (PACKETVER 20211103) to a play session without a connection.
@MainActor
struct ChatRoomPacketHandlingTests {
    private static let accountID: UInt32 = 2_000_001
    private static let ownerID: UInt32 = 2_000_002

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

    private func sign(chat: UInt32 = 900, owner: UInt32 = Self.ownerID, limit: UInt16 = 5, users: UInt16 = 2, type: UInt8 = 1, title: String = "Poring's room") -> PACKET_ZC_ROOM_NEWENTRY {
        var packet = PACKET_ZC_ROOM_NEWENTRY()
        packet.owner = Int32(bitPattern: owner)
        packet.id = Int32(bitPattern: chat)
        packet.limit = limit
        packet.users = users
        packet.type = type
        packet.title = title
        return packet
    }

    private func entered(chat: UInt32 = 900, members: [(UInt32, String)] = [(0, "Poring"), (1, "Leon")]) -> PACKET_ZC_ENTER_ROOM {
        var packet = PACKET_ZC_ENTER_ROOM()
        packet.chatId = chat
        packet.members = members.map { member in
            var entry = PACKET_ZC_ENTER_ROOM_sub()
            entry.flag = member.0
            entry.name = member.1
            return entry
        }
        return packet
    }

    private func memberExit(_ name: String, kicked: Bool = false, count: UInt16 = 1) -> PACKET_ZC_MEMBER_EXIT {
        var packet = PACKET_ZC_MEMBER_EXIT()
        packet.name = name
        packet.count = count
        packet.kicked = kicked ? 1 : 0
        return packet
    }

    private func memberEntry(_ name: String) -> PACKET_ZC_MEMBER_NEWENTRY {
        var packet = PACKET_ZC_MEMBER_NEWENTRY()
        packet.name = name
        return packet
    }

    private func role(_ name: String, _ flag: Int32) -> PACKET_ZC_ROLE_CHANGE {
        var packet = PACKET_ZC_ROLE_CHANGE()
        packet.name = name
        packet.flag = flag
        return packet
    }

    private func ack(_ flag: UInt8) -> PACKET_ZC_ACK_CREATE_CHATROOM {
        var packet = PACKET_ZC_ACK_CREATE_CHATROOM()
        packet.flag = flag
        return packet
    }

    private func lastMessage(_ session: PlaySession) -> String? {
        session.messageCenter.messages.last?.content
    }

    /// The player owns "Meetup" after the server's acknowledgement.
    private func createRoom(_ session: PlaySession, title: String = "Meetup", isPublic: Bool = true, password: String = "") {
        session.createChatRoom(ChatRoomSettings(title: title, limit: 6, isPublic: isPublic, password: password))
        _ = session.handleChatRoomPacket(ack(0))
    }

    private func joinRoom(_ session: PlaySession) {
        _ = session.handleChatRoomPacket(sign())
        session.requestJoinChatRoom(ownerID: Self.ownerID)
        _ = session.handleChatRoomPacket(entered())
    }

    private func chatPacket(_ text: String) -> PACKET_ZC_NOTIFY_CHAT {
        var packet = PACKET_ZC_NOTIFY_CHAT()
        packet.Message = text
        return packet
    }

    private func playerChatPacket(_ text: String) -> PACKET_ZC_NOTIFY_PLAYERCHAT {
        var packet = PACKET_ZC_NOTIFY_PLAYERCHAT()
        packet.Message = text
        return packet
    }

    // MARK: - Signs

    @Test func aRoomSignIsKeptAndCanBeClicked() {
        let session = makeSession()

        let handled = session.handleChatRoomPacket(sign())

        #expect(handled)
        #expect(session.chatRoom.signs[900]?.title == "Poring's room")
        #expect(session.hasChatRoomSign(ownerID: Self.ownerID))
        #expect(!session.hasChatRoomSign(ownerID: 12))
    }

    @Test func destroyingTheRoomRemovesTheSign() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign())

        var destroy = PACKET_ZC_DESTROY_ROOM()
        destroy.chatId = 900
        let handled = session.handleChatRoomPacket(destroy)

        #expect(handled)
        #expect(session.chatRoom.signs.isEmpty)
        #expect(!session.hasChatRoomSign(ownerID: Self.ownerID))
    }

    @Test func aPKZoneSignCannotBeClicked() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign(type: 3))

        #expect(!session.hasChatRoomSign(ownerID: Self.ownerID))
    }

    @Test func otherPacketsAreNotChatRoomPackets() {
        let session = makeSession()

        #expect(!session.handleChatRoomPacket(PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO()))
    }

    // MARK: - Creating

    @Test func creatingARoomAcknowledgedByTheServerOpensItWithTheCreatorAsOwner() {
        let session = makeSession()

        createRoom(session)

        let room = session.chatRoom.current
        #expect(room?.title == "Meetup")
        #expect(room?.limit == 6)
        #expect(room?.isOwner == true)
        #expect(room?.members.map(\.name) == ["Leon"])
        #expect(session.chatRoom.isWindowVisible)
        #expect(session.chatRoom.pendingCreate == nil)
        #expect(session.chatRoom.createDraft == nil)
    }

    @Test func aPrivateRoomRemembersItsPassword() {
        let session = makeSession()

        createRoom(session, title: "Secret", isPublic: false, password: "pw")

        #expect(session.chatRoom.current?.access == .privateRoom)
        #expect(session.chatRoom.current?.password == "pw")
    }

    @Test func aRefusedCreationLeavesNoRoomAndExplains() {
        let session = makeSession()
        session.createChatRoom(ChatRoomSettings(title: "Meetup"))

        _ = session.handleChatRoomPacket(ack(2))

        #expect(session.chatRoom.current == nil)
        #expect(session.chatRoom.pendingCreate == nil)
        #expect(lastMessage(session) == "A chat room like that already exists.")
    }

    @Test func creatingNeedsATitleAndNothingGoesOutWithout() {
        let session = makeSession()

        session.createChatRoom(ChatRoomSettings(title: ""))

        #expect(session.chatRoom.pendingCreate == nil)
        #expect(lastMessage(session) == "Enter a title for the chat room.")
    }

    @Test func creatingWithoutBasicSkillWarnsButStillAsksTheServer() {
        let session = makeSession()

        session.createChatRoom(ChatRoomSettings(title: "Meetup"))

        #expect(session.messageCenter.messages.contains { $0.content.contains("Basic Skill level 4") })
        #expect(session.chatRoom.pendingCreate?.title == "Meetup")
    }

    @Test func youCannotCreateWhileInARoom() {
        let session = makeSession()
        createRoom(session)

        session.createChatRoom(ChatRoomSettings(title: "Second"))

        #expect(lastMessage(session) == "You are already in a chat room.")
        #expect(session.chatRoom.pendingCreate == nil)
    }

    @Test func theMenuOpensTheCreateWindowOrTheRoomWindow() {
        let session = makeSession()

        session.openChatRoomMenu(title: "Hello")
        #expect(session.chatRoom.createDraft?.title == "Hello")

        session.cancelChatRoomCreation()
        createRoom(session)
        session.closeChatRoomWindow()
        #expect(!session.chatRoom.isWindowVisible)

        session.openChatRoomMenu()
        #expect(session.chatRoom.isWindowVisible)
        #expect(session.chatRoom.createDraft == nil)
    }

    // MARK: - Joining

    @Test func clickingAPublicRoomJoinsAtOnce() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign())

        session.requestJoinChatRoom(ownerID: Self.ownerID)

        #expect(session.chatRoom.pendingJoin?.chatID == 900)
        #expect(session.chatRoom.passwordPrompt == nil)
    }

    @Test func clickingAPrivateRoomAsksForThePassword() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign(type: 0))

        session.requestJoinChatRoom(ownerID: Self.ownerID)

        #expect(session.chatRoom.passwordPrompt?.chatID == 900)
        #expect(session.chatRoom.pendingJoin == nil)

        session.joinChatRoom(session.chatRoom.passwordPrompt!, password: "secret")
        #expect(session.chatRoom.passwordPrompt == nil)
        #expect(session.chatRoom.pendingJoin?.chatID == 900)
    }

    @Test func cancellingThePasswordPromptJoinsNothing() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign(type: 0))
        session.requestJoinChatRoom(ownerID: Self.ownerID)

        session.cancelChatRoomPassword()

        #expect(session.chatRoom.passwordPrompt == nil)
        #expect(session.chatRoom.pendingJoin == nil)
    }

    @Test func theServerLettingThePlayerInOpensTheRoomWithTheSignsTitle() {
        let session = makeSession()

        joinRoom(session)

        let room = session.chatRoom.current
        #expect(room?.title == "Poring's room")
        #expect(room?.members.map(\.name) == ["Poring", "Leon"])
        #expect(room?.isOwner == false)
        #expect(room?.chatID == 900)
        #expect(session.chatRoom.isWindowVisible)
        #expect(session.chatRoom.pendingJoin == nil)
    }

    @Test func aRefusedJoinExplainsWhy() {
        let session = makeSession()
        _ = session.handleChatRoomPacket(sign())
        session.requestJoinChatRoom(ownerID: Self.ownerID)

        var refusal = PACKET_ZC_REFUSE_ENTER_ROOM()
        refusal.result = 1
        _ = session.handleChatRoomPacket(refusal)

        #expect(session.chatRoom.current == nil)
        #expect(session.chatRoom.pendingJoin == nil)
        #expect(lastMessage(session) == "The password is wrong.")
    }

    @Test func youCannotJoinAnotherRoomWhileInOne() {
        let session = makeSession()
        joinRoom(session)
        _ = session.handleChatRoomPacket(sign(chat: 901, owner: 2_000_009, title: "Other"))

        session.requestJoinChatRoom(ownerID: 2_000_009)

        #expect(lastMessage(session) == "Leave your chat room before you enter another.")
        #expect(session.chatRoom.pendingJoin == nil)
    }

    // MARK: - Members

    @Test func membersComingAndGoingChangeTheList() {
        let session = makeSession()
        createRoom(session)

        _ = session.handleChatRoomPacket(memberEntry("Poring"))
        #expect(session.chatRoom.current?.members.map(\.name) == ["Leon", "Poring"])

        _ = session.handleChatRoomPacket(memberExit("Poring"))
        #expect(session.chatRoom.current?.members.map(\.name) == ["Leon"])
    }

    @Test func theMemberExitOfThePlayerClosesTheRoom() {
        let session = makeSession()
        joinRoom(session)

        _ = session.handleChatRoomPacket(memberExit("Leon"))

        #expect(session.chatRoom.current == nil)
        #expect(!session.chatRoom.isWindowVisible)
    }

    @Test func beingExpelledClosesTheRoomAndSaysSo() {
        let session = makeSession()
        joinRoom(session)

        _ = session.handleChatRoomPacket(memberExit("Leon", kicked: true))

        #expect(session.chatRoom.current == nil)
        #expect(lastMessage(session) == "You were expelled from the chat room.")
    }

    @Test func theOwnerLeavingPassesTheRoomOn() {
        let session = makeSession()
        joinRoom(session)

        _ = session.handleChatRoomPacket(memberExit("Poring"))
        _ = session.handleChatRoomPacket(role("Leon", 0))

        #expect(session.chatRoom.current?.isOwner == true)
        #expect(session.chatRoom.current?.members.map(\.name) == ["Leon"])
    }

    @Test func givingTheRoomAwayIsTwoRoleChanges() {
        let session = makeSession()
        createRoom(session)
        _ = session.handleChatRoomPacket(memberEntry("Poring"))

        _ = session.handleChatRoomPacket(role("Poring", 0))
        _ = session.handleChatRoomPacket(role("Leon", 1))

        #expect(session.chatRoom.current?.isOwner == false)
        #expect(session.chatRoom.current?.owner?.name == "Poring")
    }

    // MARK: - Settings

    @Test func theServersChangeUpdatesTheRoomAndKeepsThePassword() {
        let session = makeSession()
        createRoom(session, title: "Secret", isPublic: false, password: "pw")

        session.openChatRoomSettings()
        #expect(session.chatRoom.settingsDraft?.password == "pw")
        #expect(session.chatRoom.settingsDraft?.isPublic == false)

        session.changeChatRoom(ChatRoomSettings(title: "Renamed", limit: 4, isPublic: false, password: "new"))
        #expect(session.chatRoom.settingsDraft == nil)
        #expect(session.chatRoom.pendingChange?.password == "new")

        var change = PACKET_ZC_CHANGE_CHATROOM()
        change.ownerId = Self.accountID
        change.chatId = 5
        change.limit = 4
        change.users = 1
        change.flag = 0
        change.title = "Renamed"
        _ = session.handleChatRoomPacket(change)

        let room = session.chatRoom.current
        #expect(room?.title == "Renamed")
        #expect(room?.limit == 4)
        #expect(room?.password == "new")
        #expect(room?.chatID == 5)
        #expect(session.chatRoom.pendingChange == nil)
    }

    @Test func onlyTheOwnerOpensTheSettingsOrExpels() {
        let session = makeSession()
        joinRoom(session)

        session.openChatRoomSettings()
        #expect(session.chatRoom.settingsDraft == nil)

        // Nothing to check on the wire without a connection: the call must simply do nothing.
        session.expelFromChatRoom(name: "Poring")
        session.giveChatRoom(to: "Poring")
        #expect(session.chatRoom.current?.members.count == 2)
    }

    @Test func aChangeWithoutATitleIsNotSent() {
        let session = makeSession()
        createRoom(session)

        session.changeChatRoom(ChatRoomSettings(title: ""))

        #expect(session.chatRoom.pendingChange == nil)
        #expect(lastMessage(session) == "Enter a title for the chat room.")
    }

    // MARK: - Chat

    @Test func whatAMemberSaysLandsInTheRoomAndStaysInTheChatBox() {
        let session = makeSession()
        joinRoom(session)

        // The packet handler reads the line and says "not mine", so the chat box shows it like any other chat.
        let handled = session.handleChatRoomPacket(chatPacket("Poring : hello room"))

        #expect(!handled)
        let line = session.chatRoom.current?.lines.last
        #expect(line?.kind == .said(sender: "Poring"))
        #expect(line?.text == "hello room")
    }

    @Test func theEchoOfOwnChatLandsInTheRoom() {
        let session = makeSession()
        joinRoom(session)

        let handled = session.handleChatRoomPacket(playerChatPacket("Leon : hi there"))

        #expect(!handled)
        #expect(session.chatRoom.current?.lines.last?.kind == .said(sender: "Leon"))
    }

    @Test func serverNoticesAndStrangersAreNotRoomLines() {
        let session = makeSession()
        joinRoom(session)
        let lines = session.chatRoom.current?.lines.count

        // An `@` command answer comes as the same packet as the echo, without a speaker.
        _ = session.handleChatRoomPacket(playerChatPacket("Base Level changed."))
        // A speaker who is not a member.
        _ = session.handleChatRoomPacket(chatPacket("Stranger : psst"))
        // The echo with another speaker's name.
        _ = session.handleChatRoomPacket(playerChatPacket("Poring : not mine"))

        #expect(session.chatRoom.current?.lines.count == lines)
    }

    @Test func chatOutsideARoomIsNotRecorded() {
        let session = makeSession()

        let handled = session.handleChatRoomPacket(chatPacket("Poring : hello"))

        #expect(!handled)
        #expect(session.chatRoom.current == nil)
    }

    // MARK: - Leaving

    @Test func leavingClosesTheRoomAtOnce() {
        let session = makeSession()
        joinRoom(session)

        session.leaveChatRoom()

        #expect(session.chatRoom.current == nil)
        #expect(!session.chatRoom.isWindowVisible)
        #expect(lastMessage(session) == "You left the chat room.")

        // The leaver gets his own ZC_MEMBER_EXIT too, which finds no room.
        _ = session.handleChatRoomPacket(memberExit("Leon"))
        #expect(session.chatRoom.current == nil)
    }

    @Test func theLastMemberLeavingAndTheRoomClosing() {
        let session = makeSession()
        createRoom(session)

        session.leaveChatRoom()

        #expect(session.chatRoom.current == nil)
    }

    @Test func aNameThatIsNotThePlayerResolvesOnTheMapOnlyForThePlayer() {
        let session = makeSession()

        #expect(session.mapPlayerID(named: "Leon") == Self.accountID)
        #expect(session.mapPlayerID(named: "Poring") == nil)
    }
}
