//
//  ChatRoomView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

/// The window of the chat room the player is in: members with the owner marked, the lines said in the room, and a line
/// to say something. The owner also gets the settings, and expel and give-the-room buttons per member.
///
/// What is typed here is the ordinary chat request, which rAthena sends to the room alone while the sender is in one.
/// The chat box does the same for anything typed there.
struct ChatRoomView: View {
    var room: ChatRoom

    @Environment(PlaySession.self) private var playSession

    @State private var line = ""
    @State private var selectedMember: String?

    @FocusState private var isLineFocused: Bool

    var body: some View {
        GameWindow {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text(verbatim: "\(room.members.count) / \(room.limit)")
                    Text(verbatim: room.access == .privateRoom ? "Private" : "Public")
                        .foregroundStyle(Color.gameLabel.opacity(0.6))
                    Spacer()
                }
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)

                memberList
                    .frame(height: 82)

                Rectangle()
                    .fill(Color.gameBoxBorder)
                    .frame(height: 1)

                lineList
                    .frame(height: 118)

                Rectangle()
                    .fill(Color.gameBoxBorder)
                    .frame(height: 1)

                TextField(String(), text: $line, prompt: Text(verbatim: "Say something to the room"))
                    .textFieldStyle(.plain)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .disableAutocorrection(true)
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .focused($isLineFocused)
                    .onSubmit {
                        playSession.sayInChatRoom(line)
                        line = ""
                        isLineFocused = true
                    }
            }
        } bottomBar: {
            GameBottomBar {
                if room.isOwner {
                    Button {
                        playSession.openChatRoomSettings()
                    } label: {
                        Text(verbatim: "Settings")
                    }
                    .buttonStyle(.game)
                    .frame(width: 62, height: 20)

                    Button {
                        if let selectedMember {
                            playSession.giveChatRoom(to: selectedMember)
                        }
                    } label: {
                        Text(verbatim: "Owner")
                    }
                    .buttonStyle(.game)
                    .frame(width: 50, height: 20)
                    .disabled(selectedOtherMember == nil)

                    Button {
                        if let selectedMember {
                            playSession.expelFromChatRoom(name: selectedMember)
                        }
                    } label: {
                        Text(verbatim: "Expel")
                    }
                    .buttonStyle(.game)
                    .frame(width: 50, height: 20)
                    .disabled(selectedOtherMember == nil)
                }

                Spacer()

                Button {
                    playSession.leaveChatRoom()
                } label: {
                    Text(verbatim: "Leave")
                }
                .buttonStyle(.game)
                .frame(width: 50, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: room.title.isEmpty ? "Chat Room" : room.title))
        .gameWindowCloseAction {
            // The window closes, the player stays in the room until he leaves.
            playSession.closeChatRoomWindow()
        }
        .frame(width: 300)
    }

    /// The member that the owner's buttons act on.
    private var selectedOtherMember: ChatRoomMember? {
        room.otherMembers.first(where: { $0.name == selectedMember })
    }

    private var memberList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(room.members) { member in
                    HStack(spacing: 5) {
                        Image(systemName: member.isOwner ? "crown.fill" : "person.fill")
                            .font(.game(size: 10))
                            .foregroundStyle(member.isOwner ? Color.orange : Color.gameLabel.opacity(0.6))
                            .frame(width: 14)

                        Text(verbatim: member.name)
                            .font(.game())
                            .foregroundStyle(Color.gameLabel)
                            .fontWeight(member.name == room.selfName ? .bold : .regular)

                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(member.name == selectedMember ? Color(#colorLiteral(red: 0.8039215686, green: 0.8784313725, blue: 1, alpha: 1)) : .clear)
                    .contentShape(.rect)
                    .onTapGesture {
                        if room.isOwner && member.name != room.selfName {
                            selectedMember = member.name
                        }
                    }
                }
            }
        }
    }

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(room.lines) { line in
                        lineText(line)
                            .font(.game())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .onChange(of: room.lines.last?.id, initial: true) {
                if let id = room.lines.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func lineText(_ line: ChatRoomLine) -> Text {
        switch line.kind {
        case .said(let sender):
            Text(verbatim: "\(sender) : \(line.text)")
                .foregroundStyle(Color.gameLabel)
        case .notice:
            Text(verbatim: line.text)
                .foregroundStyle(Color.gameLabel.opacity(0.55))
        }
    }
}

#Preview {
    let playSession = PlaySession.testing

    var settings = ChatRoomSettings(title: "Prontera meetup", limit: 10)
    settings.isPublic = true
    var room = ChatRoom(created: settings, ownerID: 2_000_001, selfName: "Leon")
    room.memberJoined(name: "Poring")
    room.appendSaid(sender: "Leon", text: "Hello")
    room.appendSaid(sender: "Poring", text: "Hi")

    return ChatRoomView(room: room)
        .padding()
        .environment(GameContext.testing)
        .environment(playSession)
}
