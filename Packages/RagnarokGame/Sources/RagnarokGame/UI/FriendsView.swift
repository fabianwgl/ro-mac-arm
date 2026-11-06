//
//  FriendsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct FriendsView: View {
    var friendList: FriendList
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession

    @State private var friendName = ""

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 5) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if friendList.friends.isEmpty {
                            Text(verbatim: "No friends.")
                                .font(.game(size: 11))
                                .foregroundStyle(Color.gameProminentLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }

                        ForEach(friendList.friends) { friend in
                            FriendRow(friend: friend)
                        }
                    }
                }
                .frame(height: 200)
                .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))

                HStack(spacing: 5) {
                    TextField("Character name", text: $friendName)
                        .textFieldStyle(.plain)
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)
                        .padding(.horizontal, 3)
                        .frame(height: 18)
                        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1)))

                    Button {
                        playSession.addFriend(name: friendName)
                    } label: {
                        Text(verbatim: "Add")
                    }
                    .buttonStyle(.game)
                    .frame(width: 42, height: 20)
                }
            }
            .padding(5)
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "\(friendList.friends.count) friends")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
            }
        }
        .gameWindowTitle(Text(verbatim: "Friends"))
        .gameWindowCloseAction(onClose)
        .frame(width: 320)
    }
}

private struct FriendRow: View {
    var friend: FriendList.Friend

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(friend.isOnline ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            Text(verbatim: friend.name)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                playSession.removeFriend(accountID: friend.accountID)
            } label: {
                Text(verbatim: "Remove")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 18)
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }
}

#Preview {
    let friendList = FriendList(friends: [
        FriendList.Friend(
            accountID: 1,
            characterID: 1,
            name: "Leon",
            isOnline: true
        ),
        FriendList.Friend(
            accountID: 2,
            characterID: 2,
            name: "Poring",
            isOnline: false
        )
    ])

    FriendsView(friendList: friendList)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
