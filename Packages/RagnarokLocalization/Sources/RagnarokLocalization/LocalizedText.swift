//
//  LocalizedText.swift
//  RagnarokLocalization
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// Checks on the strings of a localization table.
///
/// The tables are built from the clients of several servers. Where a server had no translation for an entry, the
/// table kept the Korean text of the kRO client, either as Hangul or as its CP949 or UTF-8 bytes read as Latin-1
/// (`¸¶·ÂÀÇ º°` for `마력의 별`). A player who reads another language gets nothing from that entry, so a lookup
/// treats it as missing and moves on to the next source.
enum LocalizedText {

    /// The localization whose tables are meant to hold Korean text.
    static let koreanLocalization = "ko"

    /// The localization that every lookup falls back to.
    static let englishLocalization = "en"

    /// Returns `text` when it is worth showing to a reader of the table's language, else `nil`.
    static func usable(_ text: String?, allowsKorean: Bool) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }
        if !allowsKorean && isUntranslatedKorean(text) {
            return nil
        }
        return text
    }

    /// True when most of the letters of `text` are Korean, as Hangul or as CP949 or UTF-8 bytes read as Latin-1.
    static func isUntranslatedKorean(_ text: String) -> Bool {
        var hangulCount = 0
        var letterCount = 0
        var highCount = 0
        var nonSpaceCount = 0
        var isLatin1 = true
        var bytes: [UInt8] = []

        for scalar in text.unicodeScalars {
            if scalar.value > 0xFF {
                isLatin1 = false
            } else {
                bytes.append(UInt8(scalar.value))
            }

            if scalar.properties.isWhitespace {
                continue
            }

            nonSpaceCount += 1
            if isHangul(scalar) {
                hangulCount += 1
            }
            if scalar.properties.isAlphabetic {
                letterCount += 1
            }
            if scalar.value >= 0x80 && scalar.value <= 0xFF {
                highCount += 1
            }
        }

        if hangulCount > 0 && hangulCount * 2 >= letterCount {
            return true
        }

        // Two or more high bytes that are most of the text, which read as Hangul under CP949 or UTF-8.
        guard isLatin1, highCount >= 2, highCount * 2 >= nonSpaceCount else {
            return false
        }
        return [cp949, .utf8].contains { encoding in
            String(bytes: bytes, encoding: encoding).map(isMostlyHangul) ?? false
        }
    }

    /// True when at least two characters are Hangul and they are most of the characters outside ASCII.
    private static func isMostlyHangul(_ text: String) -> Bool {
        let hangulCount = text.unicodeScalars.filter(isHangul).count
        let nonASCIICount = text.unicodeScalars.filter { $0.value > 0x7F }.count
        return hangulCount >= 2 && hangulCount * 5 >= nonASCIICount * 4
    }

    /// CP949, the encoding of the kRO client files.
    private static let cp949 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
    )

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F:
            true
        default:
            false
        }
    }
}
