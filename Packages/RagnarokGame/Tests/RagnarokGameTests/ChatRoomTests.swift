//
//  ChatRoomTests.swift
//  RagnarokGameTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// The chat room model against what rAthena sends at PACKETVER 20211103 (chat.cpp, clif.cpp).
struct ChatRoomTests {
    private func newEntry(owner: UInt32, chat: UInt32, limit: UInt16, users: UInt16, type: UInt8, title: String) -> PACKET_ZC_ROOM_NEWENTRY {
        var packet = PACKET_ZC_ROOM_NEWENTRY()
        packet.owner = Int32(bitPattern: owner)
        packet.id = Int32(bitPattern: chat)
        packet.limit = limit
        packet.users = users
        packet.type = type
        packet.title = title
        return packet
    }

    private func enterPacket(chat: UInt32, members: [(role: UInt32, name: String)]) -> PACKET_ZC_ENTER_ROOM {
        var packet = PACKET_ZC_ENTER_ROOM()
        packet.chatId = chat
        packet.members = members.map { member in
            var entry = PACKET_ZC_ENTER_ROOM_sub()
            entry.flag = member.role
            entry.name = member.name
            return entry
        }
        return packet
    }

    private func changePacket(owner: UInt32, chat: UInt32, limit: UInt16, users: UInt16, type: UInt8, title: String) -> PACKET_ZC_CHANGE_CHATROOM {
        var packet = PACKET_ZC_CHANGE_CHATROOM()
        packet.ownerId = owner
        packet.chatId = chat
        packet.limit = limit
        packet.users = users
        packet.flag = type
        packet.title = title
        return packet
    }

    /// A room Leon owns with Poring and Drops in it.
    private func ownRoom() -> ChatRoom {
        var room = ChatRoom(created: ChatRoomSettings(title: "Meetup", limit: 5), ownerID: 2_000_001, selfName: "Leon")
        room.memberJoined(name: "Poring")
        room.memberJoined(name: "Drops")
        return room
    }

    /// A room Poring owns that Leon entered.
    private func joinedRoom() -> ChatRoom {
        let sign = ChatRoomSign(chatID: 77, ownerID: 2_000_002, title: "Poring's room", limit: 5, users: 2, access: .publicRoom)
        let packet = enterPacket(chat: 77, members: [(0, "Poring"), (1, "Drops"), (1, "Leon")])
        return ChatRoom(entered: packet, sign: sign, selfName: "Leon")
    }

    // MARK: - Settings

    @Test func titleIsCutToThirtySixBytesWithoutSplittingACharacter() {
        let settings = ChatRoomSettings(title: String(repeating: "あ", count: 20))

        #expect(settings.title == String(repeating: "あ", count: 12))
        #expect(settings.title.utf8.count == 36)
    }

    @Test func limitStaysBetweenTwoAndTwenty() {
        var settings = ChatRoomSettings(limit: 1)
        #expect(settings.limit == 2)

        settings.setLimit(99)
        #expect(settings.limit == 20)

        settings.setLimit(8)
        #expect(settings.limit == 8)
    }

    @Test func passwordIsCutToSevenBytes() {
        let settings = ChatRoomSettings(title: "x", isPublic: false, password: "123456789")

        #expect(settings.password == "1234567")
    }

    @Test func settingsNeedATitleAndAPrivateRoomNeedsAPassword() {
        #expect(ChatRoomSettings(title: "").problem == .emptyTitle)
        #expect(ChatRoomSettings(title: "   ").problem == .emptyTitle)
        #expect(ChatRoomSettings(title: "Open").problem == nil)
        #expect(ChatRoomSettings(title: "Closed", isPublic: false).problem == .missingPassword)
        #expect(ChatRoomSettings(title: "Closed", isPublic: false, password: "pw").problem == nil)
    }

    // MARK: - Sign

    @Test func signReadsOwnerChatLimitUsersAndAccess() {
        let sign = ChatRoomSign(from: newEntry(owner: 2_000_002, chat: 900, limit: 8, users: 3, type: 0, title: "Secret"))

        #expect(sign.ownerID == 2_000_002)
        #expect(sign.chatID == 900)
        #expect(sign.limit == 8)
        #expect(sign.users == 3)
        #expect(sign.title == "Secret")
        #expect(sign.access == .privateRoom)
        #expect(sign.needsPassword)
        #expect(sign.canBeJoined)
        #expect(!sign.isFull)
    }

