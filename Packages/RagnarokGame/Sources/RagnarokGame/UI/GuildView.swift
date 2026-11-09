//
//  GuildView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokConstants
import RagnarokResources
import SwiftUI

private enum GuildTab: CaseIterable {
    case info
    case members
    case positions
    case skills
    case notice
}

/// A question the guild window asks before it sends a request that cannot be undone.
private enum GuildPrompt: Equatable {
    case leave
    case expel(Guild.Member)
    case disband
}

struct GuildView: View {
    var guild: Guild
    var onClose: () -> Void = {}

    @Environment(PlaySession.self) private var playSession

    @State private var tab: GuildTab = .info
    @State private var prompt: GuildPrompt?

    var body: some View {
        GameWindow {
            if guild.isInGuild {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        GameVerticalTabBar(tabs: GuildTab.allCases, selection: $tab) { tab in
                            switch tab {
                            case .info:
                                Text(verbatim: "Info")
                            case .members:
                                Text(verbatim: "Members")
                            case .positions:
                                Text(verbatim: "Positions")
                            case .skills:
                                Text(verbatim: "Skills")
                            case .notice:
                                Text(verbatim: "Notice")
                            }
                        }

                        tabContent
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(height: 260)
                    }

                    if let prompt {
                        GuildPromptView(prompt: prompt, guildName: guild.name) {
                            self.prompt = nil
                        }
                    }
                }
            } else {
                GuildCreateForm()
            }
        } bottomBar: {
            GameBottomBar {
                if guild.isInGuild {
                    Text(verbatim: "\(guild.onlineCount) online")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    Spacer()

                    Button {
                        prompt = guild.isMaster ? .disband : .leave
                    } label: {
                        Text(verbatim: guild.isMaster ? "Disband" : "Leave")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }
            }
        }
        .gameWindowTitle(Text(verbatim: "Guild"))
        .gameWindowCloseAction(onClose)
        .frame(width: 380)
        .onAppear {
            playSession.refreshGuild()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .info:
            GuildInfoTab(guild: guild)
        case .members:
            GuildMembersTab(guild: guild) { member in
                prompt = .expel(member)
            }
        case .positions:
            GuildPositionsTab(guild: guild)
        case .skills:
            GuildSkillsTab(guild: guild)
        case .notice:
            GuildNoticeTab(guild: guild)
        }
    }
}

// MARK: - Create

private struct GuildCreateForm: View {
    @Environment(PlaySession.self) private var playSession

    @State private var guildName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "You are not in a guild.")
                .font(.game())
                .foregroundStyle(Color.gameLabel)

            Text(verbatim: "Creating a guild takes one Emperium from your inventory.")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)

            HStack(spacing: 5) {
                TextField("Guild name", text: $guildName)
                    .guildField()
                    .onChange(of: guildName) { _, newValue in
                        guildName = clampedToBytes(newValue, limit: 23)
                    }
                    .onSubmit {
                        playSession.createGuild(name: guildName)
                    }

                Button {
                    playSession.createGuild(name: guildName)
                } label: {
                    Text(verbatim: "Create")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Info

private struct GuildInfoTab: View {
    var guild: Guild

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: guild.name)
                    .font(.game(size: 13))
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)

                GuildInfoRow(label: "Level", value: "\(guild.level)")

                VStack(alignment: .leading, spacing: 2) {
                    GuildInfoRow(label: "Experience", value: "\(guild.exp) / \(guild.nextExp)")
                    GuildExpBar(fraction: guild.expFraction)
                        .frame(height: 5)
                }

                GuildInfoRow(label: "Members", value: membersText)
                GuildInfoRow(label: "Average level", value: "\(guild.averageLevel)")
                GuildInfoRow(label: "Master", value: guild.masterName.isEmpty ? "-" : guild.masterName)
                GuildInfoRow(label: "Emblem ID", value: "\(guild.emblemID)")
                GuildInfoRow(label: "Castles", value: guild.castleName.isEmpty ? "-" : guild.castleName)

                GuildRelationSection(title: "Alliances", relations: guild.alliances)
                GuildRelationSection(title: "Hostile guilds", relations: guild.hostileGuilds)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var membersText: String {
        var text = "\(guild.onlineCount) online"
        if let memberCount = guild.memberCount {
            text += " / \(memberCount)"
        }
        if guild.maxMemberCount > 0 {
            text += " (max \(guild.maxMemberCount))"
        }
        return text
    }
}

