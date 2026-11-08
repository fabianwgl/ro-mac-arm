//
//  SkillInfoTable.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2025/8/5.
//

import Foundation

struct SkillInfo: Decodable {
    var skillName: String?
    var skillDescription: String?
}

/// Skill names and descriptions.
///
/// A lookup tries the table of the locale, then the English table, then (for names) the name the server's skill
/// database gives. It returns `nil` only for an id none of them knows.
final public class SkillInfoTable {
    let sources: [LocalizedSource<Int, SkillInfo>]
    let serverSkillNamesByID: [Int : String]

    public convenience init(locale: Locale = .current) {
        self.init(
            sources: LocalizedSource<Int, SkillInfo>.sources(named: "SkillInfo", locale: locale),
            serverSkillNamesByID: ServerNameTable.shared.skillNamesByID
        )
    }

    init(sources: [LocalizedSource<Int, SkillInfo>], serverSkillNamesByID: [Int : String]) {
        self.sources = sources
        self.serverSkillNamesByID = serverSkillNamesByID
    }

    public func localizedSkillName(forSkillID skillID: Int) -> String? {
        LocalizedSource.text(forKey: skillID, in: sources, \.skillName) ?? serverSkillNamesByID[skillID]
    }

    public func localizedSkillDescription(forSkillID skillID: Int) -> String? {
        LocalizedSource.text(forKey: skillID, in: sources, \.skillDescription)
    }
}
