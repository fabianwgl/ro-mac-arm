//
//  AchievementListTests.swift
//  RagnarokScriptTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import XCTest
@testable import RagnarokScript

/// These tests run the loader on small scripts shaped like kRO's `System/achievement_list.lub`, so they need
/// no client files and no server.
final class AchievementListTests: XCTestCase {
    private let script = """
    achievement_tbl = {
    [120001] = {UI_Type = 0, group = "ADVENTURE", major = 2, minor = 0, title = "North Field (1)",
    content = {summary = "Hidden treasure", details = "Find the treasure north of Prontera"},
    resource = {
    [1] = {text = "Find it"}
    },
    reward = {item = 22876}, score = 10},
    [127001] = {UI_Type = 1, group = "CHATTING", major = 4, minor = 1, title = "Fame",
    content = {summary = "City fame", details = "How the city sees you"},
    resource = {
    [1] = {text = "Stranger", count = 3000},
    [2] = {text = "Newcomer", count = 6000, shortcut = 127002}
    },
    score = 20},
    [130000] = {UI_Type = 0, group = "BATTLE", major = 1, minor = 0, title = "Hero",
    content = {summary = "s", details = "d"},
    resource = {},
    reward = {title = 1000, buff = 10, item = 12549}, score = 30}
    }
    function main() return 1 end
    """

    func testParsesEntries() throws {
        let list = AchievementListLoader().achievementList(from: Data(script.utf8))
        XCTAssertEqual(list.entries.count, 3)

        let entry = try XCTUnwrap(list.entry(forID: 120001))
        XCTAssertEqual(entry.group, "ADVENTURE")
        XCTAssertEqual(entry.major, 2)
        XCTAssertEqual(entry.minor, 0)
        XCTAssertEqual(entry.title, "North Field (1)")
        XCTAssertEqual(entry.summary, "Hidden treasure")
        XCTAssertEqual(entry.details, "Find the treasure north of Prontera")
        XCTAssertEqual(entry.score, 10)
        XCTAssertEqual(entry.uiType, 0)
        XCTAssertEqual(entry.objectives, [AchievementList.Objective(text: "Find it", requiredCount: nil, shortcutID: nil)])
        XCTAssertEqual(entry.reward.itemID, 22876)
        XCTAssertNil(entry.reward.titleID)
        XCTAssertFalse(entry.reward.isEmpty)
    }

    func testParsesCountsAndShortcuts() throws {
        let list = AchievementListLoader().achievementList(from: Data(script.utf8))
        let entry = try XCTUnwrap(list.entry(forID: 127001))

        XCTAssertEqual(entry.uiType, 1)
        XCTAssertEqual(entry.objectives.map(\.requiredCount), [3000, 6000])
        XCTAssertEqual(entry.objectives.map(\.shortcutID), [nil, 127002])
        XCTAssertTrue(entry.reward.isEmpty)
    }

    func testParsesTitleAndBuffRewards() throws {
        let list = AchievementListLoader().achievementList(from: Data(script.utf8))
        let entry = try XCTUnwrap(list.entry(forID: 130000))

        XCTAssertEqual(entry.reward, AchievementList.Reward(itemID: 12549, titleID: 1000, buffID: 10))
        XCTAssertTrue(entry.objectives.isEmpty)
    }

    func testDecodesCP949Text() throws {
        let korean = "프론테라 북쪽 필드 탐험"
        let cp949 = try XCTUnwrap(korean.data(using: .dosKorean))
        var data = Data("achievement_tbl = {[1] = {group = \"ADVENTURE\", title = \"".utf8)
        data.append(cp949)
        data.append(Data("\", content = {summary = \"\", details = \"\"}, resource = {}, score = 10}}".utf8))

        let list = AchievementListLoader().achievementList(from: data)
        XCTAssertEqual(list.entry(forID: 1)?.title, korean)
    }

    func testMissingTableGivesEmptyList() {
        let list = AchievementListLoader().achievementList(from: Data("other = {}".utf8))
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testInvalidScriptGivesEmptyList() {
        let list = AchievementListLoader().achievementList(from: Data("this is not lua (".utf8))
        XCTAssertTrue(list.entries.isEmpty)
    }

    /// Runs on the real kRO bytecode when `RO_CLIENT_DIR` points at a client directory with `System/achievement_list.lub`.
    func testRealClientFile() throws {
        guard let clientDirectory = ProcessInfo.processInfo.environment["RO_CLIENT_DIR"] else {
            throw XCTSkip("RO_CLIENT_DIR is not set")
        }
        let url = URL(filePath: clientDirectory).appending(path: "System/achievement_list.lub")
        let data = try Data(contentsOf: url)

        let list = AchievementListLoader().achievementList(from: data)
        XCTAssertEqual(list.entries.count, 361)

        let entry = try XCTUnwrap(list.entry(forID: 120001))
        XCTAssertEqual(entry.group, "ADVENTURE")
        XCTAssertEqual(entry.title, "프론테라 북쪽 필드 탐험(1)")
        XCTAssertEqual(entry.reward.itemID, 22876)
        XCTAssertEqual(entry.score, 10)

        let fame = try XCTUnwrap(list.entry(forID: 127001))
        XCTAssertEqual(fame.uiType, 1)
        XCTAssertEqual(fame.objectives.first?.requiredCount, 3000)
    }

    func testUnknownIDHasNoEntry() {
        let list = AchievementListLoader().achievementList(from: Data(script.utf8))
        XCTAssertNil(list.entry(forID: 999))
    }
}
