//
//  MonsterNameTable.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2024/5/29.
//

import Foundation

/// Monster names.
///
/// Only the Chinese localizations have a table of their own. A lookup tries it, then the name the server's monster
/// database gives, which is English. The map shows the name the server sends with each monster, so this table is for
/// places that only have a monster id, such as a quest objective or a database page.
final public class MonsterNameTable {
    let sources: [LocalizedSource<Int, String>]
    let serverMonsterNamesByID: [Int : String]

    public convenience init(locale: Locale = .current) {
        self.init(
            sources: LocalizedSource<Int, String>.sources(named: "MonsterName", locale: locale),
            serverMonsterNamesByID: ServerNameTable.shared.monsterNamesByID
        )
    }

    init(sources: [LocalizedSource<Int, String>], serverMonsterNamesByID: [Int : String]) {
        self.sources = sources
        self.serverMonsterNamesByID = serverMonsterNamesByID
    }

    public func localizedMonsterName(forMonsterID monsterID: Int) -> String? {
        for source in sources {
            if let name = LocalizedText.usable(source.values[monsterID], allowsKorean: source.allowsKorean) {
                return name
            }
        }
        return serverMonsterNamesByID[monsterID]
    }
}