private struct GuildInfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: label)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
                .frame(width: 84, alignment: .leading)

            Text(verbatim: value)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

private struct GuildExpBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.15))

                Rectangle()
                    .fill(Color(#colorLiteral(red: 0.2588235294, green: 0.3882352941, blue: 0.6470588235, alpha: 1)))
                    .frame(width: geometry.size.width * fraction)
            }
        }
    }
}

private struct GuildRelationSection: View {
    var title: String
    var relations: [Guild.Relation]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)

            if relations.isEmpty {
                Text(verbatim: "None")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
            }

            ForEach(relations) { relation in
                Text(verbatim: relation.name)
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Members

private struct GuildMembersTab: View {
    var guild: Guild
    var onExpel: (Guild.Member) -> Void

    @Environment(PlaySession.self) private var playSession

    @State private var inviteName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if guild.members.isEmpty {
                        Text(verbatim: "No member list yet.")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(guild.members) { member in
                        GuildMemberRow(
                            member: member,
                            positionName: guild.positionName(id: member.positionID),
                            canExpel: guild.canExpel && !member.isMaster && member.characterID != playSession.character.charID,
                            onExpel: onExpel
                        )
                    }

                    if !guild.expulsions.isEmpty {
                        Text(verbatim: "Expelled")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 15)
                            .padding(.top, 8)

                        ForEach(guild.expulsions) { expulsion in
                            Text(verbatim: expulsion.reason.isEmpty ? expulsion.name : "\(expulsion.name): \(expulsion.reason)")
                                .font(.game(size: 11))
                                .foregroundStyle(Color.gameLabel)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 15)
                        }
                    }
                }
            }
            .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))

            if guild.canInvite {
                HStack(spacing: 5) {
                    TextField("Character name", text: $inviteName)
                        .guildField()
                        .onSubmit {
                            invite()
                        }

                    Button {
                        invite()
                    } label: {
                        Text(verbatim: "Invite")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 5)
            }
        }
    }

    private func invite() {
        playSession.inviteToGuild(name: inviteName)
        inviteName = ""
    }
}

private struct GuildMemberRow: View {
    var member: Guild.Member
    var positionName: String?
    var canExpel: Bool
    var onExpel: (Guild.Member) -> Void

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

