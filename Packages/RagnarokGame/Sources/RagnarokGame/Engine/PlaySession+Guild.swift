//
//  PlaySession+Guild.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation
import RagnarokNetwork
import RagnarokPackets

@Observable
final class GuildState {
    var guild = Guild()
    var invitation: GuildInvitation?
}

extension PlaySession {
    /// Handles the guild packets of rAthena at PACKETVER 20211103.
    ///
    /// `ZC_UPDATE_CHARSTAT` (a guild member logs in or out) is observed and not consumed, so another handler can
    /// read it too. Guild chat stays in `handlePacket`.
    func handleGuildPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_UPDATE_GDID:
            handleGuildBelonging(packet)
        case let packet as PACKET_ZC_GUILD_INFO:
            guildState.guild.apply(info: Guild.Info(from: packet))
        case let packet as PACKET_ZC_ACK_GUILD_MENUINTERFACE:
            guildState.guild.apply(menuFlags: Int(packet.menuFlag))
        case let packet as PACKET_ZC_MEMBERMGR_INFO:
            guildState.guild.apply(members: packet.guildMemberInfo.map(Guild.Member.init(from:)))
            refreshGuildPermissions()
        case let packet as PACKET_ZC_POSITION_ID_NAME_INFO:
            guildState.guild.apply(positionNames: packet.posInfo.map { (id: Int($0.positionID), name: $0.posName) })
        case let packet as PACKET_ZC_POSITION_INFO:
            guildState.guild.apply(positionDetails: packet.posInfo.map(Guild.Position.init(from:)))
            refreshGuildPermissions()
        case let packet as PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO:
            guildState.guild.apply(changedPositions: packet.posInfo.map(Guild.Position.init(from:)))
            refreshGuildPermissions()
        case let packet as PACKET_ZC_ACK_REQ_CHANGE_MEMBERS:
            guildState.guild.apply(memberPositions: packet.members.map {
                (characterID: $0.charId, positionID: Int($0.positionID))
            })
            refreshGuildPermissions()
        case let packet as PACKET_ZC_MYGUILD_BASIC_INFO:
            guildState.guild.apply(relations: packet.rgInfo.compactMap(Guild.Relation.init(from:)))
        case let packet as PACKET_ZC_DELETE_RELATED_GUILD:
            if let kind = Guild.Relation.Kind(rawValue: Int(packet.flag)) {
                guildState.guild.removeRelation(guildID: packet.allyID, kind: kind)
            }
        case let packet as PACKET_ZC_BAN_LIST:
            guildState.guild.apply(expulsions: packet.chars.map(Guild.Expulsion.init(from:)))
        case let packet as PACKET_ZC_GUILD_SKILLINFO:
            handleGuildSkills(packet)
        case let packet as PACKET_ZC_GUILD_NOTICE:
            guildState.guild.apply(notice: Guild.Notice(subject: packet.subject, body: packet.notice))
        case let packet as PACKET_ZC_RESULT_MAKE_GUILD:
            handleMakeGuildResult(packet)
        case let packet as PACKET_ZC_REQ_JOIN_GUILD:
            guildState.invitation = GuildInvitation(guildID: packet.guild_id, guildName: packet.guild_name)
        case let packet as PACKET_ZC_ACK_REQ_JOIN_GUILD:
            handleGuildInviteResult(packet)
        case let packet as PACKET_ZC_ACK_LEAVE_GUILD2:
            handleGuildMemberGone(characterID: packet.GID, reason: packet.reason, expelled: false)
        case let packet as PACKET_ZC_ACK_BAN_GUILD3:
            handleGuildMemberGone(characterID: packet.GID, reason: packet.reason, expelled: true)
        case let packet as PACKET_ZC_ACK_DISORGANIZE_GUILD_RESULT:
            handleGuildDisorganizeResult(packet)
        case let packet as PACKET_ZC_CHANGE_GUILD:
            handleGuildChanged(packet)
        case let packet as PACKET_ZC_REQ_ALLY_GUILD:
            addGuildMessage("\(packet.inviterGuildName) proposes an alliance. Answering alliances is not supported in this client.")
        case let packet as PACKET_ZC_UPDATE_CHARSTAT:
            guildState.guild.setOnline(accountID: packet.aid, characterID: packet.cid, isOnline: packet.status != 0)
            return false
        default:
            return false
        }
        return true
    }

    // MARK: - Requests

    /// Asks the server for everything the guild window shows: menu flags, basic info with relations,
    /// position names with members, position details, the skill list and the expulsion list.
    func refreshGuild() {
        guard guildState.guild.isInGuild else {
            return
        }

        sendPacket(PacketFactory.CZ_REQ_GUILD_MENUINTERFACE())
        for type: Int32 in [0, 1, 2, 3, 4] {
            sendPacket(PacketFactory.CZ_REQ_GUILD_MENU(type: type))
        }
    }

    /// Creates a guild. rAthena takes one Emperium from the inventory and answers with `ZC_RESULT_MAKE_GUILD`.
    func createGuild(name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            addGuildMessage("Enter a guild name.", type: .error)
            return
        }
        // The packet field is 24 bytes with the terminator.
        guard name.utf8.count <= 23 else {
            addGuildMessage("The guild name is too long.", type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_REQ_MAKE_GUILD(characterID: character.charID, name: name))
    }

    func inviteToGuild(name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            addGuildMessage("Enter a character name.", type: .error)
            return
        }

        sendPacket(PacketFactory.CZ_REQ_JOIN_GUILD2(name: name))
    }

    func answerGuildInvitation(accept: Bool) {
        guard let invitation = guildState.invitation else {
            return
        }

        guildState.invitation = nil
        sendPacket(PacketFactory.CZ_JOIN_GUILD(guildID: invitation.guildID, accept: accept))
    }

    func leaveGuild(reason: String) {
        let guild = guildState.guild
        guard guild.isInGuild else {
            return
        }

        sendPacket(PacketFactory.CZ_REQ_LEAVE_GUILD(
            guildID: guild.guildID,
            accountID: account.accountID,
            characterID: character.charID,
            reason: Self.guildReason(reason)
        ))
    }

    func expelGuildMember(_ member: Guild.Member, reason: String) {
        let guild = guildState.guild
        guard guild.isInGuild else {
            return
        }

        sendPacket(PacketFactory.CZ_REQ_BAN_GUILD(
            guildID: guild.guildID,
            accountID: member.accountID,
            characterID: member.characterID,
            reason: Self.guildReason(reason)
        ))
    }

    /// Master only. rAthena checks the name against the guild name and that no other member is left.
    func disbandGuild(confirmingName name: String) {
        guard guildState.guild.isInGuild else {
            return
        }

        sendPacket(PacketFactory.CZ_REQ_DISORGANIZE_GUILD(key: name))
    }

    /// Master only.
    func changeGuildNotice(subject: String, notice: String) {
        let guild = guildState.guild
        guard guild.isInGuild else {
            return
        }

        sendPacket(PacketFactory.CZ_GUILD_NOTICE(guildID: guild.guildID, subject: subject, notice: notice))
    }

    /// Master only. rAthena handles a guild skill id in `CZ_UPGRADE_SKILLLEVEL` (`pc_skillup`) and answers with a fresh
    /// `ZC_GUILD_SKILLINFO` for every online member. It sends nothing when the request is refused.
    func upgradeGuildSkill(_ skill: Guild.Skill) {
        let guild = guildState.guild
        guard guild.canUpgrade(skill) else {
            return
        }

        upgradeSkillLevel(skillID: skill.id)
    }

    /// Casts a guild skill on the player, the way the skill list does for a self skill. Emergency Call, Battle Orders,
    /// Regeneration and Restoration all take the caster as the target; the server applies them to the guild.
    func useGuildSkill(_ skill: Guild.Skill) {
        guard guildState.guild.isInGuild, skill.isUsable else {
            return
        }

        useSkill(skillID: skill.id, level: skill.level, onTarget: account.accountID)
    }

    // MARK: - Packet Handling

    private func handleGuildSkills(_ packet: PACKET_ZC_GUILD_SKILLINFO) {
        let skills = packet.skillInfo.map(Guild.Skill.init(from:))
        let raised = guildState.guild.apply(skills: skills, points: Int(packet.skillPoint))

        for skill in raised {
            addGuildMessage("\(guildSkillName(skill)) is now level \(skill.level).")
        }
    }

    func guildSkillName(_ skill: Guild.Skill) -> String {
        context.skillInfoTable.localizedSkillName(forSkillID: skill.id) ?? skill.name
    }

    private func handleGuildBelonging(_ packet: PACKET_ZC_UPDATE_GDID) {
        let belonging = Guild.Belonging(
            guildID: packet.guildId,
            name: packet.guildName,
            emblemID: Int(packet.emblemVersion),
            permissions: Guild.Permissions(rawValue: Int(packet.mode)),
            isMaster: packet.isMaster != 0
        )
        guildState.guild.apply(belonging: belonging)
        refreshGuildPermissions()

        // The server sends this when the player enters the guild or logs in, and again when the emblem or the
        // master changes. It sends no member list, positions or relations on its own at that point.
        refreshGuild()
    }

    private func handleMakeGuildResult(_ packet: PACKET_ZC_RESULT_MAKE_GUILD) {
        switch packet.result {
        case 0:
            addGuildMessage("Guild has been created.")
        case 1:
            addGuildMessage("You are already in a guild.", type: .error)
        case 2:
            addGuildMessage("That guild name already exists.", type: .error)
        case 3:
            addGuildMessage("You need an Emperium to create a guild.", type: .error)
        default:
            addGuildMessage("Failed to create a guild.", type: .error)
        }
    }

    private func handleGuildInviteResult(_ packet: PACKET_ZC_ACK_REQ_JOIN_GUILD) {
        switch packet.result {
        case 0:
            addGuildMessage("That player is already in a guild or cannot be invited.", type: .error)
        case 1:
            addGuildMessage("The guild invitation was declined.", type: .error)
        case 2:
            addGuildMessage("The guild invitation was accepted.")
        case 3:
            addGuildMessage("The guild is full.", type: .error)
        default:
            addGuildMessage("Could not invite that player to the guild.", type: .error)
        }
    }

    private func handleGuildMemberGone(characterID: UInt32, reason: String, expelled: Bool) {
        if characterID == character.charID {
            guildState.guild.reset()
            addGuildMessage(expelled ? "You were expelled from the guild." : "You left the guild.")
            return
        }

        let member = guildState.guild.removeMember(characterID: characterID, expelledFor: expelled ? reason : nil)
        let name = member?.name ?? "A member"
        let suffix = reason.isEmpty ? "" : " (\(reason))"
        addGuildMessage("\(name) \(expelled ? "was expelled from" : "left") the guild.\(suffix)")
    }

    private func handleGuildDisorganizeResult(_ packet: PACKET_ZC_ACK_DISORGANIZE_GUILD_RESULT) {
        switch packet.result {
        case 0:
            guildState.guild.reset()
            addGuildMessage("The guild has been disbanded.")
        case 1:
            addGuildMessage("The guild name does not match.", type: .error)
        case 2:
            addGuildMessage("The guild still has members.", type: .error)
        default:
            addGuildMessage("Failed to disband the guild.", type: .error)
        }
    }

    /// `ZC_CHANGE_GUILD` is sent to everybody nearby, only the player's own entry matters here.
    private func handleGuildChanged(_ packet: PACKET_ZC_CHANGE_GUILD) {
        guard packet.AID == account.accountID else {
            return
        }

        if packet.guild_id == 0 {
            guildState.guild.reset()
        } else if UInt32(bitPattern: packet.guild_id) == guildState.guild.guildID {
            guildState.guild.emblemID = Int(packet.emblem_id)
        }
    }

    private func refreshGuildPermissions() {
        guildState.guild.refreshPermissions(characterID: character.charID)
    }

    // MARK: - Helpers

    /// The reason field of leave and expel is 40 bytes with the terminator.
    private static func guildReason(_ reason: String) -> String {
        var reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while reason.utf8.count > 39 {
            reason.removeLast()
        }
        return reason
    }

    private func addGuildMessage(_ content: String, type: MessageCenter.MessageType = .info) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}

