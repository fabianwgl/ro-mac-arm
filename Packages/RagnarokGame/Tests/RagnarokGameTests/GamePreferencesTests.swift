//
//  GamePreferencesTests.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Testing
@testable import RagnarokGame

@MainActor
struct GamePreferencesTests {
    @Test func emptyStoreUsesDefaults() {
        let preferences = GamePreferences(userDefaults: makeUserDefaults())

        #expect(preferences.isBGMEnabled)
        #expect(preferences.bgmVolume == 0.5)
        #expect(preferences.isSoundEffectEnabled)
        #expect(preferences.soundEffectVolume == 0.5)
        #expect(preferences.showsNames)
        #expect(preferences.showsMissText)
        #expect(preferences.effectsEnabled)
        #expect(preferences.defaultZoom == 100)
    }

    @Test func changesLoadInANewInstance() {
        let defaults = makeUserDefaults()
        let preferences = GamePreferences(userDefaults: defaults)

        preferences.isBGMEnabled = false
        preferences.bgmVolume = 0.25
        preferences.isSoundEffectEnabled = false
        preferences.soundEffectVolume = 0.75
        preferences.showsNames = false
        preferences.showsMissText = false
        preferences.effectsEnabled = false
        preferences.defaultZoom = 42

        let reloaded = GamePreferences(userDefaults: defaults)

        #expect(reloaded.isBGMEnabled == false)
        #expect(reloaded.bgmVolume == 0.25)
        #expect(reloaded.isSoundEffectEnabled == false)
        #expect(reloaded.soundEffectVolume == 0.75)
        #expect(reloaded.showsNames == false)
        #expect(reloaded.showsMissText == false)
        #expect(reloaded.effectsEnabled == false)
        #expect(reloaded.defaultZoom == 42)
    }

    @Test func outOfRangeStoredValuesAreClamped() {
        let defaults = makeUserDefaults()

        defaults.set(-0.5, forKey: "game.preferences.bgmVolume")
        defaults.set(1.5, forKey: "game.preferences.soundEffectVolume")
        defaults.set(-10, forKey: "game.preferences.defaultZoom")

        let preferences = GamePreferences(userDefaults: defaults)

        #expect(preferences.bgmVolume == 0)
        #expect(preferences.soundEffectVolume == 1)
        #expect(preferences.defaultZoom == GamePreferences.zoomRange.lowerBound)

        defaults.set(500, forKey: "game.preferences.defaultZoom")

        let reloaded = GamePreferences(userDefaults: defaults)
        #expect(reloaded.defaultZoom == GamePreferences.zoomRange.upperBound)
    }

    @Test func resetToDefaultsRestoresAndPersistsDefaults() {
        let defaults = makeUserDefaults()
        let preferences = GamePreferences(userDefaults: defaults)

        preferences.isBGMEnabled = false
        preferences.bgmVolume = 0.1
        preferences.isSoundEffectEnabled = false
        preferences.soundEffectVolume = 0.9
        preferences.showsNames = false
        preferences.showsMissText = false
        preferences.effectsEnabled = false
        preferences.defaultZoom = 12

        preferences.resetToDefaults()

        let reloaded = GamePreferences(userDefaults: defaults)

        #expect(reloaded.isBGMEnabled)
        #expect(reloaded.bgmVolume == 0.5)
        #expect(reloaded.isSoundEffectEnabled)
        #expect(reloaded.soundEffectVolume == 0.5)
        #expect(reloaded.showsNames)
        #expect(reloaded.showsMissText)
        #expect(reloaded.effectsEnabled)
        #expect(reloaded.defaultZoom == 100)
    }

    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }
}
