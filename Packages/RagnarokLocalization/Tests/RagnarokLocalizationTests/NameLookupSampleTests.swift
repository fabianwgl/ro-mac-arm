//
//  NameLookupSampleTests.swift
//  RagnarokLocalizationTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import XCTest
@testable import RagnarokLocalization

/// The names a player sees for the ids the target server hands out, from the tables that ship with the package.
/// `docs/port/localization.md` lists the same samples.
final class NameLookupSampleTests: XCTestCase {
    let english = Locale(identifier: "en_PT")
    let korean = Locale(identifier: "ko_KR")
    let portuguese = Locale(identifier: "pt_PT")
    let finnish = Locale(identifier: "fi_FI")

    // MARK: - Items

    func testEnglishItemNames() {
        let table = ItemInfoTable(locale: english)
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Red Potion")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1201), "Knife")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 2301), "Cotton Shirt")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 4001), "Poring Card")
    }

    func testEnglishUnidentifiedItemNames() {
        let table = ItemInfoTable(locale: english)
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: false), "Dagger")
        XCTAssertEqual(table.localizedItemName(forItemID: 2301, isIdentified: false), "Armor")
        XCTAssertEqual(table.localizedItemName(forItemID: 4001, isIdentified: false), "Card")
        XCTAssertEqual(table.localizedItemName(forItemID: 501, isIdentified: false), "Red Potion")
        XCTAssertTrue(table.localizedItemDescription(forItemID: 1201, isIdentified: false)?.contains("appraisal") == true)
    }

    func testItemMissingFromTheEnglishTableGetsTheServerName() {
        let table = ItemInfoTable(locale: english)
        XCTAssertNil(table.sources[0].values[1190])
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "Claymore")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 542), "Festival Cookie")
    }

    func testUnsupportedLocaleReadsEnglish() {
        let table = ItemInfoTable(locale: finnish)
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Red Potion")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "Claymore")
    }

    func testPortugueseItemNamesNeverShowKorean() {
        let table = ItemInfoTable(locale: portuguese)
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "Poção Vermelha")
        // The pt-BR table holds `Å©·¹ÀÌ¸ð¾î` here.
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "Claymore")
    }

    func testKoreanLocaleKeepsKoreanNames() {
        let table = ItemInfoTable(locale: korean)
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 501), "빨간포션")
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 1190), "크레이모어")
        XCTAssertEqual(table.localizedItemName(forItemID: 1201, isIdentified: false), "단검")
        // Not in the Korean table: the server's English name.
        XCTAssertEqual(table.localizedIdentifiedItemName(forItemID: 542), "Festival Cookie")
    }

    func testNoEnglishItemNameIsKorean() {
        let table = ItemInfoTable(locale: english)
        for itemID in table.sources[0].values.keys {
            let name = table.localizedIdentifiedItemName(forItemID: itemID)
            XCTAssertFalse(name.map(LocalizedText.isUntranslatedKorean) ?? false, "item \(itemID): \(name ?? "")")
        }
    }

    // MARK: - Skills

    func testEnglishSkillNames() {
        let table = SkillInfoTable(locale: english)
        XCTAssertEqual(table.localizedSkillName(forSkillID: 1), "Basic Skill")      // NV_BASIC
        XCTAssertEqual(table.localizedSkillName(forSkillID: 5), "Bash")              // SM_BASH
        XCTAssertEqual(table.localizedSkillName(forSkillID: 18), "Fire Wall")        // MG_FIREWALL
    }

    func testSkillMissingFromTheEnglishTableGetsTheServerName() {
        let table = SkillInfoTable(locale: english)
        XCTAssertNil(table.sources[0].values[360])
        XCTAssertEqual(table.localizedSkillName(forSkillID: 360), "Fury")            // LK_FURY
        XCTAssertNil(table.localizedSkillDescription(forSkillID: 360))
    }

    func testKoreanSkillNamesInOtherTablesFallThroughToTheServerName() {
        // Skill 2543: the de table holds `¼öÈ£ÀÇ ºû` (CP949 as Latin-1) and the en table holds the same text as UTF-8
        // as Latin-1. Neither is shown; the server's name is.
        XCTAssertEqual(SkillInfoTable(locale: Locale(identifier: "de_DE")).localizedSkillName(forSkillID: 2543), "Ray of Protection")
        XCTAssertEqual(SkillInfoTable(locale: english).localizedSkillName(forSkillID: 2543), "Ray of Protection")
        // Skill 559 is in no server database, so a reader sees nothing instead of garbage.
        XCTAssertNil(SkillInfoTable(locale: english).localizedSkillName(forSkillID: 559))
    }

    // MARK: - Monsters

    func testEnglishMonsterNames() {
        let table = MonsterNameTable(locale: english)
        XCTAssertEqual(table.localizedMonsterName(forMonsterID: 1002), "Poring")
        XCTAssertEqual(table.localizedMonsterName(forMonsterID: 1113), "Drops")
    }

    func testChineseMonsterNamesKeepTheirTable() {
        let table = MonsterNameTable(locale: Locale(languageCode: .chinese, script: .hanSimplified))
        XCTAssertEqual(table.localizedMonsterName(forMonsterID: 1002), "波利")
    }

    // MARK: - Maps

    func testEnglishMapNames() {
        let table = MapInfoTable(locale: english)
        XCTAssertEqual(table.localizedMapName(forMapName: "prt_fild08"), "Prontera Field")
        XCTAssertNil(table.localizedMapName(forMapName: "gef_fild12"))
    }

    // MARK: - Server names

    func testServerNamesAreBundled() {
        let names = ServerNameTable.shared
        XCTAssertGreaterThan(names.itemNamesByID.count, 29_000)
        XCTAssertGreaterThan(names.skillNamesByID.count, 1_600)
        XCTAssertGreaterThan(names.monsterNamesByID.count, 2_600)
        XCTAssertEqual(names.itemNamesByID[501], "Red Potion")
        XCTAssertEqual(names.skillNamesByID[5], "Bash")
        XCTAssertEqual(names.monsterNamesByID[1002], "Poring")
    }
}
