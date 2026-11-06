//
//  SocialInvitationView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct SocialInvitationView: View {
    var invitation: SocialInvitation

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        MessageBoxView(message) {
            Button {
                accept()
            } label: {
                Text(verbatim: "Accept")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)

            Button {
                decline()
            } label: {
                Text(verbatim: "Decline")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
        }
        .gameWindowTitle(title)
    }

    private var title: Text {
        switch invitation {
        case .party:
            Text(verbatim: "Party Invitation")
        case .friend:
            Text(verbatim: "Friend Request")
        }
    }

    private var message: String {
        switch invitation {
        case .party(let invitation):
            "\(invitation.partyName) invites you to join the party."
        case .friend(let invitation):
            "\(invitation.name) wants to be your friend."
        }
    }

    private func accept() {
        switch invitation {
        case .party:
            playSession.answerPartyInvitation(accept: true)
        case .friend:
            playSession.answerFriendInvitation(accept: true)
        }
    }

    private func decline() {
        switch invitation {
        case .party:
            playSession.answerPartyInvitation(accept: false)
        case .friend:
            playSession.answerFriendInvitation(accept: false)
        }
    }
}

#Preview {
    SocialInvitationView(invitation: .party(PartyInvitation(partyID: 1, partyName: "Poring Hunters")))
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
