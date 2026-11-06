//
//  GamePreferences.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation

@MainActor
@Observable
public final class GamePreferences {
    /// The zoom limits the map camera already uses.
    public static let zoomRange: ClosedRange<Float> = 3...120

    private static let defaultBGMVolume: Float = 0.5
    private static let defaultSoundEffectVolume: Float = 0.5

    #if os(visionOS)
    private static let initialZoom: Float = 15
    #else
    private static let initialZoom: Float = 100
    #endif

    private enum Key: String {
        case isBGMEnabled
        case bgmVolume
        case isSoundEffectEnabled
        case soundEffectVolume
        case showsNames
        case showsMissText
        case effectsEnabled
        case defaultZoom

        var name: String {
            "game.preferences.\(rawValue)"
        }
    }

    @ObservationIgnored private let userDefaults: UserDefaults

    public var isBGMEnabled: Bool {
        didSet {
            userDefaults.set(isBGMEnabled, forKey: Key.isBGMEnabled.name)
        }
    }

    public var bgmVolume: Float {
        didSet {
            userDefaults.set(bgmVolume, forKey: Key.bgmVolume.name)
        }
    }

    public var isSoundEffectEnabled: Bool {
        didSet {
            userDefaults.set(isSoundEffectEnabled, forKey: Key.isSoundEffectEnabled.name)
        }
    }

    public var soundEffectVolume: Float {
        didSet {
            userDefaults.set(soundEffectVolume, forKey: Key.soundEffectVolume.name)
        }
    }

    public var showsNames: Bool {
        didSet {
            userDefaults.set(showsNames, forKey: Key.showsNames.name)
        }
    }

    public var showsMissText: Bool {
        didSet {
            userDefaults.set(showsMissText, forKey: Key.showsMissText.name)
        }
    }

    public var effectsEnabled: Bool {
        didSet {
            userDefaults.set(effectsEnabled, forKey: Key.effectsEnabled.name)
        }
    }

    public var defaultZoom: Float {
        didSet {
            userDefaults.set(defaultZoom, forKey: Key.defaultZoom.name)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        isBGMEnabled = Self.bool(from: userDefaults, for: .isBGMEnabled, default: true)
        bgmVolume = Self.float(
            from: userDefaults,
            for: .bgmVolume,
            default: Self.defaultBGMVolume,
            range: 0...1
        )
        isSoundEffectEnabled = Self.bool(from: userDefaults, for: .isSoundEffectEnabled, default: true)
        soundEffectVolume = Self.float(
            from: userDefaults,
            for: .soundEffectVolume,
            default: Self.defaultSoundEffectVolume,
            range: 0...1
        )
        showsNames = Self.bool(from: userDefaults, for: .showsNames, default: true)
        showsMissText = Self.bool(from: userDefaults, for: .showsMissText, default: true)
        effectsEnabled = Self.bool(from: userDefaults, for: .effectsEnabled, default: true)
        defaultZoom = Self.float(
            from: userDefaults,
            for: .defaultZoom,
            default: Self.initialZoom,
            range: Self.zoomRange
        )
    }

    public func resetToDefaults() {
        isBGMEnabled = true
        bgmVolume = Self.defaultBGMVolume
        isSoundEffectEnabled = true
        soundEffectVolume = Self.defaultSoundEffectVolume
        showsNames = true
        showsMissText = true
        effectsEnabled = true
        defaultZoom = Self.initialZoom
    }

    private static func bool(from userDefaults: UserDefaults, for key: Key, default defaultValue: Bool) -> Bool {
        guard userDefaults.object(forKey: key.name) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key.name)
    }

    private static func float(
        from userDefaults: UserDefaults,
        for key: Key,
        default defaultValue: Float,
        range: ClosedRange<Float>
    ) -> Float {
        guard userDefaults.object(forKey: key.name) != nil else {
            return defaultValue
        }
        let value = userDefaults.float(forKey: key.name)
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
