//
//  LocalizedTextTests.swift
//  RagnarokLocalizationTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import XCTest
@testable import RagnarokLocalization

final class LocalizedTextTests: XCTestCase {
    func testHangulIsUntranslated() {
        XCTAssertTrue(LocalizedText.isUntranslatedKorean("마력의 별"))
        XCTAssertTrue(LocalizedText.isUntranslatedKorean("부스터 팩(30)"))
    }

    func testCP949ReadAsLatin1IsUntranslated() {
        // `마력의 별`, `크레이모어` and `Flee 증가` as the pt-BR and en tables carry them.
        XCTAssertTrue(LocalizedText.isUntranslatedKorean("¸¶·ÂÀÇ º°"))
        XCTAssertTrue(LocalizedText.isUntranslatedKorean("Å©·¹ÀÌ¸ð¾î"))
        XCTAssertTrue(LocalizedText.isUntranslatedKorean("¼ÒÈ¯±îÁö %02dÃÊ³²¾Ò½À´Ï´Ù."))
    }

    func testUTF8ReadAsLatin1IsUntranslated() {
        // The en table holds this for skill 559 (`Taming Master`).
        let utf8Bytes = Array("테이밍 마스터".utf8)
        let misread = String(String.UnicodeScalarView(utf8Bytes.map { Unicode.Scalar($0) }))
        XCTAssertTrue(LocalizedText.isUntranslatedKorean(misread))
    }

    func testTranslatedTextIsKept() {
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("Red Potion"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("Poción Roja"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("Máscara de Oxígeno"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("¡Adelante! ¡Adelante, padres!"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("リンゴ"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("苹果"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("Яблоко"))
        XCTAssertFalse(LocalizedText.isUntranslatedKorean(""))
    }

    func testEnglishWithKoreanGlossIsKept() {
        XCTAssertFalse(LocalizedText.isUntranslatedKorean("Poring Card (포링 카드)"))
    }

    func testUsableDropsEmptyTextAndKoreanOutsideTheKoreanTable() {
        XCTAssertNil(LocalizedText.usable(nil, allowsKorean: false))
        XCTAssertNil(LocalizedText.usable("", allowsKorean: true))
        XCTAssertNil(LocalizedText.usable("빨간포션", allowsKorean: false))
        XCTAssertEqual(LocalizedText.usable("빨간포션", allowsKorean: true), "빨간포션")
        XCTAssertEqual(LocalizedText.usable("Red Potion", allowsKorean: false), "Red Potion")
    }
}
