//
//  Party.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

struct Party: Equatable, Sendable {
    struct Member: Identifiable, Equatable, Sendable {
        var accountID: UInt32
        var characterID: UInt32
        var name: String
        var mapName: String
        var job: Int
        var baseLevel: Int
        var hp: Int
        var maxHP: Int
        var position: SIMD2<Int>?
        var isLeader: Bool
        var isOnline: Bool
        var isDead: Bool

        var id: UInt32 {
            accountID
        }

        var hpFraction: Double {
            guard maxHP > 0 else {
                return 0
            }
            return min(max(Double(hp) / Double(maxHP), 0), 1)
        }
    }

    var name = ""
    private(set) var members: [Member] = []
    var sharePickup = false
    var shareLoot = false

    var isInParty: Bool {
        !name.isEmpty || !members.isEmpty
    }

    var leader: Member? {
        members.first(where: \.isLeader)
    }

    init() {
    }

    init(name: String, memberList: [Member] = []) {
        self.name = name
        self.members = memberList
    }

    mutating func apply(name: String, memberList: [Member]) {
        self.name = name
        self.members = memberList
    }

    mutating func apply(memberList: [Member]) {
        members = memberList
    }

    mutating func addMember(_ member: Member) {
        if member.isLeader {
            clearLeader()
        }

        if let index = members.firstIndex(where: { $0.accountID == member.accountID }) {
            members[index] = member
        } else {
            members.append(member)
        }
    }

    mutating func removeMember(accountID: UInt32) {
        members.removeAll(where: { $0.accountID == accountID })
        if members.isEmpty {
            name = ""
        }
    }

    mutating func updateHP(accountID: UInt32, hp: Int, maxHP: Int) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        members[index].hp = hp
        members[index].maxHP = maxHP
        members[index].isDead = hp <= 0
    }

    mutating func updatePosition(accountID: UInt32, position: SIMD2<Int>) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        members[index].position = position
    }

    mutating func updateMemberInfo(accountID: UInt32, job: Int, baseLevel: Int) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        members[index].job = job
        members[index].baseLevel = baseLevel
    }

    mutating func setOnline(accountID: UInt32, isOnline: Bool) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        members[index].isOnline = isOnline
    }

    mutating func setDead(accountID: UInt32, isDead: Bool) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        members[index].isDead = isDead
    }

    mutating func setLeader(accountID: UInt32) {
        guard let index = index(ofMemberWithAccountID: accountID) else {
            return
        }

        for memberIndex in members.indices {
            members[memberIndex].isLeader = memberIndex == index
        }
    }

    mutating func reset() {
        name = ""
        members = []
        sharePickup = false
        shareLoot = false
    }

    private mutating func clearLeader() {
        for index in members.indices {
            members[index].isLeader = false
        }
    }

    private func index(ofMemberWithAccountID accountID: UInt32) -> Int? {
        members.firstIndex(where: { $0.accountID == accountID })
    }
}

struct PartyInvitation: Identifiable, Equatable, Sendable {
    var partyID: Int32
    var partyName: String

    var id: Int32 {
        partyID
    }
}
