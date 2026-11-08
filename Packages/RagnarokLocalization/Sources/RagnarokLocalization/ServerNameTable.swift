//
//  ServerNameTable.swift
//  RagnarokLocalization
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The English names rAthena's database files give to items, skills and monsters.
///
/// This is the last source of a name lookup. The localization tables come from the clients of other servers and
/// miss ids that the target server has (11,382 of its 29,356 items are not in the English table, among them
/// Claymore and Scratcher), while the server always has an English name for every id it hands out.
///
/// `Resources/ServerNames.json` is generated from `db/re/item_db_*.yml` (`Name`), `skill_db.yml` (`Description`)
/// and `mob_db.yml` (`Name`) with `scripts/gen-server-names.py`. Regenerate it when the rAthena pin changes.
struct ServerNameTable: Sendable {
    var itemNamesByID: [Int : String]
    var skillNamesByID: [Int : String]
    var monsterNamesByID: [Int : String]

    init(
        itemNamesByID: [Int : String] = [:],
        skillNamesByID: [Int : String] = [:],
        monsterNamesByID: [Int : String] = [:]
    ) {
        self.itemNamesByID = itemNamesByID
        self.skillNamesByID = skillNamesByID
        self.monsterNamesByID = monsterNamesByID
    }

    private struct Document: Decodable {
        var items: [Int : String]
        var skills: [Int : String]
        var monsters: [Int : String]
    }

    /// Read once; an item table is 1 MB of JSON.
    static let shared: ServerNameTable = {
        guard let url = Bundle.module.url(forResource: "ServerNames", withExtension: "json") else {
            return ServerNameTable()
        }

        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(Document.self, from: data)
            return ServerNameTable(
                itemNamesByID: document.items,
                skillNamesByID: document.skills,
                monsterNamesByID: document.monsters
            )
        } catch {
            return ServerNameTable()
        }
    }()
}
