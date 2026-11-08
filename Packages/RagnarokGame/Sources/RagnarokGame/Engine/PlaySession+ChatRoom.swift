//
//  PlaySession+ChatRoom.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets

extension PlaySession {
    /// `NV_BASIC` level that rAthena wants to open a chat room (`basic_skill_check`, `clif_parse_CreateChatRoom`).
    static let chatRoomBasicSkillLevel = 4

    /// Handles chat room packets. Returns false when the packet is not one, and for the chat lines of the room,
    /// which this only reads: the chat box shows them like any other chat.
    func handleChatRoomPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_ROOM_NEWENTRY:
            chatRoom.updateSign(ChatRoomSign(from: packet))
        case let packet as PACKET_ZC_DESTROY_ROOM:
            chatRoom.removeSign(chatID: packet.chatId)
        case let packet as PACKET_ZC_CHANGE_CHATROOM:
            handleChatRoomChange(packet)
        case let packet as PACKET_ZC_ACK_CREATE_CHATROOM:
            handleChatRoomCreated(packet)
        case let packet as PACKET_ZC_REFUSE_ENTER_ROOM:
            chatRoom.pendingJoin = nil
            addChatRoomMessage(ChatRoomRefusal.message(forResult: packet.result), type: .error)
        case let packet as PACKET_ZC_ENTER_ROOM:
            handleChatRoomEntered(packet)
        case let packet as PACKET_ZC_MEMBER_NEWENTRY:
            chatRoom.current?.memberJoined(name: packet.name)
        case let packet as PACKET_ZC_MEMBER_EXIT:
            handleChatRoomMemberExit(packet)
        case let packet as PACKET_ZC_ROLE_CHANGE:
            chatRoom.current?.roleChanged(name: packet.name, role: packet.flag)

