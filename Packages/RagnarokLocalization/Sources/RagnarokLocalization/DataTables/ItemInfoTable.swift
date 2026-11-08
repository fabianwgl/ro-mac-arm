//
//  ItemInfoTable.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2024/5/28.
//

import Foundation

struct ItemInfo: Decodable {
    var unidentifiedItemName: String?
    var unidentifiedItemDescription: String?
    var identifiedItemName: String?
    var identifiedItemDescription: String?
}

/// Item names and descriptions.
///
/// A lookup tries the table of the locale, then the English table, then (for identified names) the name the server's
/// item database gives. It returns `nil` only for an id none of them knows.
final public class ItemInfoTable {
    let sources: [LocalizedSource<Int, ItemInfo>]
    let serverItemNamesByID: [Int : String]

    public convenience init(locale: Locale = .current) {
        self.init(
            sources: LocalizedSource<Int, ItemInfo>.sources(named: "ItemInfo", locale: locale),
            serverItemNamesByID: ServerNameTable.shared.itemNamesByID
        )
    }

    init(sources: [LocalizedSource<Int, ItemInfo>], serverItemNamesByID: [Int : String]) {
        self.sources = sources
        self.serverItemNamesByID = serverItemNamesByID
    }

    public func localizedIdentifiedItemName(forItemID itemID: Int) -> String? {
        text(\.identifiedItemName, forItemID: itemID) ?? serverItemNamesByID[itemID]
    }

    public func localizedIdentifiedItemDescription(forItemID itemID: Int) -> String? {
        text(\.identifiedItemDescription, forItemID: itemID)
    }

    /// The name of an item before it is appraised, such as `Dagger` for a Knife. `nil` for an item that has none.
    public func localizedUnidentifiedItemName(forItemID itemID: Int) -> String? {
        text(\.unidentifiedItemName, forItemID: itemID)
    }

    public func localizedUnidentifiedItemDescription(forItemID itemID: Int) -> String? {
        text(\.unidentifiedItemDescription, forItemID: itemID)
    }

    /// The name a player sees: the unidentified name for an item that is not appraised yet, and the identified name
    /// for everything else, including an unidentified item that has no unidentified name.
    public func localizedItemName(forItemID itemID: Int, isIdentified: Bool) -> String? {
        if !isIdentified, let name = localizedUnidentifiedItemName(forItemID: itemID) {
            return name
        }
        return localizedIdentifiedItemName(forItemID: itemID)
    }

    public func localizedItemDescription(forItemID itemID: Int, isIdentified: Bool) -> String? {
        if !isIdentified, let description = localizedUnidentifiedItemDescription(forItemID: itemID) {
            return description
        }
        return localizedIdentifiedItemDescription(forItemID: itemID)
    }

    private func text(_ keyPath: KeyPath<ItemInfo, String?>, forItemID itemID: Int) -> String? {
        LocalizedSource.text(forKey: itemID, in: sources, keyPath)
    }
}
