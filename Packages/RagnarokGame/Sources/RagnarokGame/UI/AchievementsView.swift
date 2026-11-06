//
//  AchievementsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import SwiftUI

struct AchievementsView: View {
    var achievements: Achievements
    var onClose: () -> Void = {}

    @State private var filter: Achievements.Filter = .all

    var body: some View {
        GameWindow {
            VStack(spacing: 0) {
                AchievementsHeader(achievements: achievements)

                HStack(alignment: .top, spacing: 0) {
                    GameVerticalTabBar(tabs: Achievements.Filter.allCases, selection: $filter) { filter in
                        Text(verbatim: filter.title)
                    }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if rows.isEmpty {
                                Text(verbatim: emptyText)
                                    .font(.game(size: 11))
                                    .foregroundStyle(Color.gameProminentLabel)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }

                            ForEach(rows) { entry in
                                AchievementRow(achievements: achievements, entry: entry)
                            }
                        }
                    }
                    .frame(height: 280)
                }
            }
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "\(achievements.completedCount)/\(achievements.entries.count) completed")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                if achievements.claimableCount > 0 {
                    Text(verbatim: "\(achievements.claimableCount) reward\(achievements.claimableCount == 1 ? "" : "s") ready")
                        .font(.game())
                        .foregroundStyle(Color.gameProminentLabel)
                }

                Spacer()
            }
        }
        .gameWindowTitle(Text(verbatim: "Achievements"))
        .gameWindowCloseAction(onClose)
        .frame(width: 380)
    }

    private var rows: [Achievements.Entry] {
        achievements.sortedEntries(matching: filter)
    }

    private var emptyText: String {
        guard achievements.isInitialized, !achievements.entries.isEmpty else {
            return "No achievements yet."
        }
        switch filter {
        case .all:
            return "No achievements yet."
        case .inProgress:
            return "Nothing in progress."
        case .completed:
            return "No completed achievements."
        case .rewardReady:
            return "No rewards to claim."
        }
    }
}

extension Achievements.Filter {
    fileprivate var title: String {
        switch self {
        case .all:
            "All"
        case .inProgress:
            "In Progress"
        case .completed:
            "Completed"
        case .rewardReady:
            "Rewards"
        }
    }
}

// MARK: - Header

