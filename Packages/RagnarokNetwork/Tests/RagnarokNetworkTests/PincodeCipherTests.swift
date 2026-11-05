//
//  PincodeCipherTests.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokNetwork

@Test func permutationMatchesServer() {
    #expect(PincodeCipher.permutation(seed: 4660) == [3, 8, 6, 2, 7, 1, 5, 0, 9, 4])
    #expect(PincodeCipher.permutation(seed: 0) == [3, 0, 6, 1, 9, 8, 4, 5, 2, 7])
    #expect(PincodeCipher.permutation(seed: 65534) == [5, 0, 9, 1, 7, 3, 4, 2, 6, 8])
}

@Test(arguments: [
    (UInt32(4660), "1357", "5064"),
    (UInt32(4660), "2580", "3617"),
    (UInt32(0), "0000", "1111"),
    (UInt32(65534), "9876", "2948"),
])
func encryptMatchesServer(seed: UInt32, pin: String, encrypted: String) {
    #expect(PincodeCipher.encrypt(pin, seed: seed) == encrypted)
    #expect(PincodeCipher.decrypt(encrypted, seed: seed) == pin)
}

@Test(arguments: [UInt32(0), 1, 4660, 65534])
func roundTripEveryPin(seed: UInt32) throws {
    for number in 0..<10000 {
        let pin = String(format: "%04d", number)
        let encrypted = try #require(PincodeCipher.encrypt(pin, seed: seed))
        #expect(PincodeCipher.decrypt(encrypted, seed: seed) == pin)
    }
}

@Test(arguments: ["123", "12345", "12a4", ""])
func rejectsInvalidInput(pin: String) {
    #expect(PincodeCipher.encrypt(pin, seed: 4660) == nil)
    #expect(PincodeCipher.decrypt(pin, seed: 4660) == nil)
}
