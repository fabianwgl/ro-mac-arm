//
//  Guild.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The guild the player belongs to, as the map server describes it.
///
/// The server sends the pieces in separate packets (belonging, basic info, members, positions, relations,
/// notice, expulsion list), so every piece has its own `apply` function and the rest keeps its value.
struct Guild: Equatable, Sendable {
    /// Guild position permissions, rAthena's `e_guild_permission`.
    struct Permissions: OptionSet, Equatable, Sendable {
        let rawValue: Int

        static let invite = Permissions(rawValue: 0x001)
        static let expel = Permissions(rawValue: 0x010)
        static let storage = Permissions(rawValue: 0x100)
    }

    struct Member: Identifiable, Equatable, Sendable {
        var accountID: UInt32
        var characterID: UInt32
        var name: String
        var job: Int
        var baseLevel: Int
        var contribution: Int
        var positionID: Int
        var isOnline: Bool
        /// Unix time of the last login, `nil` when the server sends 0.
        var lastLogin: Date?

        var id: UInt32 {
            characterID
        }

        /// Position 0 is always the guild master.
        var isMaster: Bool {
            positionID == 0
        }
    }

    struct Position: Identifiable, Equatable, Sendable {
        var id: Int
        var name: String
        var permissions: Permissions
        var ranking: Int
        /// Share of the member's experience that goes to the guild, in percent.
        var expRate: Int

        init(id: Int, name: String = "", permissions: Permissions = [], ranking: Int = 0, expRate: Int = 0) {
            self.id = id
            self.name = name
            self.permissions = permissions
            self.ranking = ranking
            self.expRate = expRate
        }
    }

    struct Relation: Identifiable, Equatable, Sendable {
        enum Kind: Int, Sendable {
            case alliance = 0
            case hostile = 1
        }

        var kind: Kind
        var guildID: UInt32
        var name: String

        var id: String {
            "\(kind.rawValue)-\(guildID)"
        }
    }

    struct Expulsion: Identifiable, Equatable, Sendable {
        var characterID: UInt32
        var name: String
        var reason: String

        var id: UInt32 {
            characterID
        }
    }

    struct Notice: Equatable, Sendable {
        var subject = ""
        var body = ""

        var isEmpty: Bool {
            subject.isEmpty && body.isEmpty
        }
    }

    /// `ZC_UPDATE_GDID`: the player's own belonging to the guild.
    struct Belonging: Equatable, Sendable {
        var guildID: UInt32
        var name: String
        var emblemID: Int
        var permissions: Permissions
        var isMaster: Bool
    }

    /// `ZC_GUILD_INFO`.
    struct Info: Equatable, Sendable {
        var guildID: UInt32
        var name: String
        var level: Int
        var onlineCount: Int
        var maxMemberCount: Int
        var averageLevel: Int
        var exp: Int
        var nextExp: Int
        var emblemID: Int
        var masterCharacterID: UInt32
        var masterName: String
        var castleName: String
    }

    /// `ZC_ACK_GUILD_MENUINTERFACE` bit that enables the notice tab, which only the master gets.
    static let noticeMenuFlag = 0x80

    private(set) var guildID: UInt32 = 0
    var name = ""
    var level = 0
    private(set) var reportedOnlineCount = 0
    var maxMemberCount = 0
    var averageLevel = 0
    var exp = 0
    var nextExp = 0
    var emblemID = 0
    var masterCharacterID: UInt32 = 0
    var masterName = ""
    var castleName = ""
    private(set) var permissions: Permissions = []
    private(set) var isMaster = false
    private(set) var menuFlags = 0
    private(set) var notice = Notice()
    private(set) var members: [Member] = []
    private(set) var positions: [Position] = []
    private(set) var relations: [Relation] = []
    private(set) var expulsions: [Expulsion] = []

    var isInGuild: Bool {
        guildID != 0
    }

    var canInvite: Bool {
        isMaster || permissions.contains(.invite)
    }

    var canExpel: Bool {
        isMaster || permissions.contains(.expel)
    }

    var canEditNotice: Bool {
        isMaster || menuFlags & Self.noticeMenuFlag != 0
    }

    /// Members online, counted from the member list once the server has sent it.
    var onlineCount: Int {
        members.isEmpty ? reportedOnlineCount : members.filter(\.isOnline).count
    }

    /// Members in the guild, `nil` until the server has sent the member list.
    var memberCount: Int? {
        members.isEmpty ? nil : members.count
    }

    var expFraction: Double {
        guard nextExp > 0 else {
            return 0
        }
        return min(max(Double(exp) / Double(nextExp), 0), 1)
    }

    var alliances: [Relation] {
        relations.filter { $0.kind == .alliance }
    }

    var hostileGuilds: [Relation] {
        relations.filter { $0.kind == .hostile }
    }

    init() {
    }

    // MARK: - Lookup

    func member(characterID: UInt32) -> Member? {
        members.first(where: { $0.characterID == characterID })
    }

    func position(id: Int) -> Position? {
        positions.first(where: { $0.id == id })
    }

