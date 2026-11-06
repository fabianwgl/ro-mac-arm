import Foundation
import Testing
@testable import RagnarokGame

struct PartyTests {
    @Test func applyMemberListReplacesState() {
        var party = Party()
        party.apply(name: "Poring Hunters", memberList: [
            member(accountID: 1, name: "Leon", isLeader: true),
            member(accountID: 2, name: "Poring")
        ])

        party.apply(name: "Prontera Guards", memberList: [
            member(accountID: 3, name: "Guard")
        ])

        #expect(party.name == "Prontera Guards")
        #expect(party.members.map(\.accountID) == [3])
        #expect(party.leader == nil)
    }

    @Test func addAndRemoveMember() {
        var party = Party(name: "Poring Hunters")

        party.addMember(member(accountID: 1, name: "Leon", isLeader: true))
        party.addMember(member(accountID: 2, name: "Poring"))
        #expect(party.members.map(\.accountID) == [1, 2])

        party.addMember(member(accountID: 2, name: "Poring", isOnline: false))
        #expect(party.members.count == 2)
        #expect(party.members[1].isOnline == false)

        party.removeMember(accountID: 2)
        #expect(party.members.map(\.accountID) == [1])

        party.removeMember(accountID: 1)
        #expect(party.members.isEmpty)
        #expect(party.isInParty == false)
    }

    @Test func setLeaderChangesLeader() {
        var party = Party(name: "Poring Hunters", memberList: [
            member(accountID: 1, name: "Leon", isLeader: true),
            member(accountID: 2, name: "Poring")
        ])

        party.setLeader(accountID: 2)

        #expect(party.members[0].isLeader == false)
        #expect(party.members[1].isLeader == true)
        #expect(party.leader?.accountID == 2)

        party.setLeader(accountID: 99)
        #expect(party.leader?.accountID == 2)
    }

    @Test func hpAndPositionUpdatesForUnknownMemberAreIgnored() {
        var party = Party(name: "Poring Hunters", memberList: [
            member(accountID: 1, name: "Leon", hp: 100, maxHP: 200)
        ])

        party.updateHP(accountID: 99, hp: 1, maxHP: 2)
        party.updatePosition(accountID: 99, position: SIMD2(10, 20))

        #expect(party.members[0].hp == 100)
        #expect(party.members[0].maxHP == 200)
        #expect(party.members[0].position == nil)
    }

    @Test func hpAndPositionUpdatesChangeMember() {
        var party = Party(name: "Poring Hunters", memberList: [
            member(accountID: 1, name: "Leon", hp: 100, maxHP: 200)
        ])

        party.updateHP(accountID: 1, hp: 50, maxHP: 200)
        party.updatePosition(accountID: 1, position: SIMD2(10, 20))

        #expect(party.members[0].hp == 50)
        #expect(party.members[0].hpFraction == 0.25)
        #expect(party.members[0].position == SIMD2(10, 20))
    }

    private func member(
        accountID: UInt32,
        name: String,
        hp: Int = 0,
        maxHP: Int = 0,
        isLeader: Bool = false,
        isOnline: Bool = true
    ) -> Party.Member {
        Party.Member(
            accountID: accountID,
            characterID: accountID,
            name: name,
            mapName: "prontera.gat",
            job: 0,
            baseLevel: 0,
            hp: hp,
            maxHP: maxHP,
            position: nil,
            isLeader: isLeader,
            isOnline: isOnline,
            isDead: false
        )
    }
}
