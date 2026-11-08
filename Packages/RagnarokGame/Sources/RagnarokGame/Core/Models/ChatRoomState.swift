//
//  ChatRoomState.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokPackets

// Chat rooms as rAthena sends them at PACKETVER 20211103 (clif.cpp: clif_dispchat, clif_changechatstatus,
// clif_clearchat, clif_joinchatok, clif_addchat, clif_chat_role, clif_chat_leave; chat.cpp for the rules).

/// Who may enter a room. The `type` byte of `ZC_ROOM_NEWENTRY` (`clif_chat_status`).
enum ChatRoomAccess: Equatable, Sendable {
    /// Password protected (0).
    case privateRoom

    /// Open to anyone (1).
    case publicRoom

    /// An NPC's waiting room for a fight (2).
    case arena

    /// An NPC's room that cannot be entered (3).
    case pkZone

    init(type: UInt8) {
        switch type {
        case 0: self = .privateRoom
        case 2: self = .arena
        case 3: self = .pkZone
        default: self = .publicRoom
        }
    }
}

/// The sign of a room over its owner's head (`ZC_ROOM_NEWENTRY`). rAthena shows it to the players around the owner,
/// and not to the members of the room.
struct ChatRoomSign: Equatable, Identifiable, Sendable {
    /// The id to join with (`CZ_REQ_ENTER_ROOM`). It is not the owner's account id.
    var chatID: UInt32

    /// The account id of the owner, which is the object id of a player on the map. An NPC room has the NPC's id.
    var ownerID: UInt32

    var title: String
    var limit: Int
    var users: Int
    var access: ChatRoomAccess

    var id: UInt32 {
        chatID
    }

    var needsPassword: Bool {
        access == .privateRoom
    }

    /// An NPC "PK zone" room is only a sign.
    var canBeJoined: Bool {
        access != .pkZone
    }

    var isFull: Bool {
        users >= limit
    }

    init(chatID: UInt32, ownerID: UInt32, title: String, limit: Int, users: Int, access: ChatRoomAccess) {
        self.chatID = chatID
        self.ownerID = ownerID
        self.title = title
        self.limit = limit
        self.users = users
        self.access = access
    }

    init(from packet: PACKET_ZC_ROOM_NEWENTRY) {
        self.init(
            chatID: UInt32(bitPattern: packet.id),
            ownerID: UInt32(bitPattern: packet.owner),
            title: packet.title,
            limit: Int(packet.limit),
            users: Int(packet.users),
            access: ChatRoomAccess(type: packet.type)
        )
    }
}

/// What the create window and the owner's settings window edit. `CZ_CREATE_CHATROOM` and `CZ_CHANGE_CHATROOM` carry it.
struct ChatRoomSettings: Equatable, Sendable {
    /// `CHATROOM_TITLE_SIZE` is 37 in rAthena: 36 bytes and the terminator.
    static let maxTitleBytes = 36

    /// `MAX_CHAT_USERS`.
    static let maxLimit = 20

    /// A room of one has no room for anybody else.
    static let minLimit = 2

    /// The password is an 8 byte field, but rAthena compares 9 bytes (`strncmp(pass, cd->pass, sizeof(cd->pass))` in
    /// `chat_joinchat`), so a password that fills the field is compared with the first byte of whatever follows the
    /// packet and rarely matches. 7 bytes are the longest that always work.
    static let maxPasswordBytes = 7

    /// The size of the password field of `CZ_REQ_ENTER_ROOM`. A room made by another client may use all of it.
    static let packetPasswordBytes = 8

    enum Problem: Equatable, Sendable {
        case emptyTitle
        case missingPassword

        var message: String {
            switch self {
            case .emptyTitle: "Enter a title for the chat room."
            case .missingPassword: "Enter a password for a private chat room."
            }
        }
    }

    private(set) var title: String
    private(set) var limit: Int
    var isPublic: Bool
    private(set) var password: String

    init(title: String = "", limit: Int = ChatRoomSettings.maxLimit, isPublic: Bool = true, password: String = "") {
        self.title = ""
        self.limit = Self.minLimit
        self.isPublic = isPublic
        self.password = ""
        setTitle(title)
        setLimit(limit)
        setPassword(password)
    }