                if let positionName {
                    Text(verbatim: positionName)
                        .font(.game(size: 10))
                        .foregroundStyle(member.isMaster ? Color.gameProminentLabel : Color.gameLabel.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if canExpel {
                    Button {
                        onExpel(member)
                    } label: {
                        Text(verbatim: "Expel")
                    }
                    .buttonStyle(.game)
                    .frame(width: 46, height: 18)
                }
            }

            Text(verbatim: infoText)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)
                .lineLimit(1)
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }

    private var infoText: String {
        var parts: [String] = []

        if member.baseLevel > 0 {
            parts.append("Lv \(member.baseLevel)")
        }

        if member.job >= 0, let jobID = JobID(rawValue: member.job), let name = jobID.localizedName {
            parts.append(String(localized: name))
        }

        parts.append("Exp \(member.contribution)")

        if !member.isOnline, let lastLogin = member.lastLogin {
            parts.append("Seen \(lastLogin.formatted(date: .abbreviated, time: .omitted))")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Positions

private struct GuildPositionsTab: View {
    var guild: Guild

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if namedPositions.isEmpty {
                    Text(verbatim: "No position list yet.")
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameProminentLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }

                ForEach(namedPositions) { position in
                    HStack(spacing: 6) {
                        Text(verbatim: "\(position.id + 1)")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(width: 18, alignment: .trailing)

                        Text(verbatim: position.name)
                            .font(.game())
                            .foregroundStyle(Color.gameLabel)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(verbatim: details(of: position))
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .lineLimit(1)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var namedPositions: [Guild.Position] {
        guild.positions.filter { !$0.name.isEmpty }
    }

    private func details(of position: Guild.Position) -> String {
        var parts: [String] = []
        if position.permissions.contains(.invite) {
            parts.append("Invite")
        }
        if position.permissions.contains(.expel) {
            parts.append("Expel")
        }
        parts.append("Tax \(position.expRate)%")
        return parts.joined(separator: " | ")
    }
}

// MARK: - Skills

private struct GuildSkillsTab: View {
    var guild: Guild

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: "Skill points")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)

                Text(verbatim: "\(guild.skillPoints)")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if guild.skills.isEmpty {
                        Text(verbatim: "No skill list yet.")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.gameProminentLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(guild.skills) { skill in
                        GuildSkillRow(skill: skill, canUpgrade: guild.canUpgrade(skill), canUse: guild.isMaster)
                    }
                }
            }
            .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))
        }
    }
}

private struct GuildSkillRow: View {
    var skill: Guild.Skill
    var canUpgrade: Bool
    var canUse: Bool

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    @State private var iconImage: Resources.Image?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if let iconImage {
                    Image(decorative: iconImage.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.none)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: playSession.guildSkillName(skill))
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)

                Text(verbatim: detail)
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .lineLimit(1)
            }
            .opacity(skill.level == 0 ? 0.5 : 1)

            Spacer(minLength: 0)

            if canUse && skill.isUsable {
                Button {
                    playSession.useGuildSkill(skill)
                } label: {
                    Text(verbatim: "Use")
                }
                .buttonStyle(.game)
                .frame(width: 40, height: 18)
            }

            if canUpgrade {
                Button {
                    playSession.upgradeGuildSkill(skill)
                } label: {
                    Text(verbatim: "Lv Up")
                }
                .buttonStyle(.game)
                .frame(width: 46, height: 18)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .task(id: skill.name) {
            let path = ResourcePath.generateSkillIconImagePath(skillAegisName: skill.name)
            iconImage = try? await gameContext.resourceManager.image(at: path, removesMagentaPixels: true)
        }
    }

    private var detail: String {
        var parts = ["Lv \(skill.level)"]
        if skill.isPassive {
            parts.append("Passive")
        } else if skill.level > 0 {
            parts.append("SP \(skill.spCost)")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Notice

private struct GuildNoticeTab: View {
    var guild: Guild

    @Environment(PlaySession.self) private var playSession

    @State private var subject = ""
    @State private var notice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if guild.canEditNotice {
                TextField("Subject", text: $subject)
                    .guildField()
                    .onChange(of: subject) { _, newValue in
                        subject = clampedToBytes(newValue, limit: 59)
                    }

                TextField("Notice", text: $notice, axis: .vertical)
                    .lineLimit(4...6)
                    .guildField()
                    .onChange(of: notice) { _, newValue in
                        notice = clampedToBytes(newValue, limit: 119)
                    }

                HStack {
                    Spacer()

                    Button {
                        playSession.changeGuildNotice(subject: subject, notice: notice)
                    } label: {
                        Text(verbatim: "Save")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }

                Spacer(minLength: 0)
            } else if guild.notice.isEmpty {
                Text(verbatim: "No notice.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            } else {
                Text(verbatim: guild.notice.subject)
                    .font(.game(size: 13))
                    .foregroundStyle(Color.gameLabel)

                Text(verbatim: guild.notice.body)
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .onAppear {
            loadDraft()
        }
        .onChange(of: guild.notice) {
            loadDraft()
        }
    }

    private func loadDraft() {
        subject = guild.notice.subject
        notice = guild.notice.body
    }
}

// MARK: - Prompt

private struct GuildPromptView: View {
    var prompt: GuildPrompt
    var guildName: String
    var onDone: () -> Void

    @Environment(PlaySession.self) private var playSession

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: question)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameProminentLabel)

            HStack(spacing: 5) {
                TextField(placeholder, text: $text)
                    .guildField()
                    .onChange(of: text) { _, newValue in
                        text = clampedToBytes(newValue, limit: isDisband ? 23 : 39)
                    }

                Button {
                    confirm()
                    onDone()
                } label: {
                    Text(verbatim: "OK")
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(isDisband && text != guildName)

                Button {
                    onDone()
                } label: {
                    Text(verbatim: "Cancel")
                }
                .buttonStyle(.game)
                .frame(width: 58, height: 20)
            }
        }
        .padding(5)
        .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
    }

    private var isDisband: Bool {
        prompt == .disband
    }

    private var question: String {
        switch prompt {
        case .leave:
            "Leave the guild? You can give a reason."
        case .expel(let member):
            "Expel \(member.name)? You can give a reason."
        case .disband:
            "Disbanding needs an empty guild. Type the guild name to confirm."
        }
    }

    private var placeholder: String {
        isDisband ? "Guild name" : "Reason"
    }

    private func confirm() {
        switch prompt {
        case .leave:
            playSession.leaveGuild(reason: text)
        case .expel(let member):
            playSession.expelGuildMember(member, reason: text)
        case .disband:
            playSession.disbandGuild(confirmingName: text)
        }
    }
}

// MARK: - Invitation

struct GuildInvitationView: View {
    var invitation: GuildInvitation

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        MessageBoxView("\(invitation.guildName) invites you to join the guild.") {
            Button {
                playSession.answerGuildInvitation(accept: true)
            } label: {
                Text(verbatim: "Accept")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)

            Button {
                playSession.answerGuildInvitation(accept: false)
            } label: {
                Text(verbatim: "Decline")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
        }
        .gameWindowTitle(Text(verbatim: "Guild Invitation"))
    }
}

// MARK: - Helpers

private extension View {
    func guildField() -> some View {
        textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1)))
    }
}