    @Test func signTypesMapToAccess() {
        #expect(ChatRoomAccess(type: 0) == .privateRoom)
        #expect(ChatRoomAccess(type: 1) == .publicRoom)
        #expect(ChatRoomAccess(type: 2) == .arena)
        #expect(ChatRoomAccess(type: 3) == .pkZone)
        #expect(ChatRoomSign(chatID: 1, ownerID: 2, title: "PK", limit: 0, users: 0, access: .pkZone).canBeJoined == false)
    }

    @Test func aFullSignIsFull() {
        #expect(ChatRoomSign(chatID: 1, ownerID: 2, title: "t", limit: 3, users: 3, access: .publicRoom).isFull)
    }

    // MARK: - Opening and entering

    @Test func aCreatedRoomHasTheCreatorAsOwnerAndOnlyMember() {
        let room = ChatRoom(created: ChatRoomSettings(title: "Meetup", limit: 10), ownerID: 2_000_001, selfName: "Leon")

        #expect(room.members == [ChatRoomMember(name: "Leon", isOwner: true)])
        #expect(room.isOwner)
        #expect(room.title == "Meetup")
        #expect(room.limit == 10)
        #expect(room.access == .publicRoom)
        #expect(room.chatID == nil)
        #expect(room.ownerID == 2_000_001)
        #expect(room.lines.count == 1)
    }

    @Test func aPrivateRoomKeepsItsPasswordForLaterChanges() {
        let room = ChatRoom(created: ChatRoomSettings(title: "Secret", isPublic: false, password: "pw"), ownerID: 1, selfName: "Leon")

        #expect(room.access == .privateRoom)
        #expect(room.password == "pw")
    }

    @Test func enteringReadsTheMemberListWithTheOwnerFirst() {
        let room = joinedRoom()

        #expect(room.members.map(\.name) == ["Poring", "Drops", "Leon"])
        #expect(room.members.map(\.isOwner) == [true, false, false])
        #expect(!room.isOwner)
        #expect(room.owner?.name == "Poring")
        #expect(room.chatID == 77)
        #expect(room.ownerID == 2_000_002)
        #expect(room.title == "Poring's room")
        #expect(room.limit == 5)
        #expect(room.otherMembers.map(\.name) == ["Poring", "Drops"])
    }

    @Test func enteringWithoutTheSignStillWorks() {
        let room = ChatRoom(entered: enterPacket(chat: 5, members: [(0, "Poring"), (1, "Leon")]), sign: nil, selfName: "Leon")

        #expect(room.title == "")
        #expect(room.members.count == 2)
        #expect(room.owner?.name == "Poring")
    }

    // MARK: - Members

    @Test func aMemberJoiningIsAddedOnceAndAnnounced() {
        var room = ownRoom()
        let lines = room.lines.count

        room.memberJoined(name: "Poring")
        #expect(room.members.count == 3)
        #expect(room.lines.count == lines)

        room.memberJoined(name: "Lunatic")
        #expect(room.members.map(\.name) == ["Leon", "Poring", "Drops", "Lunatic"])
        #expect(room.lines.last?.text == "Lunatic entered the chat room.")
    }

    @Test func aMemberLeavingIsRemoved() {
        var room = ownRoom()

        let departure = room.memberLeft(name: "Poring", wasExpelled: false)

        #expect(departure == .memberLeft(name: "Poring"))
        #expect(room.members.map(\.name) == ["Leon", "Drops"])
        #expect(room.lines.last?.text == "Poring left the chat room.")
    }

    @Test func anExpelledMemberIsAnnouncedAsExpelled() {
        var room = ownRoom()

        let departure = room.memberLeft(name: "Drops", wasExpelled: true)

        #expect(departure == .memberExpelled(name: "Drops"))
        #expect(room.lines.last?.text == "Drops was expelled from the chat room.")
    }

    @Test func thePlayerLeavingOrBeingExpelledIsReportedAndLeavesTheListAlone() {
        var room = joinedRoom()

        #expect(room.memberLeft(name: "Leon", wasExpelled: false) == .selfLeft)
        #expect(room.memberLeft(name: "Leon", wasExpelled: true) == .selfExpelled)
        #expect(room.members.count == 3)
    }

    @Test func aNameThatIsNotInTheRoomChangesNothing() {
        var room = ownRoom()

        #expect(room.memberLeft(name: "Nobody", wasExpelled: false) == .unknown)
        #expect(room.members.count == 3)
    }

    @Test func whenTheOwnerLeavesTheNextMemberOwnsTheRoom() {
        var room = joinedRoom()

        _ = room.memberLeft(name: "Poring", wasExpelled: false)

        // chat_leavechat: usersd[0] becomes the owner, before ZC_ROLE_CHANGE says so.
        #expect(room.members.map(\.name) == ["Drops", "Leon"])
        #expect(room.owner?.name == "Drops")
        #expect(room.ownerID == nil)
    }