    mutating func setTitle(_ title: String) {
        self.title = Self.truncated(title, maxBytes: Self.maxTitleBytes)
    }

    mutating func setLimit(_ limit: Int) {
        self.limit = min(max(limit, Self.minLimit), Self.maxLimit)
    }

    mutating func setPassword(_ password: String) {
        self.password = Self.truncated(password, maxBytes: Self.maxPasswordBytes)
    }

    /// Why the request cannot go out, or nil. rAthena ignores a change with an empty title, and a private room without a
    /// password lets everybody in who sends an empty one, which is a public room that looks private.
    var problem: Problem? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }
        if !isPublic && password.isEmpty {
            return .missingPassword
        }
        return nil
    }

    /// Cuts the text to `maxBytes` of UTF-8 without splitting a character.
    static func truncated(_ text: String, maxBytes: Int) -> String {
        var text = text
        while text.utf8.count > maxBytes {
            text.removeLast()
        }
        return text
    }
}

struct ChatRoomMember: Equatable, Identifiable, Sendable {
    var name: String
    var isOwner: Bool

    var id: String {
        name
    }
}

/// One line of the room window.
struct ChatRoomLine: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// What a member said, with his name.
        case said(sender: String)

        /// The room itself: someone came or left.
        case notice
    }

    var id: Int
    var kind: Kind
    var text: String
}

/// The room the player is in, as owner or as member.
struct ChatRoom: Equatable, Sendable {
    static let maxLines = 200

    /// What `ZC_MEMBER_EXIT` did to the room.
    enum Departure: Equatable, Sendable {
        /// The player is out of the room, because he left or because of the server (a map change, a disconnect).
        case selfLeft

        /// The owner expelled the player.
        case selfExpelled

        case memberLeft(name: String)
        case memberExpelled(name: String)

        /// The name was not in the room.
        case unknown
    }

    /// The id of the room, once the server told it. The creator learns it with the first change of the room,
    /// because rAthena does not send the sign to the members of the room, himself included.
    var chatID: UInt32?

    /// The account id of the owner, when it is known: a creator is his own owner, a member took it from the sign he clicked.
    var ownerID: UInt32?

    var title: String
    var limit: Int
    var access: ChatRoomAccess

    /// The password of a room the player owns. A change of title sends it again, or the room would turn open.
    var password: String

    private(set) var members: [ChatRoomMember]
    private(set) var lines: [ChatRoomLine] = []

    /// The name of the player, to know which member he is.
    let selfName: String

    private var nextLineID = 0

    /// The player created the room and is its only member.
    init(created settings: ChatRoomSettings, ownerID: UInt32, selfName: String) {
        self.chatID = nil
        self.ownerID = ownerID
        self.title = settings.title
        self.limit = settings.limit
        self.access = settings.isPublic ? .publicRoom : .privateRoom
        self.password = settings.isPublic ? "" : settings.password
        self.members = [ChatRoomMember(name: selfName, isOwner: true)]
        self.selfName = selfName
        appendNotice("You opened the chat room \"\(settings.title)\".")
    }

    /// The server let the player in (`ZC_ENTER_ROOM`). `sign` is the sign he clicked, which has the title.
    init(entered packet: PACKET_ZC_ENTER_ROOM, sign: ChatRoomSign?, selfName: String) {
        let chatID = packet.chatId
        self.chatID = chatID
        self.ownerID = sign?.ownerID
        self.title = sign?.title ?? ""
        self.limit = sign?.limit ?? ChatRoomSettings.maxLimit
        self.access = sign?.access ?? .publicRoom
        self.password = ""
        self.members = packet.members.map { ChatRoomMember(name: $0.name, isOwner: $0.flag == 0) }
        self.selfName = selfName

        // The server marks the first member as the owner (`member.flag = i > 0`). A list that marks nobody gets it.
        if !members.isEmpty, !members.contains(where: \.isOwner) {
            members[0].isOwner = true
        }

        if title.isEmpty {
            appendNotice("You entered the chat room.")
        } else {
            appendNotice("You entered the chat room \"\(title)\".")
        }
    }

    // MARK: - Reading

    var owner: ChatRoomMember? {
        members.first(where: \.isOwner)
    }

