//
//  LocalizedSource.swift
//  RagnarokLocalization
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// One localization table, tried in order by a lookup.
struct LocalizedSource<Key: Hashable, Value> {
    var values: [Key : Value]

    /// Whether text in this table may be Korean. Only the Korean table may; elsewhere Korean text marks an entry nobody translated.
    var allowsKorean: Bool

    init(values: [Key : Value], allowsKorean: Bool = false) {
        self.values = values
        self.allowsKorean = allowsKorean
    }

    /// The first of `sources` with a usable string for `key`.
    static func text(
        forKey key: Key,
        in sources: [LocalizedSource<Key, Value>],
        _ keyPath: KeyPath<Value, String?>
    ) -> String? {
        for source in sources {
            if let text = LocalizedText.usable(source.values[key]?[keyPath: keyPath], allowsKorean: source.allowsKorean) {
                return text
            }
        }
        return nil
    }
}

extension LocalizedSource where Key: Decodable, Value: Decodable {

    /// The `name.json` table of the localization `locale` maps to, then the English one unless that is English already.
    /// A localization without the file gives an empty table.
    static func sources(named name: String, locale: Locale) -> [LocalizedSource<Key, Value>] {
        let localization = Bundle.module.localization(for: locale)
        var sources = [
            LocalizedSource(
                values: decode(named: name, localization: localization) ?? [:],
                allowsKorean: localization == LocalizedText.koreanLocalization
            )
        ]
        if localization != LocalizedText.englishLocalization {
            sources.append(LocalizedSource(values: decode(named: name, localization: LocalizedText.englishLocalization) ?? [:]))
        }
        return sources
    }

    private static func decode(named name: String, localization: String) -> [Key : Value]? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: nil, localization: localization) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Key : Value].self, from: data)
        } catch {
            return nil
        }
    }
}