private struct AchievementsHeader: View {
    var achievements: Achievements

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(achievements.level)")
                .font(.game(size: 14, weight: .bold))
                .foregroundStyle(Color.gameLabel)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(Color(#colorLiteral(red: 0.9568627451, green: 0.7607843137, blue: 0.2509803922, alpha: 1)))
                        .overlay {
                            Circle().strokeBorder(Color(#colorLiteral(red: 0.6, green: 0.4352941176, blue: 0.0980392157, alpha: 1)), lineWidth: 1.5)
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: "Achievement Level")
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    Spacer(minLength: 0)

                    Text(verbatim: "\(achievements.totalPoints) points")
                        .font(.game())
                        .foregroundStyle(Color.gameProminentLabel)
                }

                AchievementExperienceBar(
                    fraction: achievements.levelFraction,
                    text: experienceText
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.gameSecondaryBoxBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gameBoxBorder).frame(height: 1)
        }
    }

    private var experienceText: String {
        // The server sends a zero span at the last level.
        if achievements.experienceToNextLevel > 0 {
            "\(achievements.experience) / \(achievements.experienceToNextLevel)"
        } else {
            "MAX"
        }
    }
}

private struct AchievementExperienceBar: View {
    var fraction: Double
    var text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .circular)
            .fill(Color(#colorLiteral(red: 0.5490196078, green: 0.5490196078, blue: 0.5490196078, alpha: 1)))
            .frame(height: 15)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color(#colorLiteral(red: 0.2588235294, green: 0.3882352941, blue: 0.6470588235, alpha: 1)))
                        .frame(width: max(0, fraction * (geometry.size.width - 4)), height: 11)
                        .offset(x: 2, y: 2)
                }
            }
            .overlay {
                Text(verbatim: text)
                    .font(.game(size: 11))
                    .foregroundStyle(Color(#colorLiteral(red: 1, green: 1, blue: 0, alpha: 1)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .circular)
                    .strokeBorder(Color(#colorLiteral(red: 0, green: 1, blue: 1, alpha: 1)))
            }
    }
}

// MARK: - Row

private struct AchievementRow: View {
    var achievements: Achievements
    var entry: Achievements.Entry

    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: achievements.title(for: entry.id))
                    .font(.game(weight: .bold))
                    .foregroundStyle(Color.gameLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameProminentLabel)
                }

                if let details = info?.details, !details.isEmpty {
                    Text(verbatim: details)
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(achievements.progressRows(for: entry).enumerated()), id: \.offset) { _, row in
                    AchievementProgressRow(row: row)
                }

                if let rewardText {
                    Text(verbatim: rewardText)
                        .font(.game(size: 11))
                        .foregroundStyle(Color.gameProminentLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if entry.isCompleted, let completedAt = entry.completedAt {
                    Text(verbatim: "Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.game(size: 11))
                        .foregroundStyle(Color(#colorLiteral(red: 0.462745098, green: 0.462745098, blue: 0.462745098, alpha: 1)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(achievements.hasClaimableReward(entry) ? Color(#colorLiteral(red: 0.9137254902, green: 0.9411764706, blue: 0.9803921569, alpha: 1)) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gameBoxBorder.opacity(0.6)).frame(height: 1)
        }
    }

    private var info: Achievements.Info? {
        achievements.info[entry.id]
    }

    private var subtitle: String? {
        guard let info else {
            return nil
        }
        var parts: [String] = []
        if !info.group.isEmpty {
            parts.append(Achievements.displayName(forGroup: info.group))
        }
        if info.score > 0 {
            parts.append("\(info.score) points")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var rewardText: String? {
        guard let info, info.hasReward else {
            return nil
        }
        var parts: [String] = []
        if let itemID = info.rewardItemID {
            let name = gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: itemID) ?? "Item #\(itemID)"
            parts.append(name)
        }
        if info.hasRewardTitle {
            parts.append("Title")
        }
        if info.hasRewardBuff {
            parts.append("Buff")
        }
        return "Reward: " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var trailing: some View {
        if achievements.hasClaimableReward(entry) {
            let isPending = achievements.isClaimPending(id: entry.id)
            Button {
                playSession.claimAchievementReward(id: entry.id)
            } label: {
                Text(verbatim: isPending ? "..." : "Claim")
            }
            .buttonStyle(.game)
            .frame(width: 52, height: 20)
            .disabled(isPending)
        } else if entry.isCompleted {
            Text(verbatim: entry.isRewardClaimed ? "Claimed" : "Done")
                .font(.game(size: 11))
                .foregroundStyle(Color(#colorLiteral(red: 0.462745098, green: 0.462745098, blue: 0.462745098, alpha: 1)))
        }
    }
}

private struct AchievementProgressRow: View {
    var row: Achievements.ProgressRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(verbatim: row.isDone ? "✓" : "•")
                    .font(.game(size: 11))
                    .foregroundStyle(row.isDone ? Color(#colorLiteral(red: 0.1960784314, green: 0.5490196078, blue: 0.2352941176, alpha: 1)) : Color.gameProminentLabel)
                    .frame(width: 10)

                Text(verbatim: label)
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fraction, !row.isDone {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gameBoxBorder)
                        Capsule()
                            .fill(Color(#colorLiteral(red: 0.2588235294, green: 0.3882352941, blue: 0.6470588235, alpha: 1)))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: 3)
                .padding(.leading, 14)
            }
        }
    }

    private var label: String {
        if let required = row.required {
            "\(row.text) \(row.isDone ? required : row.current)/\(required)"
        } else if row.text.isEmpty {
            "\(row.current)"
        } else {
            row.text
        }
    }

    private var fraction: Double? {
        guard let required = row.required, required > 0 else {
            return nil
        }
        return min(max(Double(row.current) / Double(required), 0), 1)
    }
}

#Preview {
    let playSession = PlaySession(context: .testing)

    playSession.achievements.apply(
        list: [
            Achievements.Entry(id: 120001, progress: [1]),
            Achievements.Entry(id: 120002, isCompleted: true, completedAt: .now),
            Achievements.Entry(id: 127001, progress: [1500]),
            Achievements.Entry(id: 130000, isCompleted: true, completedAt: .now, isRewardClaimed: true),
        ],
        level: Achievements.Level(totalPoints: 130, level: 3, experience: 30, experienceToNextLevel: 100)
    )
    playSession.achievements.apply(catalog: [
        120001: Achievements.Info(
            title: "North Field (1)", summary: "Hidden treasure", details: "Find the treasure north of Prontera.", group: "ADVENTURE",
            objectives: [.init(text: "Find the treasure", requiredCount: nil)],
            rewardItemID: 501, hasRewardTitle: false, hasRewardBuff: false, score: 10
        ),
        120002: Achievements.Info(
            title: "North Field (2)", summary: "", details: "Find the second treasure.", group: "ADVENTURE",
            objectives: [.init(text: "Find the treasure", requiredCount: nil)],
            rewardItemID: 501, hasRewardTitle: false, hasRewardBuff: false, score: 10
        ),
        127001: Achievements.Info(
            title: "Prontera Fame", summary: "", details: "How the city sees you.", group: "CHATTING",
            objectives: [.init(text: "Stranger", requiredCount: 3000), .init(text: "Newcomer", requiredCount: 6000)],
            rewardItemID: nil, hasRewardTitle: false, hasRewardBuff: false, score: 10
        ),
    ])

    return AchievementsView(achievements: playSession.achievements)
        .padding()
        .environment(GameContext.testing)
        .environment(playSession)
}
