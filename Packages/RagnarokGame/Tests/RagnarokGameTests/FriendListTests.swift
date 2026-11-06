import Testing
@testable import RagnarokGame

struct FriendListTests {
    @Test func setOnlineTogglesFriend() {
        var friendList = FriendList(friends: [
            friend(accountID: 1, name: "Leon", isOnline: false)
        ])

        friendList.setOnline(accountID: 1, isOnline: true)
        #expect(friendList.friends[0].isOnline == true)

        friendList.setOnline(accountID: 1, isOnline: false)
        #expect(friendList.friends[0].isOnline == false)

        friendList.setOnline(accountID: 99, isOnline: true)
        #expect(friendList.friends.count == 1)
    }

    @Test func addDuplicateFriendReplaces() {
        var friendList = FriendList()
        friendList.add(friend(accountID: 1, name: "Leon", isOnline: false))
        friendList.add(friend(accountID: 1, name: "Leon", isOnline: true))

        #expect(friendList.friends.count == 1)
        #expect(friendList.friends[0].isOnline == true)

        friendList.add(friend(accountID: 2, name: "Poring", isOnline: false))
        #expect(friendList.friends.map(\.accountID) == [1, 2])
    }

    @Test func removeFriend() {
        var friendList = FriendList(friends: [
            friend(accountID: 1, name: "Leon", isOnline: true),
            friend(accountID: 2, name: "Poring", isOnline: false)
        ])

        friendList.remove(accountID: 1)
        #expect(friendList.friends.map(\.accountID) == [2])

        friendList.remove(accountID: 99)
        #expect(friendList.friends.map(\.accountID) == [2])
    }

    @Test func applyListReplacesFriendsAndKeepsOnlineState() {
        var friendList = FriendList(friends: [
            friend(accountID: 1, name: "Leon", isOnline: true),
            friend(accountID: 2, name: "Poring", isOnline: false)
        ])

        friendList.apply(list: [
            friend(accountID: 1, name: "Leon", isOnline: false),
            friend(accountID: 3, name: "Fabre", isOnline: false)
        ])

        #expect(friendList.friends.map(\.accountID) == [1, 3])
        #expect(friendList.friends[0].isOnline == true)
        #expect(friendList.friends[1].isOnline == false)
    }

    private func friend(accountID: UInt32, name: String, isOnline: Bool) -> FriendList.Friend {
        FriendList.Friend(
            accountID: accountID,
            characterID: accountID,
            name: name,
            isOnline: isOnline
        )
    }
}