    var isOwner: Bool {
        owner?.name == selfName
    }

    var isFull: Bool {
        members.count >= limit
    }

    func contains(memberNamed name: String) -> Bool {
        members.contains(where: { $0.name == name })
    }

    /// The members the owner can expel or give the room to: everybody but himself.
    var otherMembers: [ChatRoomMember] {
        members.filter { $0.name != selfName }
    }

    // MARK: - Members

    /// `ZC_MEMBER_NEWENTRY`.
    mutating func memberJoined(name: String) {
        guard !contains(memberNamed: name) else {
            return
        }
        members.append(ChatRoomMember(name: name, isOwner: false))
        appendNotice("\(name) entered the chat room.")
    }

    /// `ZC_MEMBER_EXIT`, which the whole room gets, the leaver included.
    mutating func memberLeft(name: String, wasExpelled: Bool) -> Departure {
        guard let index = members.firstIndex(where: { $0.name == name }) else {
            return .unknown
        }

        if name == selfName {
            return wasExpelled ? .selfExpelled : .selfLeft
        }

        let wasOwner = members[index].isOwner
        members.remove(at: index)

        // rAthena gives the room to the next member (`cd->usersd[0]`) and announces it with `ZC_ROLE_CHANGE` right after.
        if wasOwner, !members.isEmpty {
            members[0].isOwner = true
            ownerID = nil
        }

        appendNotice(wasExpelled ? "\(name) was expelled from the chat room." : "\(name) left the chat room.")
        return wasExpelled ? .memberExpelled(name: name) : .memberLeft(name: name)
    }

    /// `ZC_ROLE_CHANGE`: `role` 0 makes the member the owner, anything else makes him a normal member.
    /// A new owner takes the first place, like the swap in `chat_changechatowner`.
    mutating func roleChanged(name: String, role: Int32) {
        guard let index = members.firstIndex(where: { $0.name == name }) else {
            return
        }

        if role == 0 {
            let wasOwner = members[index].isOwner
            for position in members.indices {
                members[position].isOwner = position == index
            }
            if index != 0 {
                members.swapAt(0, index)
            }
            if !wasOwner {
                ownerID = nil
                appendNotice(name == selfName ? "You are the owner of the chat room now." : "\(name) is the owner of the chat room now.")
            }
        } else {
            members[index].isOwner = false
        }
    }

    // MARK: - Settings

    /// `ZC_CHANGE_CHATROOM`: the owner changed title, limit or access.
    mutating func apply(change packet: PACKET_ZC_CHANGE_CHATROOM) {
        chatID = packet.chatId
        ownerID = packet.ownerId
        title = packet.title
        limit = Int(packet.limit)
        access = ChatRoomAccess(type: packet.flag)
        if access == .publicRoom {
            password = ""
        }
        appendNotice("The chat room was changed: \"\(title)\", \(limit) members, \(access == .privateRoom ? "private" : "public").")
    }

    // MARK: - Lines

    mutating func appendSaid(sender: String, text: String) {
        append(ChatRoomLine(id: nextLineID, kind: .said(sender: sender), text: text))
    }

    mutating func appendNotice(_ text: String) {
        append(ChatRoomLine(id: nextLineID, kind: .notice, text: text))
    }

    private mutating func append(_ line: ChatRoomLine) {
        nextLineID += 1
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    /// Splits a chat line of the server, `"Name : text"` (`clif_process_message`), into the speaker and the text.
    static func spokenLine(_ content: String) -> (sender: String, text: String)? {
        guard let separator = content.range(of: " : ") else {
            return nil
        }
        let sender = String(content[..<separator.lowerBound])
        let text = String(content[separator.upperBound...])
        return sender.isEmpty ? nil : (sender, text)
    }
}

/// Why a join was refused. `e_refuse_enter_room` in clif.hpp.
enum ChatRoomRefusal {
    static func message(forResult result: UInt8) -> String {
        switch result {
        // rAthena answers 0 for a full room and for a room that is gone, on another map, or while the player vends.
        case 0: "The chat room is full or no longer available."
        case 1: "The password is wrong."
        case 2: "You were expelled from that chat room."
        case 4: "You do not have enough zeny to enter that chat room."
        case 5: "Your level is too low for that chat room."
        case 6: "Your level is too high for that chat room."
        case 7: "Your job cannot enter that chat room."
        default: "You cannot enter that chat room."
        }
    }