// MARK: - Packet Conversion

extension Guild.Info {
    init(from packet: PACKET_ZC_GUILD_INFO) {
        self.init(
            guildID: UInt32(bitPattern: packet.GDID),
            name: packet.guildname,
            level: Int(packet.level),
            onlineCount: Int(packet.userNum),
            maxMemberCount: Int(packet.maxUserNum),
            averageLevel: Int(packet.userAverageLevel),
            exp: Int(packet.exp),
            nextExp: Int(packet.maxExp),
            emblemID: Int(packet.emblemVersion),
            masterCharacterID: UInt32(bitPattern: packet.masterGID),
            masterName: packet.masterName,
            castleName: packet.manageLand
        )
    }
}

extension Guild.Skill {
    init(from data: GUILD_SKILLDATA) {
        self.init(
            id: Int(data.id),
            name: data.name,
            level: Int(data.level),
            spCost: Int(data.sp),
            range: Int(data.range2),
            type: Int(data.inf),
            isUpgradable: data.upFlag != 0
        )
    }
}

extension Guild.Member {
    init(from info: GUILD_MEMBER_INFO) {
        self.init(
            accountID: info.AID,
            characterID: info.GID,
            name: info.char_name,
            job: Int(info.job),
            baseLevel: Int(info.level),
            contribution: Int(info.contributionExp),
            positionID: Int(info.positionID),
            isOnline: info.currentState != 0,
            lastLogin: info.lastLoginTime > 0 ? Date(timeIntervalSince1970: TimeInterval(info.lastLoginTime)) : nil
        )
    }
}

extension Guild.Position {
    init(from info: PACKET_ZC_POSITION_INFO_sub) {
        self.init(
            id: Int(info.positionID),
            permissions: Guild.Permissions(rawValue: Int(info.right)),
            ranking: Int(info.ranking),
            expRate: Int(info.payRate)
        )
    }

    init(from info: PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO_sub) {
        self.init(
            id: Int(info.positionID),
            name: info.posName,
            permissions: Guild.Permissions(rawValue: Int(info.mode)),
            ranking: Int(info.ranking),
            expRate: Int(info.payRate)
        )
    }
}

extension Guild.Relation {
    init?(from info: RELATED_GUILD_INFO) {
        guard let kind = Kind(rawValue: Int(info.relation)) else {
            return nil
        }

        self.init(kind: kind, guildID: UInt32(bitPattern: info.GDID), name: info.guildname)
    }
}

extension Guild.Expulsion {
    init(from info: PACKET_ZC_BAN_LIST_sub) {
        self.init(characterID: UInt32(bitPattern: info.char_id), name: info.char_name, reason: info.message)
    }
}
