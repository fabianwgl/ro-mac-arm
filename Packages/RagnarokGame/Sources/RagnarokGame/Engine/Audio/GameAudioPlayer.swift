//
//  GameAudioPlayer.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/5/4.
//

import AVFAudio
import Foundation
import Observation
import RagnarokCore
import RagnarokResources

@MainActor
final class GameAudioPlayer {
    private let resourceManager: ResourceManager
    private let preferences: GamePreferences

    private var bgmName: String?
    private var bgmPlayer: AVAudioPlayer?

    private let soundEffectEngine: GameAudioEngine
    private let soundEffectCache: GameAudioCache

    private var soundEffectTasks: [UUID : Task<Void, Never>] = [:]

    init(resourceManager: ResourceManager, preferences: GamePreferences) {
        self.resourceManager = resourceManager
        self.preferences = preferences

        self.soundEffectEngine = GameAudioEngine()
        self.soundEffectCache = GameAudioCache(resourceManager: resourceManager)

        #if !os(macOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.warning("Failed to configure game audio playback: \(error, privacy: .public)")
        }
        #endif

        observePreferences()
        applyPreferences()
    }

    func setListenerPosition(_ position: SIMD3<Float>) {
        soundEffectEngine.setListenerPosition(position)
    }

    // MARK: - BGM

    func playLoginBGM() async {
        await playBGM(named: "01.mp3")
    }

    func playBGM(forMapName mapName: String) async {
        let mp3NameTable = await resourceManager.mp3NameTable()
        guard let mp3Name = mp3NameTable.mp3Name(forMapName: mapName) else {
            return
        }

        await playBGM(named: mp3Name)
    }

    private func playBGM(named mp3Name: String) async {
        guard bgmName != mp3Name else {
            return
        }

        stopBGM()
        bgmName = mp3Name

        let bgmPath = ResourcePath(components: ["BGM", mp3Name])
        let bgmData = try? await resourceManager.contentsOfResource(at: bgmPath)

        guard bgmName == mp3Name else {
            return
        }

        guard let bgmData, let player = try? AVAudioPlayer(data: bgmData) else {
            bgmName = nil
            return
        }

        bgmPlayer = player
        bgmPlayer?.numberOfLoops = -1
        bgmPlayer?.volume = bgmVolume
        bgmPlayer?.play()
    }

    /// Applies the preferences to the playing BGM and to the sound effect mixer.
    private func applyPreferences() {
        bgmPlayer?.volume = bgmVolume
        soundEffectEngine.volume = preferences.isSoundEffectEnabled ? preferences.soundEffectVolume : 0
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.isBGMEnabled
            _ = preferences.bgmVolume
            _ = preferences.isSoundEffectEnabled
            _ = preferences.soundEffectVolume
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.observePreferences()
                self.applyPreferences()
            }
        }
    }

    private var bgmVolume: Float {
        preferences.isBGMEnabled ? preferences.bgmVolume : 0
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        bgmName = nil
    }

    // MARK: - Sound Effect

    func playButtonSoundEffect() {
        playSoundEffect(named: K2L("버튼소리.wav"))
    }

    func playSoundEffect(named soundName: String, from source: GameAudio.Source? = nil, after delay: Duration = .zero) {
        let playbackID = UUID()

        soundEffectTasks[playbackID] = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self else {
                return
            }

            defer {
                soundEffectTasks[playbackID] = nil
            }

            if Task.isCancelled {
                return
            }

            guard let soundEffect = await soundEffectCache.soundEffect(forSoundName: soundName) else {
                return
            }

            if Task.isCancelled {
                return
            }

            soundEffectEngine.play(soundEffect, from: source)
        }
    }

    func stopSoundEffects() {
        for task in soundEffectTasks.values {
            task.cancel()
        }
        soundEffectTasks.removeAll()

        soundEffectEngine.stop()
        soundEffectCache.removeAll()
    }
}