    @Test func whenTheOwnerLeavesAndThePlayerIsNextThePlayerOwnsTheRoom() {
        var room = ChatRoom(entered: enterPacket(chat: 3, members: [(0, "Poring"), (1, "Leon")]), sign: nil, selfName: "Leon")

        _ = room.memberLeft(name: "Poring", wasExpelled: false)

        #expect(room.isOwner)
    }

    // MARK: - Roles

    @Test func aRoleChangeOfZeroMakesTheMemberTheOwnerInTheFirstPlace() {
        var room = ownRoom()

        // chat_changechatowner sends the new owner with role 0, then the old owner with role 1.
        room.roleChanged(name: "Drops", role: 0)
        room.roleChanged(name: "Leon", role: 1)

        #expect(room.owner?.name == "Drops")
        #expect(room.members.first?.name == "Drops")
        #expect(room.members.filter(\.isOwner).count == 1)
        #expect(!room.isOwner)
        #expect(room.ownerID == nil)
    }

    @Test func receivingTheRoomMakesThePlayerTheOwner() {
        var room = joinedRoom()

        room.roleChanged(name: "Leon", role: 0)

        #expect(room.isOwner)
        #expect(room.members.first?.name == "Leon")
        #expect(room.lines.last?.text == "You are the owner of the chat room now.")
    }

    @Test func aRoleChangeForAnUnknownNameChangesNothing() {
        var room = ownRoom()
        let before = room

        room.roleChanged(name: "Nobody", role: 0)

        #expect(room == before)
    }

    // MARK: - Changes

    @Test func aChangeUpdatesTitleLimitAccessAndIds() {
        var room = ownRoom()

        room.apply(change: changePacket(owner: 2_000_001, chat: 321, limit: 9, users: 3, type: 0, title: "New title"))

        #expect(room.chatID == 321)
        #expect(room.ownerID == 2_000_001)
        #expect(room.title == "New title")
        #expect(room.limit == 9)
        #expect(room.access == .privateRoom)
    }

    @Test func makingTheRoomPublicForgetsThePassword() {
        var room = ChatRoom(created: ChatRoomSettings(title: "Secret", isPublic: false, password: "pw"), ownerID: 1, selfName: "Leon")

        room.apply(change: changePacket(owner: 1, chat: 2, limit: 5, users: 1, type: 1, title: "Secret"))

        #expect(room.access == .publicRoom)
        #expect(room.password == "")
    }

    // MARK: - Lines

    @Test func linesKeepTheLatestTwoHundred() {
        var room = ownRoom()

        for index in 0..<250 {
            room.appendSaid(sender: "Leon", text: "line \(index)")
        }

        #expect(room.lines.count == ChatRoom.maxLines)
        #expect(room.lines.last?.text == "line 249")
        #expect(Set(room.lines.map(\.id)).count == ChatRoom.maxLines)
    }

    @Test func spokenLinesSplitAtTheFirstSeparator() {
        let line = ChatRoom.spokenLine("Poring : see you : soon")

        #expect(line?.sender == "Poring")
        #expect(line?.text == "see you : soon")
        #expect(ChatRoom.spokenLine("a server notice") == nil)
        #expect(ChatRoom.spokenLine(" : text") == nil)
    }

    // MARK: - Refusals

    @Test func everyRefusalHasAMessage() {
        #expect(ChatRoomRefusal.message(forResult: 0) == "The chat room is full or no longer available.")
        #expect(ChatRoomRefusal.message(forResult: 1) == "The password is wrong.")
        #expect(ChatRoomRefusal.message(forResult: 2) == "You were expelled from that chat room.")
        #expect(ChatRoomRefusal.message(forResult: 4).contains("zeny"))
        #expect(ChatRoomRefusal.message(forResult: 5).contains("too low"))
        #expect(ChatRoomRefusal.message(forResult: 6).contains("too high"))
        #expect(ChatRoomRefusal.message(forResult: 7).contains("job"))
        #expect(ChatRoomRefusal.message(forResult: 99) == "You cannot enter that chat room.")
        #expect(ChatRoomRefusal.creationMessage(forFlag: 1).contains("limit"))
        #expect(ChatRoomRefusal.creationMessage(forFlag: 2).contains("already exists"))
    }

    // MARK: - State