        // The lines of the room come in as plain chat (`clif_parse_GlobalMessage` sends them to the room alone while the
        // sender is in one). The room window keeps its own copy.
        case let packet as PACKET_ZC_NOTIFY_CHAT:
            recordChatRoomLine(packet.Message, isOwn: false)
            return false
        case let packet as PACKET_ZC_NOTIFY_PLAYERCHAT:
            recordChatRoomLine(packet.Message, isOwn: true)
            return false
        default:
            return false
        }
        return true
    }

    // MARK: - Opening

    /// The menu button and `/chat`: the room window of the room the player is in, or else the create window.
    func openChatRoomMenu(title: String = "") {
        if chatRoom.current != nil {
            chatRoom.isWindowVisible = true
        } else {
            chatRoom.createDraft = ChatRoomSettings(title: title)
        }
    }

    func closeChatRoomWindow() {
        chatRoom.isWindowVisible = false
    }

    // MARK: - Creating

    /// Opens a room around the player. The server answers `ZC_ACK_CREATE_CHATROOM`.
    func createChatRoom(_ settings: ChatRoomSettings) {
        guard chatRoom.current == nil else {
            addChatRoomMessage("You are already in a chat room.", type: .error)
            return
        }
        if let problem = settings.problem {
            addChatRoomMessage(problem.message, type: .error)
            return
        }

        // rAthena refuses with a "skill level too low" when `basic_skill_check` is on, and the default is on.
        // The request goes out anyway: the server decides.
        if (skillList.skills[Trade.basicSkillID]?.level ?? 0) < Self.chatRoomBasicSkillLevel {
            addChatRoomMessage("Chat rooms need Basic Skill level \(Self.chatRoomBasicSkillLevel) unless the server waives it.", type: .error)
        }

        chatRoom.createDraft = nil
        chatRoom.pendingCreate = settings
        sendPacket(PacketFactory.CZ_CREATE_CHATROOM(
            title: settings.title,
            limit: settings.limit,
            isPublic: settings.isPublic,
            password: settings.password
        ))
    }

    func cancelChatRoomCreation() {
        chatRoom.createDraft = nil
    }

    // MARK: - Joining

    /// Whether the player on the map with this account id (or the NPC) has a room that a click can enter.
    func hasChatRoomSign(ownerID: UInt32) -> Bool {
        chatRoom.sign(ofOwner: ownerID)?.canBeJoined == true
    }

    /// A click on the owner of a room: public rooms are entered, private ones ask for the password first.
    func requestJoinChatRoom(ownerID: UInt32) {
        guard let sign = chatRoom.sign(ofOwner: ownerID), sign.canBeJoined else {
            return
        }
        guard chatRoom.current == nil else {
            addChatRoomMessage("Leave your chat room before you enter another.", type: .error)
            return
        }

        if sign.needsPassword {
            chatRoom.passwordPrompt = sign
        } else {
            joinChatRoom(sign, password: "")
        }
    }

    func joinChatRoom(_ sign: ChatRoomSign, password: String) {
        guard chatRoom.current == nil else {
            return
        }
        chatRoom.passwordPrompt = nil
        chatRoom.pendingJoin = sign
        sendPacket(PacketFactory.CZ_REQ_ENTER_ROOM(chatID: sign.chatID, password: password))
    }

    func cancelChatRoomPassword() {
        chatRoom.passwordPrompt = nil
    }

    // MARK: - In the room

    /// Leaves the room. The window closes at once, the server confirms with `ZC_MEMBER_EXIT` for the leaver too.
    func leaveChatRoom() {
        guard chatRoom.current != nil else {
            return
        }
        chatRoom.current = nil
        chatRoom.isWindowVisible = false
        chatRoom.settingsDraft = nil
        sendPacket(PacketFactory.CZ_EXIT_ROOM())
        addChatRoomMessage("You left the chat room.", type: .info)
    }

    /// Says a line in the room. It is the ordinary chat request, because rAthena sends the chat of a player in a room to
    /// the room alone.
    func sayInChatRoom(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard chatRoom.current != nil, !text.isEmpty else {
            return
        }
        sendMessage(text)
    }

    // MARK: - Owner

    func openChatRoomSettings() {
        guard let room = chatRoom.current, room.isOwner else {
            return
        }
        chatRoom.settingsDraft = ChatRoomSettings(
            title: room.title,
            limit: room.limit,
            isPublic: room.access != .privateRoom,
            password: room.password
        )
    }

    func cancelChatRoomSettings() {
        chatRoom.settingsDraft = nil
    }

    /// Sends the new settings. The room window changes when the server confirms with `ZC_CHANGE_CHATROOM`.
    func changeChatRoom(_ settings: ChatRoomSettings) {
        guard let room = chatRoom.current, room.isOwner else {
            return
        }
        if let problem = settings.problem {
            addChatRoomMessage(problem.message, type: .error)
            return
        }

        // rAthena does not check the limit against the members: a room with fewer places than members keeps them
        // and lets nobody else in.
        chatRoom.settingsDraft = nil
        chatRoom.pendingChange = settings
        sendPacket(PacketFactory.CZ_CHANGE_CHATROOM(
            title: settings.title,
            limit: settings.limit,
            isPublic: settings.isPublic,
            password: settings.password
        ))
    }

    func expelFromChatRoom(name: String) {
        guard let room = chatRoom.current, room.isOwner, name != room.selfName, room.contains(memberNamed: name) else {
            return
        }
        sendPacket(PacketFactory.CZ_REQ_EXPEL_MEMBER(name: name))
    }

    /// Gives the room to another member. Both players get `ZC_ROLE_CHANGE`.
    func giveChatRoom(to name: String) {
        guard let room = chatRoom.current, room.isOwner, name != room.selfName, room.contains(memberNamed: name) else {
            return
        }
        sendPacket(PacketFactory.CZ_REQ_ROLE_CHANGE(newOwnerName: name))
    }

    // MARK: - Signs

    /// The account id of the player on the map with this name, for a sign over a room that changed its owner.
    func mapPlayerID(named name: String) -> UInt32? {
        if name == character.name {
            return account.accountID
        }
        return mapScene?.objects.values.first(where: { $0.type == .pc && $0.name == name })?.objectID
    }

    // MARK: - Packets

    /// The answer to `CZ_CREATE_CHATROOM`. `e_create_chatroom` in clif.hpp.
    private func handleChatRoomCreated(_ packet: PACKET_ZC_ACK_CREATE_CHATROOM) {
        let settings = chatRoom.pendingCreate
        chatRoom.pendingCreate = nil

        guard packet.flag == 0 else {
            addChatRoomMessage(ChatRoomRefusal.creationMessage(forFlag: packet.flag), type: .error)
            return
        }

        // rAthena does not send the creator the sign or the member list, only this. The room is the one asked for.
        chatRoom.current = ChatRoom(
            created: settings ?? ChatRoomSettings(title: "Chat room"),
            ownerID: account.accountID,
            selfName: character.name
        )
        chatRoom.isWindowVisible = true
    }

    private func handleChatRoomEntered(_ packet: PACKET_ZC_ENTER_ROOM) {
        let sign = chatRoom.pendingJoin.flatMap { $0.chatID == packet.chatId ? $0 : nil } ?? chatRoom.signs[packet.chatId]
        chatRoom.pendingJoin = nil
        chatRoom.passwordPrompt = nil
        chatRoom.createDraft = nil

        chatRoom.current = ChatRoom(entered: packet, sign: sign, selfName: character.name)
        chatRoom.isWindowVisible = true
    }

    private func handleChatRoomChange(_ packet: PACKET_ZC_CHANGE_CHATROOM) {
        guard chatRoom.current != nil else {
            return
        }

        chatRoom.current?.apply(change: packet)

        // The server keeps the password the owner sent, and does not repeat it.
        if let pending = chatRoom.pendingChange, chatRoom.current?.isOwner == true {
            chatRoom.current?.password = pending.isPublic ? "" : pending.password
        }
        chatRoom.pendingChange = nil
    }

    private func handleChatRoomMemberExit(_ packet: PACKET_ZC_MEMBER_EXIT) {
        guard let departure = chatRoom.current?.memberLeft(name: packet.name, wasExpelled: packet.kicked != 0) else {
            return
        }

        switch departure {
        case .selfLeft:
            chatRoom.current = nil
            chatRoom.isWindowVisible = false
            chatRoom.settingsDraft = nil
        case .selfExpelled:
            chatRoom.current = nil
            chatRoom.isWindowVisible = false
            chatRoom.settingsDraft = nil
            addChatRoomMessage("You were expelled from the chat room.", type: .error)
        case .memberLeft, .memberExpelled, .unknown:
            break
        }
    }

    /// Keeps what a member said in the room window. A line the server shows in the chat box without a speaker, like an
    /// `@` command answer, is not one.
    private func recordChatRoomLine(_ content: String, isOwn: Bool) {
        guard let room = chatRoom.current,
              let line = ChatRoom.spokenLine(content),
              room.contains(memberNamed: line.sender) else {
            return
        }
        if isOwn && line.sender != room.selfName {
            return
        }
        chatRoom.current?.appendSaid(sender: line.sender, text: line.text)
    }

    func addChatRoomMessage(_ content: String, type: MessageCenter.MessageType) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