    /// The answer to `CZ_CREATE_CHATROOM` when it is not a success. `e_create_chatroom` in clif.hpp.
    static func creationMessage(forFlag flag: UInt8) -> String {
        switch flag {
        case 1: "The chat room could not be created, the limit of rooms is reached."
        case 2: "A chat room like that already exists."
        default: "The chat room could not be created."
        }
    }
}

/// Everything about chat rooms in one play session.
@Observable
final class ChatRoomState {
    /// The signs of the rooms in view, by chat id.
    var signs: [UInt32 : ChatRoomSign] = [:]

    /// The room the player is in.
    var current: ChatRoom?

    /// The room window is open. Closing it keeps the player in the room.
    var isWindowVisible = false

    /// The create window, open while this is not nil. The menu and `/chat` open it.
    var createDraft: ChatRoomSettings?

    /// The owner's settings window, open while this is not nil.
    var settingsDraft: ChatRoomSettings?

    /// A private room the player clicked, waiting for the password.
    var passwordPrompt: ChatRoomSign?

    /// The room settings that went out with `CZ_CREATE_CHATROOM`. The answer (`ZC_ACK_CREATE_CHATROOM`) does not repeat them.
    @ObservationIgnored var pendingCreate: ChatRoomSettings?

    /// The room settings that went out with `CZ_CHANGE_CHATROOM`, to keep the password.
    @ObservationIgnored var pendingChange: ChatRoomSettings?

    /// The room the player asked to enter. `ZC_ENTER_ROOM` has the members but not the title.
    @ObservationIgnored var pendingJoin: ChatRoomSign?

    // MARK: - Signs

    /// A sign appeared or changed (`ZC_ROOM_NEWENTRY`). A player owns one room, so an older sign of the same owner goes.
    func updateSign(_ sign: ChatRoomSign) {
        for (chatID, other) in signs where other.ownerID == sign.ownerID && chatID != sign.chatID {
            signs.removeValue(forKey: chatID)
        }
        signs[sign.chatID] = sign
    }

    /// `ZC_DESTROY_ROOM`.
    func removeSign(chatID: UInt32) {
        signs.removeValue(forKey: chatID)
    }

    /// An object left the view: the sign over him goes too.
    func removeSigns(ofOwner ownerID: UInt32) {
        for (chatID, sign) in signs where sign.ownerID == ownerID {
            signs.removeValue(forKey: chatID)
        }
    }

    func sign(ofOwner ownerID: UInt32) -> ChatRoomSign? {
        signs.values.first(where: { $0.ownerID == ownerID })
    }

    /// The titles to draw over heads, by owner account id, sorted by id. The room the player is in shows its current title
    /// over its current owner (the members do not get sign updates), and the creator's own sign is only known here.
    /// `resolveOwnerID` finds the account id of a player on the map by name, for a room that changed its owner.
    func displayedSigns(selfAccountID: UInt32, resolveOwnerID: (String) -> UInt32?) -> [(ownerID: UInt32, title: String)] {
        var titles: [UInt32 : String] = [:]
        for sign in signs.values {
            titles[sign.ownerID] = sign.title
        }

        if let current {
            if let chatID = current.chatID {
                for sign in signs.values where sign.chatID == chatID {
                    titles.removeValue(forKey: sign.ownerID)
                }
            }

            let ownerID: UInt32? = if current.isOwner {
                selfAccountID
            } else {
                current.ownerID ?? current.owner.flatMap { resolveOwnerID($0.name) }
            }
            if let ownerID {
                titles[ownerID] = current.title
            }
        }

        return titles.map { (ownerID: $0.key, title: $0.value) }.sorted { $0.ownerID < $1.ownerID }
    }

    // MARK: - Map change

    /// The signs belong to the map the player left. The server takes the player out of his room when he changes map.
    func resetForMapChange() {
        signs = [:]
        current = nil
        isWindowVisible = false
        createDraft = nil
        settingsDraft = nil
        passwordPrompt = nil
        pendingCreate = nil
        pendingChange = nil
        pendingJoin = nil
    }
}
