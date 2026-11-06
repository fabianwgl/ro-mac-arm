//
//  AchievementListLoader.swift
//  RagnarokScript
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokLua
import RagnarokResources

struct AchievementListLoader {

    /// The script sits next to `itemInfo.lub`, outside `data/`.
    static let path: ResourcePath = ["System", "achievement_list.lub"]

    /// - Parameter data: Lua 5.1 bytecode or Lua source of `achievement_list.lub`.
    func achievementList(from data: Data) -> AchievementList {
        let context = LuaContext()

        // The script defines `achievement_tbl` and a `main` function, and does not run `main` when loaded.
        do {
            try context.load(data)
        } catch {
            logger.warning("\(error)")
            return AchievementList()
        }

        guard let table = context["achievement_tbl"].tableValue else {
            logger.warning("achievement_tbl not found")
            return AchievementList()
        }

        var entries: [Int : AchievementList.Entry] = [:]
        for (key, value) in table {
            guard let id = key.intValue, let entry = entry(id: id, from: value) else {
                continue
            }
            entries[id] = entry
        }
        return AchievementList(entries: entries)
    }

    private func entry(id: Int, from value: LuaValue) -> AchievementList.Entry? {
        guard value.tableValue != nil else {
            return nil
        }

        let content = value["content"] ?? .nil
        let resources = value["resource"]?.arrayValue ?? []

        return AchievementList.Entry(
            id: id,
            group: value["group"]?.stringValue ?? "",
            major: value["major"]?.intValue ?? 0,
            minor: value["minor"]?.intValue ?? 0,
            title: text(value["title"]),
            summary: text(content["summary"]),
            details: text(content["details"]),
            objectives: resources.map(objective(from:)),
            reward: reward(from: value["reward"]),
            score: value["score"]?.intValue ?? 0,
            uiType: value["UI_Type"]?.intValue ?? 0
        )
    }

    // An objective is `{text, count?, shortcut?}`.
    private func objective(from value: LuaValue) -> AchievementList.Objective {
        AchievementList.Objective(
            text: text(value["text"]),
            requiredCount: value["count"]?.intValue,
            shortcutID: value["shortcut"]?.intValue
        )
    }

    // A reward is `{item?, title?, buff?}`, or `{}` or missing.
    private func reward(from value: LuaValue?) -> AchievementList.Reward {
        AchievementList.Reward(
            itemID: value?["item"]?.intValue,
            titleID: value?["title"]?.intValue,
            buffID: value?["buff"]?.intValue
        )
    }

    /// The script is CP949 text, as in the world map scripts.
    private func text(_ value: LuaValue?) -> String {
        value?.string(using: .dosKorean) ?? value?.stringValue ?? ""
    }
}
