//
//  QuestLogView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

private enum QuestLogTab: CaseIterable {
    case active
    case inactive
}

struct QuestLogView: View {
    var questLog: QuestLog
    var onClose: () -> Void = {}

    @State private var tab: QuestLogTab = .active

    var body: some View {
        GameWindow {
            HStack(alignment: .top, spacing: 0) {
                GameVerticalTabBar(tabs: QuestLogTab.allCases, selection: $tab) { tab in
                    switch tab {
                    case .active:
                        Text(verbatim: "Active")
                    case .inactive:
                        Text(verbatim: "Inactive")
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if quests.isEmpty {
                            Text(verbatim: tab == .active ? "No active quests." : "No inactive quests.")
                                .font(.game(size: 11))
                                .foregroundStyle(Color.gameProminentLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }

                        ForEach(quests) { quest in
                            QuestLogRow(quest: quest)
                        }
                    }
                }
                .frame(height: 240)
            }
        } bottomBar: {
            GameBottomBar {
                Text(verbatim: "\(questLog.activeQuests.count) active")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)

                Spacer()
            }
        }
        .gameWindowTitle(Text(verbatim: "Quest Log"))
        .gameWindowCloseAction(onClose)
        .frame(width: 320)
    }

    private var quests: [QuestLog.Quest] {
        switch tab {
        case .active:
            questLog.activeQuests
        case .inactive:
            questLog.inactiveQuests
        }
    }
}

private struct QuestLogRow: View {
    var quest: QuestLog.Quest

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(verbatim: "Quest #\(quest.id)")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    playSession.setQuestActive(questID: quest.id, active: !quest.isActive)
                } label: {
                    Text(verbatim: quest.isActive ? "Deactivate" : "Activate")
                }
                .buttonStyle(.game)
                .frame(width: 68, height: 20)
            }

            if let timeLimit = quest.timeLimit {
                Text(verbatim: "Time limit: \(Int((timeLimit / 60).rounded(.up))) min")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            }

            ForEach(quest.objectives) { objective in
                Text(verbatim: objectiveText(objective))
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(quest.isActive ? Color(#colorLiteral(red: 0.9137254902, green: 0.9411764706, blue: 0.9803921569, alpha: 1)) : .clear)
    }

    private func objectiveText(_ objective: QuestLog.Objective) -> String {
        // The server names the monster in the quest packet; when it sends none, the monster table does.
        let monsterName = if !objective.monsterName.isEmpty {
            objective.monsterName
        } else if let name = gameContext.monsterNameTable.localizedMonsterName(forMonsterID: Int(objective.monsterID)) {
            name
        } else {
            "Monster #\(objective.monsterID)"
        }
        return "\(monsterName) \(objective.count)/\(objective.required)"
    }
}

#Preview {
    let playSession = PlaySession(context: .testing)

    playSession.questLog.apply(allQuests: [
        QuestLog.Quest(
            id: 1001,
            isActive: true,
            timeLimit: 3600,
            objectives: [
                QuestLog.Objective(
                    huntID: 1001,
                    huntID2: 0,
                    monsterID: 1002,
                    monsterName: "Poring",
                    count: 3,
                    required: 10
                )
            ]
        ),
        QuestLog.Quest(
            id: 1002,
            isActive: false,
            timeLimit: nil,
            objectives: []
        )
    ])

    return QuestLogView(questLog: playSession.questLog)
        .padding()
        .environment(GameContext.testing)
        .environment(playSession)
}