    /// The position's name, `nil` while the server has not sent the name or when it is empty.
    func positionName(id: Int) -> String? {
        guard let name = position(id: id)?.name, !name.isEmpty else {
            return nil
        }
        return name
    }

    // MARK: - Apply

    /// Joining another guild, or leaving, drops everything known about the previous one.
    mutating func apply(belonging: Belonging) {
        if belonging.guildID != guildID {
            reset()
        }

        guildID = belonging.guildID
        name = belonging.name
        emblemID = belonging.emblemID
        permissions = belonging.permissions
        isMaster = belonging.isMaster
    }

    mutating func apply(info: Info) {
        if info.guildID != guildID {
            reset()
        }

        guildID = info.guildID
        name = info.name
        level = info.level
        reportedOnlineCount = info.onlineCount
        maxMemberCount = info.maxMemberCount
        averageLevel = info.averageLevel
        exp = info.exp
        nextExp = info.nextExp
        emblemID = info.emblemID
        masterCharacterID = info.masterCharacterID
        masterName = info.masterName
        castleName = info.castleName
    }

    mutating func apply(menuFlags: Int) {
        self.menuFlags = menuFlags
    }

    mutating func apply(members: [Member]) {
        self.members = members
    }

    /// `ZC_POSITION_ID_NAME_INFO`: names for every position id, the unused ones empty.
    mutating func apply(positionNames: [(id: Int, name: String)]) {
        for entry in positionNames {
            updatePosition(id: entry.id) { position in
                position.name = entry.name
            }
        }
    }

    /// `ZC_POSITION_INFO`: permissions, ranking and experience rate of every position.
    mutating func apply(positionDetails: [Position]) {
        for details in positionDetails {
            updatePosition(id: details.id) { position in
                position.permissions = details.permissions
                position.ranking = details.ranking
                position.expRate = details.expRate
            }
        }
    }

    /// `ZC_ACK_CHANGE_GUILD_POSITIONINFO`: full position records, the name included.
    mutating func apply(changedPositions: [Position]) {
        for changed in changedPositions {
            updatePosition(id: changed.id) { position in
                position = changed
            }
        }
    }

    /// Recomputes the player's permissions from the position the member list gives the player.
    ///
    /// The server tells the permissions once, with `ZC_UPDATE_GDID`, and not again when a master edits positions.
    /// The master keeps them all.
    mutating func refreshPermissions(characterID: UInt32) {
        guard !isMaster,
              let member = member(characterID: characterID),
              let position = position(id: member.positionID) else {
            return
        }

        permissions = position.permissions
    }

    /// `ZC_ACK_REQ_CHANGE_MEMBERS`: the new position of members.
    mutating func apply(memberPositions: [(characterID: UInt32, positionID: Int)]) {
        for entry in memberPositions {
            guard let index = members.firstIndex(where: { $0.characterID == entry.characterID }) else {
                continue
            }
            members[index].positionID = entry.positionID
        }
    }

    mutating func apply(relations: [Relation]) {
        self.relations = relations
    }

    mutating func removeRelation(guildID: UInt32, kind: Relation.Kind) {
        relations.removeAll(where: { $0.guildID == guildID && $0.kind == kind })
    }

    mutating func apply(notice: Notice) {
        self.notice = notice
    }

    mutating func apply(expulsions: [Expulsion]) {
        self.expulsions = expulsions
    }

    /// `ZC_UPDATE_CHARSTAT`: a member logged in or out.
    ///
    /// Matches by character id, the account id only when the server sends 0 for the character.
    mutating func setOnline(accountID: UInt32, characterID: UInt32, isOnline: Bool) {
        let index: Int?
        if characterID != 0 {
            index = members.firstIndex(where: { $0.characterID == characterID })
        } else {
            index = members.firstIndex(where: { $0.accountID == accountID })
        }

        guard let index else {
            return
        }

        members[index].isOnline = isOnline
    }

    /// Removes a member and, when `reason` is given, records the expulsion. Returns the removed member.
    @discardableResult
    mutating func removeMember(characterID: UInt32, expelledFor reason: String? = nil) -> Member? {
        guard let index = members.firstIndex(where: { $0.characterID == characterID }) else {
            return nil
        }

        let member = members.remove(at: index)

        if let reason {
            expulsions.removeAll(where: { $0.characterID == characterID })
            expulsions.append(Expulsion(characterID: member.characterID, name: member.name, reason: reason))
        }

        return member
    }

    mutating func reset() {
        self = Guild()
    }

    // MARK: - Private

    private mutating func updatePosition(id: Int, _ update: (inout Position) -> Void) {
        if let index = positions.firstIndex(where: { $0.id == id }) {
            update(&positions[index])
        } else {
            var position = Position(id: id)
            update(&position)
            positions.append(position)
            positions.sort(by: { $0.id < $1.id })
        }
    }
}

struct GuildInvitation: Identifiable, Equatable, Sendable {
    var guildID: UInt32
    var guildName: String

    var id: UInt32 {
        guildID
    }
}
