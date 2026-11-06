//
//  PartyView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokConstants
import SwiftUI

struct PartyView: View {
    var party: Party
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    @State private var partyName = ""
    @State private var inviteName = ""

    private var isLeader: Bool {
        party.members.first(where: { $0.accountID == playSession.account.accountID })?.isLeader == true
    }

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 5) {
                if party.isInParty {
                    partyHeader
                    memberList
                    inviteForm
                } else {
                    createForm
                }
            }
            .padding(5)
        } bottomBar: {
            GameBottomBar {
                if party.isInParty {
                    Button {
                        playSession.leaveParty()
                        onClose()
                    } label: {
                        Text("Leave")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }
            }
        }
        .gameWindowTitle(Text(verbatim: "Party"))
        .gameWindowCloseAction(onClose)
        .frame(width: 360)
    }

    private var partyHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: party.name.isEmpty ? "Party" : party.name)
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            HStack(spacing: 10) {
                Text(verbatim: "Item pickup: \(party.sharePickup ? "Shared" : "Each take")")
                Text(verbatim: "Item drop: \(party.shareLoot ? "Shared" : "Each take")")
            }
            .font(.game(size: 11))
            .foregroundStyle(Color.gameProminentLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
    }

    private var memberList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(party.members) { member in
                    PartyMemberRow(
                        member: member,
                        isLeader: isLeader && member.accountID != playSession.account.accountID
                    )
                }
            }
        }
        .frame(height: 180)
        .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))
    }

    private var createForm: some View {
        HStack(spacing: 5) {
            TextField("Party name", text: $partyName)
                .textFieldStyle(.plain)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 3)
                .frame(height: 18)
                .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1)))

            Button {
                playSession.createParty(name: partyName)
            } label: {
                Text(verbatim: "Create")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
        }
    }

    private var inviteForm: some View {
        HStack(spacing: 5) {
            TextField("Character name", text: $inviteName)
                .textFieldStyle(.plain)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 3)
                .frame(height: 18)
                .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1)))

            Button {
                playSession.inviteToParty(name: inviteName)
            } label: {
                Text(verbatim: "Invite")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
        }
    }
}

private struct PartyMemberRow: View {
    var member: Party.Member
    var isLeader: Bool

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(member.isOnline ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text(verbatim: member.name)
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)

                if member.isLeader {
                    Text(verbatim: "Leader")
                        .font(.game(size: 10))
                        .foregroundStyle(Color.gameProminentLabel)
                }

                Spacer(minLength: 0)

                if isLeader {
                    Button {
                        playSession.changePartyLeader(accountID: member.accountID)
                    } label: {
                        Text(verbatim: "Make leader")
                    }
                    .buttonStyle(.game)
                    .frame(width: 74, height: 18)

                    Button {
                        playSession.expelPartyMember(accountID: member.accountID, name: member.name)
                    } label: {
                        Text(verbatim: "Kick")
                    }
                    .buttonStyle(.game)
                    .frame(width: 38, height: 18)
                }
            }

            HStack(spacing: 6) {
                Text(verbatim: infoText)
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .lineLimit(1)

                if member.maxHP > 0 {
                    PartyHPBar(fraction: member.hpFraction, isDead: member.isDead)
                        .frame(width: 70, height: 4)
                }
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }

    private var infoText: String {
        var parts: [String] = []

        if !member.mapName.isEmpty {
            let mapName = member.mapName.split(separator: ".", maxSplits: 1).first.map(String.init) ?? member.mapName
            parts.append(gameContext.mapInfoTable.localizedMapName(forMapName: mapName) ?? mapName)
        }

        if member.baseLevel > 0 {
            parts.append("Lv \(member.baseLevel)")
        }

        if member.job > 0, let jobID = JobID(rawValue: member.job), let name = jobID.localizedName {
            parts.append(String(localized: name))
        }

        if !member.isOnline {
            parts.append("Offline")
        }

        return parts.joined(separator: " | ")
    }
}

private struct PartyHPBar: View {
    var fraction: Double
    var isDead: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.15))

                Rectangle()
                    .fill(isDead ? Color.red : Color.green)
                    .frame(width: geometry.size.width * fraction)
            }
        }
    }
}

#Preview {
    let party = Party(name: "Poring Hunters", memberList: [
        Party.Member(
            accountID: 1,
            characterID: 1,
            name: "Leon",
            mapName: "prontera.gat",
            job: JobID.knight.rawValue,
            baseLevel: 50,
            hp: 1200,
            maxHP: 1500,
            position: nil,
            isLeader: true,
            isOnline: true,
            isDead: false
        ),
        Party.Member(
            accountID: 2,
            characterID: 2,
            name: "Poring",
            mapName: "prontera.gat",
            job: JobID.acolyte.rawValue,
            baseLevel: 40,
            hp: 300,
            maxHP: 600,
            position: nil,
            isLeader: false,
            isOnline: false,
            isDead: false
        )
    ])

    PartyView(party: party)
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
