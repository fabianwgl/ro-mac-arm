//
//  PincodeCipher.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

/// The second password (pincode) cipher used by the char server.
///
/// See `char_pincode_encrypt` and `char_pincode_decrypt` in rAthena `src/char/char.cpp`.
public enum PincodeCipher {
    public static let length = 4

    /// Build the substitution table for a seed.
    public static func permutation(seed: UInt32) -> [Int] {
        var table = Array(0..<10)
        var seed = seed
        for i in 1..<10 {
            seed = 0x881234 &+ seed &* 0x3498
            let position = Int(seed % UInt32(i + 1))
            if i != position {
                table.swapAt(i, position)
            }
        }
        return table
    }

    /// Encrypt a plain pin, nil unless it is exactly ``length`` ASCII digits.
    public static func encrypt(_ pin: String, seed: UInt32) -> String? {
        guard let digits = digits(of: pin) else {
            return nil
        }

        let table = permutation(seed: seed)
        var inverse = [Int](repeating: 0, count: 10)
        for (index, digit) in table.enumerated() {
            inverse[digit] = index
        }
        return digits.map { String(inverse[$0]) }.joined()
    }

    /// Decrypt a pin the way the server does, for tests and packet replay.
    public static func decrypt(_ pin: String, seed: UInt32) -> String? {
        guard let digits = digits(of: pin) else {
            return nil
        }

        let table = permutation(seed: seed)
        return digits.map { String(table[$0]) }.joined()
    }

    private static func digits(of pin: String) -> [Int]? {
        let digits = pin.compactMap { $0.wholeNumberValue }
        guard pin.utf8.count == length, digits.count == length, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return digits
    }
}