/// Packet fields are fixed size byte strings, so the length limits count UTF-8 bytes.
private func clampedToBytes(_ text: String, limit: Int) -> String {
    var text = text
    while text.utf8.count > limit {
        text.removeLast()
    }
    return text
}

private func previewGuild() -> Guild {
    var guild = Guild()
    guild.apply(info: Guild.Info(
        guildID: 1,
        name: "Poring Hunters",
        level: 3,
        onlineCount: 1,
        maxMemberCount: 16,
        averageLevel: 60,
        exp: 120,
        nextExp: 500,
        emblemID: 0,
        masterCharacterID: 1,
        masterName: "Leon",
        castleName: "Not managing any castle"
    ))
    guild.apply(positionNames: [(id: 0, name: "Guild Master"), (id: 1, name: "Member")])
    guild.apply(members: [
        Guild.Member(
            accountID: 1,
            characterID: 1,
            name: "Leon",
            job: JobID.knight.rawValue,
            baseLevel: 50,
            contribution: 1200,
            positionID: 0,
            isOnline: true,
            lastLogin: nil
        ),
        Guild.Member(
            accountID: 2,
            characterID: 2,
            name: "Poring",
            job: JobID.acolyte.rawValue,
            baseLevel: 40,
            contribution: 300,
            positionID: 1,
            isOnline: false,
            lastLogin: Date(timeIntervalSinceNow: -86400)
        ),
    ])
    return guild
}

#Preview {
    GuildView(guild: previewGuild())
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
