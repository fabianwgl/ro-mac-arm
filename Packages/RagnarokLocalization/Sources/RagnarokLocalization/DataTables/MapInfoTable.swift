//
//  MapInfoTable.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2024/5/27.
//

import Foundation

struct MapInfo: Decodable {
    var displayName: String
    var signMainTitle: String?
    var signSubTitle: String?

    var optionalDisplayName: String? {
        displayName
    }
}

/// Map names and sign titles. A lookup tries the table of the locale, then the English table.
final public class MapInfoTable {
    let sources: [LocalizedSource<String, MapInfo>]

    public convenience init(locale: Locale = .current) {
        self.init(sources: LocalizedSource<String, MapInfo>.sources(named: "MapInfo", locale: locale))
    }

    init(sources: [LocalizedSource<String, MapInfo>]) {
        self.sources = sources
    }

    public func localizedMapName(forMapName mapName: String) -> String? {
        LocalizedSource.text(forKey: mapName, in: sources, \.optionalDisplayName)
    }

    public func localizedMapSignMainTitle(forMapName mapName: String) -> String? {
        LocalizedSource.text(forKey: mapName, in: sources, \.signMainTitle)
    }

    public func localizedMapSignSubTitle(forMapName mapName: String) -> String? {
        LocalizedSource.text(forKey: mapName, in: sources, \.signSubTitle)
    }
}
