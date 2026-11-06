import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Feeds the guild packets of rAthena (PACKETVER 20211103) to a play session without a connection.
@MainActor
struct GuildPacketHandlingTests {
    private static let characterID: UInt32 = 150000
    private static let accountID: UInt32 = 2000001

    private func makeSession() -> PlaySession {
        var loginPacket = PACKET_AC_ACCEPT_LOGIN()
        loginPacket.AID = Self.accountID
        var character = CharacterInfo()
        character.charID = Self.characterID
        character.name = "Leon"

        let context = GameContext.testing
        return PlaySession(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager, preferences: context.preferences),
            account: AccountInfo(from: loginPacket),
            character: character
        )
    }

    private func belongingPacket(guildID: UInt32 = 7, isMaster: Bool = false, mode: UInt32 = 0) -> PACKET_ZC_UPDATE_GDID {
        var packet = PACKET_ZC_UPDATE_GDID()
        packet.guildId = guildID
        packet.emblemVersion = 3
        packet.mode = mode
        packet.isMaster = isMaster ? 1 : 0
        packet.guildName = "Poring Hunters"
        return packet
    }

    private func memberInfo(characterID: UInt32, name: String, positionID: Int32, isOnline: Bool) -> GUILD_MEMBER_INFO {
        var info = GUILD_MEMBER_INFO()
        info.AID = characterID + 1_000_000
        info.GID = characterID
        info.char_name = name
        info.job = 7
        info.level = 45
        info.contributionExp = 1200
        info.currentState = isOnline ? 1 : 0
        info.positionID = positionID
        info.lastLoginTime = 1_700_000_000
        return info
    }

    private func enterGuild(_ session: PlaySession, isMaster: Bool = false) {
        _ = session.handleGuildPacket(belongingPacket(isMaster: isMaster, mode: isMaster ? 0x11 : 0))

        var members = PACKET_ZC_MEMBERMGR_INFO()
        members.guildMemberInfo = [
            memberInfo(characterID: Self.characterID, name: "Leon", positionID: isMaster ? 0 : 1, isOnline: true),
            memberInfo(characterID: 150001, name: "Poring", positionID: 1, isOnline: false),
        ]
        _ = session.handleGuildPacket(members)
    }

    @Test func belongingPacketJoinsGuild() {
        let session = makeSession()

        let handled = session.handleGuildPacket(belongingPacket(isMaster: true, mode: 0x11))

        #expect(handled)
        let guild = session.guildState.guild
        #expect(guild.isInGuild)
        #expect(guild.guildID == 7)
        #expect(guild.name == "Poring Hunters")
        #expect(guild.emblemID == 3)
        #expect(guild.isMaster)
        #expect(guild.permissions == [.invite, .expel])
    }

    @Test func infoPacketFillsBasicInfo() {
        let session = makeSession()
        var packet = PACKET_ZC_GUILD_INFO()
        packet.GDID = 7
        packet.level = 5
        packet.userNum = 2
        packet.maxUserNum = 26
        packet.userAverageLevel = 61
        packet.exp = 300
        packet.maxExp = 1200
        packet.emblemVersion = 3
        packet.guildname = "Poring Hunters"
        packet.manageLand = "Valkyrie"
        packet.masterGID = Int32(Self.characterID)
        packet.masterName = "Leon"

        #expect(session.handleGuildPacket(packet))

        let guild = session.guildState.guild
        #expect(guild.guildID == 7)
        #expect(guild.level == 5)
        #expect(guild.maxMemberCount == 26)
        #expect(guild.averageLevel == 61)
        #expect(guild.expFraction == 0.25)
        #expect(guild.masterName == "Leon")
        #expect(guild.masterCharacterID == Self.characterID)
        #expect(guild.castleName == "Valkyrie")
    }

    @Test func memberListPacketFillsMembers() {
        let session = makeSession()
        enterGuild(session)

        let guild = session.guildState.guild
        #expect(guild.members.map(\.name) == ["Leon", "Poring"])
        #expect(guild.members[0].isOnline)
        #expect(guild.members[1].isOnline == false)
        #expect(guild.members[1].job == 7)
        #expect(guild.members[1].baseLevel == 45)
        #expect(guild.members[1].contribution == 1200)
        #expect(guild.members[1].lastLogin == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func positionPacketsFillPositions() {
        let session = makeSession()
        enterGuild(session)

        var names = PACKET_ZC_POSITION_ID_NAME_INFO()
        for index in names.posInfo.indices {
            names.posInfo[index].positionID = Int32(index)
            names.posInfo[index].posName = index == 0 ? "Guild Master" : (index == 1 ? "Member" : "")
        }
        #expect(session.handleGuildPacket(names))

        var details = PACKET_ZC_POSITION_INFO()
        var first = PACKET_ZC_POSITION_INFO_sub()
        first.positionID = 0
        first.right = 0x11
        var second = PACKET_ZC_POSITION_INFO_sub()
        second.positionID = 1
        second.payRate = 20
        details.posInfo = [first, second]
        #expect(session.handleGuildPacket(details))

        let guild = session.guildState.guild
        #expect(guild.positionName(id: 0) == "Guild Master")
        #expect(guild.position(id: 0)?.permissions == [.invite, .expel])
        #expect(guild.position(id: 1)?.expRate == 20)
        #expect(guild.positionName(id: 5) == nil)
    }

    @Test func changedPositionPacketGivesOwnPositionPermissions() {
        let session = makeSession()
        enterGuild(session)

        var sub = PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO_sub()
        sub.positionID = 1
        sub.mode = 0x01
        sub.payRate = 10
        sub.posName = "Recruiter"
        var packet = PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO()
        packet.posInfo = [sub]

        #expect(session.handleGuildPacket(packet))

        let guild = session.guildState.guild
        #expect(guild.positionName(id: 1) == "Recruiter")
        #expect(guild.canInvite)
        #expect(guild.canExpel == false)
    }

    @Test func changedMemberPositionPacketMovesMember() {
        let session = makeSession()
        enterGuild(session)

        var sub = PACKET_ZC_ACK_REQ_CHANGE_MEMBERS_sub()
        sub.accId = 150001 + 1_000_000
        sub.charId = 150001
        sub.positionID = 3
        var packet = PACKET_ZC_ACK_REQ_CHANGE_MEMBERS()
        packet.members = [sub]

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.member(characterID: 150001)?.positionID == 3)
    }

    @Test func relationPacketsFillAndRemoveRelations() {
        let session = makeSession()
        enterGuild(session)

        var ally = RELATED_GUILD_INFO()
        ally.relation = 0
        ally.GDID = 11
        ally.guildname = "Friends"
        var enemy = RELATED_GUILD_INFO()
        enemy.relation = 1
        enemy.GDID = 12
        enemy.guildname = "Foes"
        var packet = PACKET_ZC_MYGUILD_BASIC_INFO()
        packet.rgInfo = [ally, enemy]

        #expect(session.handleGuildPacket(packet))
        #expect(session.guildState.guild.alliances.map(\.name) == ["Friends"])
        #expect(session.guildState.guild.hostileGuilds.map(\.name) == ["Foes"])

        var removal = PACKET_ZC_DELETE_RELATED_GUILD()
        removal.allyID = 12
        removal.flag = 1
        #expect(session.handleGuildPacket(removal))
        #expect(session.guildState.guild.hostileGuilds.isEmpty)
        #expect(session.guildState.guild.alliances.count == 1)
    }

    @Test func noticePacketSetsNotice() {
        let session = makeSession()
        enterGuild(session)
        var packet = PACKET_ZC_GUILD_NOTICE()
        packet.subject = "Siege tonight"
        packet.notice = "Meet at the portal."

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.notice == Guild.Notice(subject: "Siege tonight", body: "Meet at the portal."))
    }

    @Test func memberLoginPacketUpdatesOnlineStateAndIsNotConsumed() {
        let session = makeSession()
        enterGuild(session)
        var packet = PACKET_ZC_UPDATE_CHARSTAT()
        packet.aid = 150001 + 1_000_000
        packet.cid = 150001
        packet.status = 1

        let handled = session.handleGuildPacket(packet)

        // Not consumed, a party handler can read the same packet.
        #expect(handled == false)
        #expect(session.guildState.guild.member(characterID: 150001)?.isOnline == true)

        packet.status = 0
        _ = session.handleGuildPacket(packet)
        #expect(session.guildState.guild.member(characterID: 150001)?.isOnline == false)
    }

    @Test func leavePacketForAnotherMemberRemovesThem() {
        let session = makeSession()
        enterGuild(session)
        var packet = PACKET_ZC_ACK_LEAVE_GUILD2()
        packet.GID = 150001
        packet.reason = "Bye"

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.members.map(\.name) == ["Leon"])
        #expect(session.guildState.guild.expulsions.isEmpty)
        #expect(session.messageCenter.messages.last?.content == "Poring left the guild. (Bye)")
    }

    @Test func leavePacketForOwnCharacterResetsGuild() {
        let session = makeSession()
        enterGuild(session)
        var packet = PACKET_ZC_ACK_LEAVE_GUILD2()
        packet.GID = Self.characterID

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.isInGuild == false)
        #expect(session.guildState.guild.members.isEmpty)
    }

    @Test func banPacketRecordsExpulsion() {
        let session = makeSession()
        enterGuild(session, isMaster: true)
        var packet = PACKET_ZC_ACK_BAN_GUILD3()
        packet.GID = 150001
        packet.reason = "Inactive"

        #expect(session.handleGuildPacket(packet))

        let guild = session.guildState.guild
        #expect(guild.members.map(\.name) == ["Leon"])
        #expect(guild.expulsions == [Guild.Expulsion(characterID: 150001, name: "Poring", reason: "Inactive")])
    }

    @Test func banPacketForOwnCharacterResetsGuild() {
        let session = makeSession()
        enterGuild(session)
        var packet = PACKET_ZC_ACK_BAN_GUILD3()
        packet.GID = Self.characterID
        packet.reason = "Inactive"

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.isInGuild == false)
    }

    @Test func banListPacketFillsExpulsions() {
        let session = makeSession()
        enterGuild(session)
        var entry = PACKET_ZC_BAN_LIST_sub()
        entry.char_id = 150009
        entry.message = "Spam"
        entry.char_name = "Spammer"
        var packet = PACKET_ZC_BAN_LIST()
        packet.chars = [entry]

        #expect(session.handleGuildPacket(packet))

        #expect(session.guildState.guild.expulsions == [Guild.Expulsion(characterID: 150009, name: "Spammer", reason: "Spam")])
    }

    @Test func makeGuildResultsAddMessages() {
        let session = makeSession()

        for (result, text) in [
            (UInt8(0), "Guild has been created."),
            (UInt8(1), "You are already in a guild."),
            (UInt8(2), "That guild name already exists."),
            (UInt8(3), "You need an Emperium to create a guild."),
        ] {
            var packet = PACKET_ZC_RESULT_MAKE_GUILD()
            packet.result = result
            #expect(session.handleGuildPacket(packet))
            #expect(session.messageCenter.messages.last?.content == text)
        }
    }

    @Test func invitationPacketAndAnswer() {
        let session = makeSession()
        var packet = PACKET_ZC_REQ_JOIN_GUILD()
        packet.guild_id = 9
        packet.guild_name = "Other Guild"

        #expect(session.handleGuildPacket(packet))
        #expect(session.guildState.invitation == GuildInvitation(guildID: 9, guildName: "Other Guild"))

        session.answerGuildInvitation(accept: false)
        #expect(session.guildState.invitation == nil)
    }

    @Test func disbandResultResetsGuildOnlyOnSuccess() {
        let session = makeSession()
        enterGuild(session, isMaster: true)

        var refused = PACKET_ZC_ACK_DISORGANIZE_GUILD_RESULT()
        refused.result = 2
        #expect(session.handleGuildPacket(refused))
        #expect(session.guildState.guild.isInGuild)
        #expect(session.messageCenter.messages.last?.content == "The guild still has members.")

        var done = PACKET_ZC_ACK_DISORGANIZE_GUILD_RESULT()
        done.result = 0
        #expect(session.handleGuildPacket(done))
        #expect(session.guildState.guild.isInGuild == false)
    }

    @Test func changeGuildPacketOnlyAppliesToOwnAccount() {
        let session = makeSession()
        enterGuild(session)

        var other = PACKET_ZC_CHANGE_GUILD()
        other.AID = 5
        other.guild_id = 0
        #expect(session.handleGuildPacket(other))
        #expect(session.guildState.guild.isInGuild)

        var ownEmblem = PACKET_ZC_CHANGE_GUILD()
        ownEmblem.AID = Self.accountID
        ownEmblem.guild_id = 7
        ownEmblem.emblem_id = 12
        #expect(session.handleGuildPacket(ownEmblem))
        #expect(session.guildState.guild.emblemID == 12)

        var ownLeft = PACKET_ZC_CHANGE_GUILD()
        ownLeft.AID = Self.accountID
        ownLeft.guild_id = 0
        #expect(session.handleGuildPacket(ownLeft))
        #expect(session.guildState.guild.isInGuild == false)
    }

    @Test func createGuildRejectsEmptyAndLongNames() {
        let session = makeSession()

        session.createGuild(name: "   ")
        #expect(session.messageCenter.messages.last?.content == "Enter a guild name.")

        session.createGuild(name: String(repeating: "x", count: 24))
        #expect(session.messageCenter.messages.last?.content == "The guild name is too long.")
    }

    @Test func unrelatedPacketIsNotHandled() {
        let session = makeSession()

        #expect(session.handleGuildPacket(PACKET_ZC_GUILD_CHAT()) == false)
    }
}
