import Foundation
import Testing
@testable import RagnarokGame

struct GuildTests {
    @Test func newGuildIsNotInGuild() {
        let guild = Guild()

        #expect(guild.isInGuild == false)
        #expect(guild.canInvite == false)
        #expect(guild.canExpel == false)
        #expect(guild.canEditNotice == false)
        #expect(guild.memberCount == nil)
        #expect(guild.onlineCount == 0)
    }

    @Test func belongingSetsGuildAndPermissions() {
        var guild = Guild()

        guild.apply(belonging: belonging(guildID: 7, name: "Poring Hunters", permissions: [.invite]))

        #expect(guild.isInGuild)
        #expect(guild.guildID == 7)
        #expect(guild.name == "Poring Hunters")
        #expect(guild.canInvite)
        #expect(guild.canExpel == false)
        #expect(guild.isMaster == false)
    }

    @Test func masterCanInviteExpelAndEditNotice() {
        var guild = Guild()

        guild.apply(belonging: belonging(guildID: 7, isMaster: true))

        #expect(guild.canInvite)
        #expect(guild.canExpel)
        #expect(guild.canEditNotice)
    }

    @Test func menuFlagEnablesNoticeEditing() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7))

        // A member gets 0x57 from the server, the master 0xd7.
        guild.apply(menuFlags: 0x57)
        #expect(guild.canEditNotice == false)

        guild.apply(menuFlags: 0xd7)
        #expect(guild.canEditNotice)
    }

    @Test func belongingToAnotherGuildDropsOldData() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7))
        guild.apply(members: [member(characterID: 1, name: "Leon")])
        guild.apply(notice: Guild.Notice(subject: "Hello", body: "World"))

        guild.apply(belonging: belonging(guildID: 8, name: "Other"))

        #expect(guild.guildID == 8)
        #expect(guild.members.isEmpty)
        #expect(guild.notice.isEmpty)
    }

    @Test func belongingToSameGuildKeepsData() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7))
        guild.apply(members: [member(characterID: 1, name: "Leon")])

        guild.apply(belonging: belonging(guildID: 7, emblemID: 5))

        #expect(guild.members.count == 1)
        #expect(guild.emblemID == 5)
    }

    @Test func infoFillsBasicFields() {
        var guild = Guild()

        guild.apply(info: info(guildID: 7, level: 4, exp: 250, nextExp: 1000, onlineCount: 2, maxMemberCount: 26))

        #expect(guild.isInGuild)
        #expect(guild.level == 4)
        #expect(guild.masterName == "Leon")
        #expect(guild.maxMemberCount == 26)
        #expect(guild.expFraction == 0.25)
        #expect(guild.onlineCount == 2)
        #expect(guild.memberCount == nil)
    }

    @Test func expFractionWithoutNextExpIsZero() {
        var guild = Guild()
        guild.apply(info: info(guildID: 7, exp: 10, nextExp: 0))

        #expect(guild.expFraction == 0)
    }

    @Test func infoKeepsMembersAndNotice() {
        var guild = Guild()
        guild.apply(info: info(guildID: 7))
        guild.apply(members: [member(characterID: 1, name: "Leon")])
        guild.apply(notice: Guild.Notice(subject: "Hello", body: "World"))

        guild.apply(info: info(guildID: 7, level: 5))

        #expect(guild.members.count == 1)
        #expect(guild.notice.subject == "Hello")
    }

    @Test func memberCountsComeFromMemberList() {
        var guild = Guild()
        guild.apply(info: info(guildID: 7, onlineCount: 5))

        guild.apply(members: [
            member(characterID: 1, name: "Leon", isOnline: true),
            member(characterID: 2, name: "Poring", isOnline: false),
            member(characterID: 3, name: "Drops", isOnline: true),
        ])

        #expect(guild.memberCount == 3)
        #expect(guild.onlineCount == 2)
    }

    @Test func setOnlineMatchesCharacterID() {
        var guild = Guild()
        guild.apply(members: [
            member(characterID: 1, accountID: 100, name: "Leon", isOnline: false),
            member(characterID: 2, accountID: 100, name: "Alt", isOnline: false),
        ])

        guild.setOnline(accountID: 100, characterID: 2, isOnline: true)

        #expect(guild.members[0].isOnline == false)
        #expect(guild.members[1].isOnline == true)

        guild.setOnline(accountID: 100, characterID: 2, isOnline: false)
        #expect(guild.members[1].isOnline == false)
    }

    @Test func setOnlineFallsBackToAccountIDWithoutCharacterID() {
        var guild = Guild()
        guild.apply(members: [member(characterID: 1, accountID: 100, name: "Leon", isOnline: false)])

        guild.setOnline(accountID: 100, characterID: 0, isOnline: true)

        #expect(guild.members[0].isOnline)
    }

    @Test func setOnlineForUnknownMemberIsIgnored() {
        var guild = Guild()
        guild.apply(members: [member(characterID: 1, name: "Leon", isOnline: false)])

        guild.setOnline(accountID: 99, characterID: 99, isOnline: true)

        #expect(guild.members[0].isOnline == false)
    }

    @Test func applyMembersReplacesList() {
        var guild = Guild()
        guild.apply(members: [member(characterID: 1, name: "Leon"), member(characterID: 2, name: "Poring")])

        guild.apply(members: [member(characterID: 3, name: "Drops")])

        #expect(guild.members.map(\.characterID) == [3])
    }

    @Test func removeMemberReturnsMember() {
        var guild = Guild()
        guild.apply(members: [member(characterID: 1, name: "Leon"), member(characterID: 2, name: "Poring")])

        let removed = guild.removeMember(characterID: 2)

        #expect(removed?.name == "Poring")
        #expect(guild.members.map(\.characterID) == [1])
        #expect(guild.expulsions.isEmpty)
        #expect(guild.removeMember(characterID: 99) == nil)
    }

    @Test func removeMemberWithReasonRecordsExpulsion() {
        var guild = Guild()
        guild.apply(members: [member(characterID: 1, name: "Leon"), member(characterID: 2, name: "Poring")])

        guild.removeMember(characterID: 2, expelledFor: "AFK")

        #expect(guild.expulsions == [Guild.Expulsion(characterID: 2, name: "Poring", reason: "AFK")])
    }

    @Test func positionNamesThenDetailsMerge() {
        var guild = Guild()

        guild.apply(positionNames: [(id: 0, name: "Guild Master"), (id: 1, name: "Member"), (id: 2, name: "")])
        guild.apply(positionDetails: [
            Guild.Position(id: 0, permissions: [.invite, .expel], ranking: 0, expRate: 0),
            Guild.Position(id: 1, permissions: [], ranking: 1, expRate: 10),
        ])

        #expect(guild.positions.map(\.id) == [0, 1, 2])
        #expect(guild.position(id: 0)?.name == "Guild Master")
        #expect(guild.position(id: 0)?.permissions == [.invite, .expel])
        #expect(guild.position(id: 1)?.expRate == 10)
        #expect(guild.positionName(id: 1) == "Member")
        #expect(guild.positionName(id: 2) == nil)
        #expect(guild.positionName(id: 9) == nil)
    }

    @Test func positionDetailsBeforeNamesCreatePositions() {
        var guild = Guild()

        guild.apply(positionDetails: [Guild.Position(id: 3, permissions: [.invite], ranking: 3, expRate: 5)])
        guild.apply(positionNames: [(id: 3, name: "Officer")])

        #expect(guild.positions.count == 1)
        #expect(guild.positions[0] == Guild.Position(id: 3, name: "Officer", permissions: [.invite], ranking: 3, expRate: 5))
    }

    @Test func changedPositionReplacesPosition() {
        var guild = Guild()
        guild.apply(positionNames: [(id: 1, name: "Member")])
        guild.apply(positionDetails: [Guild.Position(id: 1, permissions: [], ranking: 1, expRate: 0)])

        guild.apply(changedPositions: [
            Guild.Position(id: 1, name: "Veteran", permissions: [.invite], ranking: 1, expRate: 15),
        ])

        #expect(guild.positions.count == 1)
        #expect(guild.positions[0].name == "Veteran")
        #expect(guild.positions[0].permissions == [.invite])
        #expect(guild.positions[0].expRate == 15)
    }

    @Test func memberPositionsUpdateMembers() {
        var guild = Guild()
        guild.apply(members: [
            member(characterID: 1, name: "Leon", positionID: 0),
            member(characterID: 2, name: "Poring", positionID: 1),
        ])

        guild.apply(memberPositions: [(characterID: 2, positionID: 4), (characterID: 99, positionID: 2)])

        #expect(guild.members[1].positionID == 4)
        #expect(guild.members[0].positionID == 0)
    }

    @Test func refreshPermissionsFollowsOwnPosition() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7, permissions: []))
        guild.apply(members: [
            member(characterID: 1, name: "Leon", positionID: 0),
            member(characterID: 2, name: "Poring", positionID: 1),
        ])
        guild.apply(changedPositions: [
            Guild.Position(id: 1, name: "Officer", permissions: [.invite, .expel], ranking: 1, expRate: 0),
        ])

        guild.refreshPermissions(characterID: 2)

        #expect(guild.canInvite)
        #expect(guild.canExpel)

        guild.apply(changedPositions: [
            Guild.Position(id: 1, name: "Officer", permissions: [], ranking: 1, expRate: 0),
        ])
        guild.refreshPermissions(characterID: 2)

        #expect(guild.canInvite == false)
        #expect(guild.canExpel == false)
    }

    @Test func refreshPermissionsWithoutPositionDataKeepsPermissions() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7, permissions: [.invite]))

        guild.refreshPermissions(characterID: 2)

        #expect(guild.permissions == [.invite])
    }

    @Test func relationsSplitByKind() {
        var guild = Guild()

        guild.apply(relations: [
            Guild.Relation(kind: .alliance, guildID: 1, name: "Friends"),
            Guild.Relation(kind: .hostile, guildID: 2, name: "Foes"),
            Guild.Relation(kind: .alliance, guildID: 3, name: "Buddies"),
        ])

        #expect(guild.alliances.map(\.name) == ["Friends", "Buddies"])
        #expect(guild.hostileGuilds.map(\.name) == ["Foes"])
    }

    @Test func removeRelationMatchesGuildAndKind() {
        var guild = Guild()
        guild.apply(relations: [
            Guild.Relation(kind: .alliance, guildID: 1, name: "Friends"),
            Guild.Relation(kind: .hostile, guildID: 1, name: "Friends"),
        ])

        guild.removeRelation(guildID: 1, kind: .hostile)

        #expect(guild.relations.map(\.kind) == [.alliance])
    }

    @Test func relationKindFollowsServerValue() {
        // rAthena sends the alliance's `opposition` flag: 0 ally, 1 enemy.
        #expect(Guild.Relation.Kind(rawValue: 0) == .alliance)
        #expect(Guild.Relation.Kind(rawValue: 1) == .hostile)
        #expect(Guild.Relation.Kind(rawValue: 2) == nil)
    }

    @Test func noticeReplacesPreviousNotice() {
        var guild = Guild()

        guild.apply(notice: Guild.Notice(subject: "Old", body: "old text"))
        guild.apply(notice: Guild.Notice(subject: "New", body: "new text"))

        #expect(guild.notice == Guild.Notice(subject: "New", body: "new text"))
        #expect(guild.notice.isEmpty == false)
        #expect(Guild.Notice().isEmpty)
    }

    @Test func resetLeavesGuild() {
        var guild = Guild()
        guild.apply(belonging: belonging(guildID: 7, isMaster: true))
        guild.apply(info: info(guildID: 7))
        guild.apply(members: [member(characterID: 1, name: "Leon")])
        guild.apply(relations: [Guild.Relation(kind: .alliance, guildID: 1, name: "Friends")])

        guild.reset()

        #expect(guild == Guild())
        #expect(guild.isInGuild == false)
        #expect(guild.isMaster == false)
    }

    @Test func masterMemberHasPositionZero() {
        #expect(member(characterID: 1, name: "Leon", positionID: 0).isMaster)
        #expect(member(characterID: 2, name: "Poring", positionID: 1).isMaster == false)
    }

    // MARK: - Helpers

    private func belonging(
        guildID: UInt32,
        name: String = "Poring Hunters",
        emblemID: Int = 0,
        permissions: Guild.Permissions = [],
        isMaster: Bool = false
    ) -> Guild.Belonging {
        Guild.Belonging(
            guildID: guildID,
            name: name,
            emblemID: emblemID,
            permissions: permissions,
            isMaster: isMaster
        )
    }

    private func info(
        guildID: UInt32,
        level: Int = 1,
        exp: Int = 0,
        nextExp: Int = 100,
        onlineCount: Int = 1,
        maxMemberCount: Int = 16
    ) -> Guild.Info {
        Guild.Info(
            guildID: guildID,
            name: "Poring Hunters",
            level: level,
            onlineCount: onlineCount,
            maxMemberCount: maxMemberCount,
            averageLevel: 50,
            exp: exp,
            nextExp: nextExp,
            emblemID: 0,
            masterCharacterID: 1,
            masterName: "Leon",
            castleName: ""
        )
    }

    private func member(
        characterID: UInt32,
        accountID: UInt32? = nil,
        name: String,
        positionID: Int = 1,
        isOnline: Bool = true
    ) -> Guild.Member {
        Guild.Member(
            accountID: accountID ?? characterID + 1000,
            characterID: characterID,
            name: name,
            job: 0,
            baseLevel: 10,
            contribution: 0,
            positionID: positionID,
            isOnline: isOnline,
            lastLogin: nil
        )
    }
}
