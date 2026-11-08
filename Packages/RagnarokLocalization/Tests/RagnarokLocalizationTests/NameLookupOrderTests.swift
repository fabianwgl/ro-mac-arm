//
//  NameLookupOrderTests.swift
//  RagnarokLocalizationTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import XCTest
@testable import RagnarokLocalization

/// A name lookup tries the table of the locale, then the English table, then the server's database.
/// These tests build the tables by hand, so they check the order and not the data.
final class NameLookupOrderTests: XCTestCase {

    // MARK: - Items

    private func itemTable(
        locale: [Int : ItemInfo] = [:],
        english: [Int : ItemInfo] = [:],
        server: [Int : String] = [:],
        allowsKorean: Bool = false
    ) -> ItemInfoTable {
        ItemInfoTable(
            sources: [
                LocalizedSource(values: locale, allowsKorean: allowsKorean),
                LocalizedSource(values: english),
            ],
            serverItemNamesByID: server
        )
    }

    func testItemNameOfTheLocaleWins() {
        let table = itemTable(
            locale: [501: ItemInfo(identifiedItemName: "Poción Roja")],
            english: [501: ItemInfo(identifiedItemName: "Red Potion")],
            server: [501: "Red Potion (server)"]
        )
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Poción Roja")
    }

    func testItemNameFallsBackToEnglish() {
        let table = itemTable(
            locale: [:],
            english: [501: ItemInfo(identifiedItemName: "Red Potion")],
            server: [501: "Red Potion (server)"]
        )
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Red Potion")
    }