    @Test func aNewSignOfTheSameOwnerReplacesTheOldOne() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Old", limit: 5, users: 1, access: .publicRoom))
        state.updateSign(ChatRoomSign(chatID: 2, ownerID: 10, title: "New", limit: 5, users: 1, access: .publicRoom))

        #expect(state.signs.count == 1)
        #expect(state.sign(ofOwner: 10)?.title == "New")
    }

    @Test func aSignUpdateKeepsTheSameRoom() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Room", limit: 5, users: 1, access: .publicRoom))
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Room", limit: 5, users: 4, access: .publicRoom))

        #expect(state.signs.count == 1)
        #expect(state.signs[1]?.users == 4)
    }

    @Test func destroyingARoomRemovesItsSign() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Room", limit: 5, users: 1, access: .publicRoom))

        state.removeSign(chatID: 1)

        #expect(state.signs.isEmpty)
    }

    @Test func anOwnerLeavingTheViewTakesHisSign() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "A", limit: 5, users: 1, access: .publicRoom))
        state.updateSign(ChatRoomSign(chatID: 2, ownerID: 11, title: "B", limit: 5, users: 1, access: .publicRoom))

        state.removeSigns(ofOwner: 10)

        #expect(state.signs.keys.sorted() == [2])
    }

    @Test func theCreatorSeesHisOwnSignThoughTheServerNeverSendsIt() {
        let state = ChatRoomState()
        state.current = ChatRoom(created: ChatRoomSettings(title: "Mine"), ownerID: 5, selfName: "Leon")

        let signs = state.displayedSigns(selfAccountID: 5) { _ in nil }

        #expect(signs.map(\.ownerID) == [5])
        #expect(signs.map(\.title) == ["Mine"])
    }

    @Test func aMemberSeesTheCurrentTitleOverTheOwnerNotTheStaleSign() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 77, ownerID: 2_000_002, title: "Old title", limit: 5, users: 2, access: .publicRoom))
        var room = joinedRoom()
        room.apply(change: changePacket(owner: 2_000_002, chat: 77, limit: 5, users: 3, type: 1, title: "Renamed"))
        state.current = room

        let signs = state.displayedSigns(selfAccountID: 2_000_001) { _ in nil }

        #expect(signs.count == 1)
        #expect(signs.first?.ownerID == 2_000_002)
        #expect(signs.first?.title == "Renamed")
    }

    @Test func aRoomThatChangedOwnerShowsOverTheNewOwnerFoundByName() {
        let state = ChatRoomState()
        var room = joinedRoom()
        room.roleChanged(name: "Drops", role: 0)
        room.roleChanged(name: "Poring", role: 1)
        state.current = room

        let signs = state.displayedSigns(selfAccountID: 2_000_001) { name in
            name == "Drops" ? 2_000_003 : nil
        }

        #expect(signs.map(\.ownerID) == [2_000_003])
    }

    @Test func aRoomThePlayerNowOwnsShowsOverThePlayer() {
        let state = ChatRoomState()
        var room = joinedRoom()
        room.roleChanged(name: "Leon", role: 0)
        state.current = room

        let signs = state.displayedSigns(selfAccountID: 2_000_001) { _ in nil }

        #expect(signs.map(\.ownerID) == [2_000_001])
    }

    @Test func signsOfOtherRoomsStayWhileThePlayerIsInOne() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Other", limit: 5, users: 1, access: .publicRoom))
        state.current = ChatRoom(created: ChatRoomSettings(title: "Mine"), ownerID: 5, selfName: "Leon")

        let signs = state.displayedSigns(selfAccountID: 5) { _ in nil }

        #expect(signs.map(\.ownerID) == [5, 10])
        #expect(signs.map(\.title) == ["Mine", "Other"])
    }

    @Test func aMapChangeForgetsEverything() {
        let state = ChatRoomState()
        state.updateSign(ChatRoomSign(chatID: 1, ownerID: 10, title: "Room", limit: 5, users: 1, access: .publicRoom))
        state.current = joinedRoom()
        state.isWindowVisible = true
        state.createDraft = ChatRoomSettings()
        state.passwordPrompt = state.signs[1]
        state.pendingJoin = state.signs[1]

        state.resetForMapChange()

        #expect(state.signs.isEmpty)
        #expect(state.current == nil)
        #expect(!state.isWindowVisible)
        #expect(state.createDraft == nil)
        #expect(state.passwordPrompt == nil)
        #expect(state.pendingJoin == nil)
    }

    // MARK: - Slash command

    @Test func slashChatIsACommand() {
        #expect(SlashCommand(message: "/chat") == .chat)
        #expect(SlashCommand(message: "/chat Meet at the fountain") == .chat)
    }
}
