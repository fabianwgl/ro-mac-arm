import Foundation
import Testing
@testable import RagnarokGame

struct QuestLogTests {
    @Test func applyAllQuestsReplacesState() {
        let questLog = QuestLog()

        questLog.apply(allQuests: [
            quest(id: 1, objectives: [objective(huntID: 1, monsterID: 1002, count: 1, required: 10)])
        ])
        questLog.apply(allQuests: [quest(id: 2)])

        #expect(questLog.quests.count == 1)
        #expect(questLog.quests[1] == nil)
        #expect(questLog.quests[2]?.isActive == false)
    }

    @Test func addQuest() {
        let questLog = QuestLog()

        questLog.add(quest(id: 1))
        questLog.add(quest(id: 2, isActive: true))

        #expect(questLog.quests.count == 2)
        #expect(questLog.quests[2]?.isActive == true)
    }

    @Test func removeQuest() {
        let questLog = QuestLog()

        questLog.add(quest(id: 1))
        questLog.remove(questID: 1)
        questLog.remove(questID: 99)

        #expect(questLog.quests.isEmpty)
    }

    @Test func updateHuntKeepsSentCount() {
        let questLog = QuestLog()
        questLog.add(quest(
            id: 1,
            objectives: [objective(huntID: 1, huntID2: 2, monsterID: 1002, count: 1, required: 10)]
        ))

        questLog.updateHunt(questID: 1, huntID: 1, huntID2: 2, count: 10)
        #expect(questLog.quests[1]?.objectives.first?.count == 10)

        questLog.updateHunt(questID: 1, huntID: 1, huntID2: 2, count: 25)
        #expect(questLog.quests[1]?.objectives.first?.count == 25)

        questLog.updateHunt(questID: 1, huntID: 1, huntID2: 2, count: -1)
        #expect(questLog.quests[1]?.objectives.first?.count == -1)
    }

    @Test func unknownUpdatesAreIgnored() {
        let questLog = QuestLog()
        questLog.add(quest(
            id: 1,
            objectives: [objective(huntID: 1, huntID2: 2, monsterID: 1002, count: 1, required: 10)]
        ))

        questLog.updateHunt(questID: 99, huntID: 1, huntID2: 2, count: 50)
        questLog.updateHunt(questID: 1, huntID: 99, huntID2: 2, count: 50)
        questLog.updateHunt(questID: 1, huntID: 1, huntID2: 99, count: 50)
        questLog.setActive(questID: 99, true)
        questLog.remove(questID: 99)

        #expect(questLog.quests.count == 1)
        #expect(questLog.quests[1]?.objectives.first?.count == 1)
        #expect(questLog.quests[1]?.isActive == false)
    }

    @Test func setActiveTogglesQuest() {
        let questLog = QuestLog()
        questLog.add(quest(id: 1))

        questLog.setActive(questID: 1, true)
        #expect(questLog.quests[1]?.isActive == true)

        questLog.setActive(questID: 1, false)
        #expect(questLog.quests[1]?.isActive == false)
    }

    @Test func activeAndInactiveQuestsAreSeparated() {
        let questLog = QuestLog()
        questLog.add(quest(id: 2, isActive: true))
        questLog.add(quest(id: 1, isActive: true))
        questLog.add(quest(id: 3))

        #expect(questLog.activeQuests.map(\.id) == [1, 2])
        #expect(questLog.inactiveQuests.map(\.id) == [3])
    }

    @Test func missionsFillNamesAndRequiredCounts() {
        let questLog = QuestLog()
        questLog.add(quest(
            id: 1,
            objectives: [objective(huntID: 1, huntID2: 2, monsterID: 1002, count: 3, required: 3)]
        ))

        questLog.apply(missions: [
            QuestLog.Mission(
                questID: 1,
                huntID: 1,
                huntID2: 2,
                monsterName: "Poring",
                required: 10
            )
        ])

        #expect(questLog.quests[1]?.objectives.first?.monsterName == "Poring")
        #expect(questLog.quests[1]?.objectives.first?.required == 10)
        #expect(questLog.quests[1]?.objectives.first?.count == 3)
    }

    @Test func missionsReceivedBeforeQuestAreAppliedOnAdd() {
        let questLog = QuestLog()
        questLog.apply(missions: [
            QuestLog.Mission(
                questID: 1,
                huntID: 1,
                huntID2: 2,
                monsterName: "Poring",
                required: 10
            )
        ])

        questLog.add(quest(
            id: 1,
            objectives: [objective(huntID: 1, huntID2: 2, monsterID: 1002, count: 3, required: 3)]
        ))

        #expect(questLog.quests[1]?.objectives.first?.monsterName == "Poring")
        #expect(questLog.quests[1]?.objectives.first?.required == 10)
    }

    private func quest(
        id: UInt32,
        isActive: Bool = false,
        timeLimit: TimeInterval? = nil,
        objectives: [QuestLog.Objective] = []
    ) -> QuestLog.Quest {
        QuestLog.Quest(
            id: id,
            isActive: isActive,
            timeLimit: timeLimit,
            objectives: objectives
        )
    }

    private func objective(
        huntID: UInt32,
        huntID2: UInt32 = 0,
        monsterID: UInt32,
        count: Int,
        required: Int
    ) -> QuestLog.Objective {
        QuestLog.Objective(
            huntID: huntID,
            huntID2: huntID2,
            monsterID: monsterID,
            monsterName: "",
            count: count,
            required: required
        )
    }
}
