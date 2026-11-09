import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

/// Guild skills: the `ZC_GUILD_SKILLINFO` list, the skill point count and what the guild window may do with them.
@MainActor
struct GuildSkillTests {
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

    private func enterGuild(_ session: PlaySession, isMaster: Bool) {
        var packet = PACKET_ZC_UPDATE_GDID()
        packet.guildId = 7
        packet.emblemVersion = 3
        packet.mode = isMaster ? 0x11 : 0
        packet.isMaster = isMaster ? 1 : 0
        packet.guildName = "Poring Hunters"
        _ = session.handleGuildPacket(packet)
    }

    private func skillData(id: UInt16, name: String, inf: Int32, level: UInt16, sp: UInt16 = 0, upFlag: UInt8 = 0) -> GUILD_SKILLDATA {
        var data = GUILD_SKILLDATA()
        data.id = id
        data.name = name
        data.inf = inf
        data.level = level
        data.sp = sp
        data.range2 = 9
        data.upFlag = upFlag
        return data
    }

    private func skillInfoPacket(points: Int16, _ skills: [GUILD_SKILLDATA]) -> PACKET_ZC_GUILD_SKILLINFO {
        var packet = PACKET_ZC_GUILD_SKILLINFO()
        packet.skillPoint = points
        packet.skillInfo = skills
        return packet
    }

    private func belonging(isMaster: Bool) -> Guild.Belonging {
        Guild.Belonging(guildID: 7, name: "G", emblemID: 0, permissions: [], isMaster: isMaster)
    }

    // MARK: - State

    @Test func skillListFillsSkillsAndPoints() {
        var guild = Guild()
        guild.apply(belonging: belonging(isMaster: true))

        let raised = guild.apply(
            skills: [
                Guild.Skill(id: 10000, name: "GD_APPROVAL", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: true),
                Guild.Skill(id: 10013, name: "GD_EMERGENCYCALL", level: 0, spCost: 0, range: 0, type: 4, isUpgradable: true),
            ],
            points: 3
        )

        #expect(raised.isEmpty)
        #expect(guild.skills.count == 2)
        #expect(guild.skillPoints == 3)
        #expect(guild.skill(id: 10000)?.isPassive == true)
        #expect(guild.skill(id: 10013)?.isUsable == false)
    }

    @Test func raisedSkillsAreReportedAfterTheFirstList() {
        var guild = Guild()
        let before = [Guild.Skill(id: 10000, name: "GD_APPROVAL", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: true)]
        var after = before
        after[0].level = 2

        guild.apply(skills: before, points: 2)
        let raised = guild.apply(skills: after, points: 1)

        #expect(raised.map(\.id) == [10000])
        #expect(guild.skillPoints == 1)

        // The same list again changes nothing.
        #expect(guild.apply(skills: after, points: 1).isEmpty)
    }

    @Test func selfSkillWithLevelIsUsable() {
        let learned = Guild.Skill(id: 10013, name: "GD_EMERGENCYCALL", level: 1, spCost: 100, range: 0, type: 4, isUpgradable: false)
        var unlearned = learned
        unlearned.level = 0
        let passive = Guild.Skill(id: 10000, name: "GD_APPROVAL", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: false)

        #expect(learned.isUsable)
        #expect(unlearned.isUsable == false)
        #expect(passive.isUsable == false)
    }

    @Test func onlyTheMasterWithPointsCanUpgrade() {
        let upgradable = Guild.Skill(id: 10000, name: "GD_APPROVAL", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: true)
        let capped = Guild.Skill(id: 10001, name: "GD_KAFRACONTRACT", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: false)

        var master = Guild()
        master.apply(belonging: belonging(isMaster: true))
        master.apply(skills: [upgradable, capped], points: 1)
        #expect(master.canUpgrade(upgradable))
        #expect(master.canUpgrade(capped) == false)

        master.apply(skills: [upgradable, capped], points: 0)
        #expect(master.canUpgrade(upgradable) == false)

        var member = Guild()
        member.apply(belonging: belonging(isMaster: false))
        member.apply(skills: [upgradable], points: 5)
        #expect(member.canUpgrade(upgradable) == false)
    }

    @Test func leavingTheGuildDropsTheSkills() {
        var guild = Guild()
        guild.apply(belonging: belonging(isMaster: true))
        guild.apply(skills: [Guild.Skill(id: 10000, name: "GD_APPROVAL", level: 1, spCost: 0, range: 0, type: 0, isUpgradable: true)], points: 2)

        guild.reset()

        #expect(guild.skills.isEmpty)
        #expect(guild.skillPoints == 0)
    }

    // MARK: - Packet handling

    @Test func skillInfoPacketUpdatesState() {
        let session = makeSession()
        enterGuild(session, isMaster: true)

        let handled = session.handleGuildPacket(skillInfoPacket(points: 2, [
            skillData(id: 10000, name: "GD_APPROVAL", inf: 0, level: 1, upFlag: 1),
            skillData(id: 10013, name: "GD_EMERGENCYCALL", inf: 4, level: 1, sp: 100, upFlag: 1),
        ]))

        #expect(handled)
        let guild = session.guildState.guild
        #expect(guild.skillPoints == 2)
        #expect(guild.skills.map(\.name) == ["GD_APPROVAL", "GD_EMERGENCYCALL"])
        #expect(guild.skill(id: 10013)?.spCost == 100)
        #expect(guild.skill(id: 10013)?.isUsable == true)
        #expect(guild.skill(id: 10000)?.isUpgradable == true)
    }

    @Test func levelUpIsAnnouncedInTheMessageCenter() {
        let session = makeSession()
        enterGuild(session, isMaster: true)
        _ = session.handleGuildPacket(skillInfoPacket(points: 1, [
            skillData(id: 10000, name: "GD_APPROVAL", inf: 0, level: 1, upFlag: 1),
        ]))
        let messageCount = session.messageCenter.messages.count

        _ = session.handleGuildPacket(skillInfoPacket(points: 0, [
            skillData(id: 10000, name: "GD_APPROVAL", inf: 0, level: 2, upFlag: 1),
        ]))

        #expect(session.guildState.guild.skillPoints == 0)
        #expect(session.messageCenter.messages.count == messageCount + 1)
        #expect(session.messageCenter.messages.last?.content.hasSuffix("is now level 2.") == true)
    }

    @Test func upgradeAndUseAreGuardedWithoutAGuild() {
        let session = makeSession()
        let skill = Guild.Skill(id: 10013, name: "GD_EMERGENCYCALL", level: 1, spCost: 100, range: 0, type: 4, isUpgradable: true)

        // Without a guild or a connection these must do nothing and not crash.
        session.upgradeGuildSkill(skill)
        session.useGuildSkill(skill)

        #expect(session.guildState.guild.skills.isEmpty)
    }
}