    func testItemNameFallsBackToTheServerName() {
        let table = itemTable(server: [1190: "Claymore"])
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "Claymore")
    }

    func testItemNameIsNilWhenNothingKnowsTheID() {
        XCTAssertNil(itemTable().localizedIdentifiedItemName(forItemID: 999_999))
    }

    func testEmptyItemNameFallsThrough() {
        let table = itemTable(
            locale: [501: ItemInfo(identifiedItemName: "")],
            english: [501: ItemInfo(identifiedItemName: "Red Potion")]
        )
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Red Potion")
    }

    func testKoreanInAnotherLocaleFallsThrough() {
        // Hangul, and CP949 read as Latin-1, both mark an entry that was never translated.
        let table = itemTable(
            locale: [
                1190: ItemInfo(identifiedItemName: "Å©·¹ÀÌ¸ð¾î"),
                1177: ItemInfo(identifiedItemName: "무랑맛살"),
            ],
            english: [1177: ItemInfo(identifiedItemName: "Muramash")],
            server: [1190: "Claymore"]
        )
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "Claymore")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1177), "Muramash")
    }

    func testKoreanTableKeepsItsKorean() {
        let table = itemTable(
            locale: [501: ItemInfo(identifiedItemName: "빨간포션")],
            english: [501: ItemInfo(identifiedItemName: "Red Potion")],
            allowsKorean: true
        )
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "빨간포션")
    }

    func testUnidentifiedItemShowsTheUnidentifiedName() {
        let table = itemTable(
            locale: [1201: ItemInfo(unidentifiedItemName: "Dagger", identifiedItemName: "Knife")]
        )
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: false), "Dagger")
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: true), "Knife")
    }

    func testUnidentifiedItemWithoutUnidentifiedNameShowsTheIdentifiedName() {
        let table = itemTable(
            locale: [501: ItemInfo(identifiedItemName: "Red Potion")],
            server: [1190: "Claymore"]
        )
        XCTAssertEqual(table.localizedItemName(forItemID: 501, isIdentified: false), "Red Potion")
        XCTAssertEqual(table.localizedItemName(forItemID: 1190, isIdentified: false), "Claymore")
    }

    func testUnidentifiedNameFallsBackToEnglishBeforeTheIdentifiedName() {
        let table = itemTable(
            locale: [1201: ItemInfo(identifiedItemName: "Cuchillo")],
            english: [1201: ItemInfo(unidentifiedItemName: "Dagger", identifiedItemName: "Knife")]
        )
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: false), "Dagger")
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: true), "Cuchillo")
    }

    func testItemDescriptionFollowsIdentification() {
        let table = itemTable(
            locale: [
                1201: ItemInfo(
                    unidentifiedItemDescription: "Unknown item.",
                    identifiedItemDescription: "A simple knife."
                )
            ],
            english: [501: ItemInfo(identifiedItemDescription: "A potion.")]
        )
        XCTAssertEqual(table.localizedItemDescription(forItemID: 1201, isIdentified: false), "Unknown item.")
        XCTAssertEqual(table.localizedItemDescription(forItemID: 1201, isIdentified: true), "A simple knife.")
        XCTAssertEqual(table.localizedItemDescription(forItemID: 501, isIdentified: false), "A potion.")
        XCTAssertNil(table.localizedItemDescription(forItemID: 1190, isIdentified: true))
    }

    // MARK: - Skills

    private func skillTable(
        locale: [Int : SkillInfo] = [:],
        english: [Int : SkillInfo] = [:],
        server: [Int : String] = [:]
    ) -> SkillInfoTable {
        SkillInfoTable(
            sources: [
                LocalizedSource(values: locale),
                LocalizedSource(values: english),
            ],
            serverSkillNamesByID: server
        )
    }

    func testSkillNameOrder() {
        let table = skillTable(
            locale: [5: SkillInfo(skillName: "Golpe Fulminante")],
            english: [5: SkillInfo(skillName: "Bash"), 28: SkillInfo(skillName: "Heal")],
            server: [5: "Bash (server)", 28: "Heal (server)", 360: "Fury"]
        )
        XCTAssertEqual(table.localizedSkillName(forSkillID: 5), "Golpe Fulminante")
        XCTAssertEqual(table.localizedSkillName(forSkillID: 28), "Heal")
        XCTAssertEqual(table.localizedSkillName(forSkillID: 360), "Fury")
        XCTAssertNil(table.localizedSkillName(forSkillID: 99_999))
    }

    func testSkillDescriptionFallsBackToEnglishOnly() {
        let table = skillTable(
            locale: [5: SkillInfo(skillDescription: "Bash\r\nMax Lv : 10")],
            english: [28: SkillInfo(skillDescription: "Heal\r\nMax Lv : 10")],
            server: [360: "Fury"]
        )
        XCTAssertEqual(table.localizedSkillDescription(forSkillID: 5), "Bash\r\nMax Lv : 10")
        XCTAssertEqual(table.localizedSkillDescription(forSkillID: 28), "Heal\r\nMax Lv : 10")
        XCTAssertNil(table.localizedSkillDescription(forSkillID: 360))
    }

    func testKoreanSkillNameInAnotherLocaleFallsThrough() {
        let table = skillTable(
            locale: [559: SkillInfo(skillName: "Å×ÀÌ¹Ö ¸¶½ºÅÍ")],
            english: [559: SkillInfo(skillName: "Taming Master")]
        )
        XCTAssertEqual(table.localizedSkillName(forSkillID: 559), "Taming Master")
    }

    // MARK: - Monsters

    func testMonsterNameOrder() {
        let table = MonsterNameTable(
            sources: [LocalizedSource(values: [1002: "波利"])],
            serverMonsterNamesByID: [1002: "Poring", 1113: "Drops"]
        )
        XCTAssertEqual(table.localizedMonsterName(forMonsterID: 1002), "波利")
        XCTAssertEqual(table.localizedMonsterName(forMonsterID: 1113), "Drops")
        XCTAssertNil(table.localizedMonsterName(forMonsterID: 99_999))
    }

    // MARK: - Maps

    func testMapNameFallsBackToEnglish() {
        let table = MapInfoTable(
            sources: [
                LocalizedSource(values: ["prontera": MapInfo(displayName: "Prontera")]),
                LocalizedSource(values: [
                    "prontera": MapInfo(displayName: "Prontera (en)"),
                    "prt_fild08": MapInfo(displayName: "Prontera Field", signMainTitle: "Prontera Field"),
                ]),
            ]
        )
        XCTAssertEqual(table.localizedMapName(forMapName: "prontera"), "Prontera")
        XCTAssertEqual(table.localizedMapName(forMapName: "prt_fild08"), "Prontera Field")
        XCTAssertEqual(table.localizedMapSignMainTitle(forMapName: "prt_fild08"), "Prontera Field")
        XCTAssertNil(table.localizedMapName(forMapName: "gef_fild12"))
    }
}
