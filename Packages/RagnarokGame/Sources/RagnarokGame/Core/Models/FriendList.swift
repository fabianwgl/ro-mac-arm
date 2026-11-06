//
//  FriendList.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

struct FriendList: Equatable, Sendable {
    struct Friend: Identifiable, Equatable, Sendable {
        var accountID: UInt32
        var characterID: UInt32
        var name: String
        var isOnline: Bool

        var id: UInt32 {
            accountID
        }
    }

    private(set) var friends: [Friend] = []

    init() {
    }

    init(friends: [Friend]) {
        self.friends = friends
    }

    /// Replaces the list while keeping the online state already known for each friend.
    mutating func apply(list: [Friend]) {
        let onlineStates = Dictionary(friends.map { ($0.accountID, $0.isOnline) }, uniquingKeysWith: { first, _ in first })
        friends = list.map { friend in
            var friend = friend
            friend.isOnline = onlineStates[friend.accountID] ?? friend.isOnline
            return friend
        }
    }

    mutating func setOnline(accountID: UInt32, isOnline: Bool) {
        guard let index = friends.firstIndex(where: { $0.accountID == accountID }) else {
            return
        }

        friends[index].isOnline = isOnline
    }

    mutating func add(_ friend: Friend) {
        if let index = friends.firstIndex(where: { $0.accountID == friend.accountID }) {
            friends[index] = friend
        } else {
            friends.append(friend)
        }
    }

    mutating func remove(accountID: UInt32) {
        friends.removeAll(where: { $0.accountID == accountID })
    }
}

struct FriendInvitation: Identifiable, Equatable, Sendable {
    var accountID: UInt32
    var characterID: UInt32
    var name: String

    var id: UInt32 {
        accountID
    }
}
