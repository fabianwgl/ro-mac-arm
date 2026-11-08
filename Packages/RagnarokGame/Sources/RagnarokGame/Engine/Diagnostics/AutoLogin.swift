//
//  AutoLogin.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

// Automation for the performance runs (scripts/perf-run.sh). It drives the same GameSession calls the
// login, character select and map screens use, so no person has to click. It is compiled only into Debug
// builds, or into a build made with the RO_AUTOMATION compilation condition. A normal Release build does
// not contain it.
#if DEBUG || RO_AUTOMATION

import Foundation
import RagnarokModels

#if canImport(AppKit)
import AppKit
#endif

/// Environment (all read once at launch):
/// - `RO_AUTOLOGIN_USER`, `RO_AUTOLOGIN_PASS`: account. Automation is off unless the user is set.
///   The password is never logged.
/// - `RO_AUTOLOGIN_SERVER`: `host[:port]` of the login server. Default: the address saved in settings.
/// - `RO_AUTOLOGIN_CHARSERVER`: char server name or 0-based index when the login server lists several. Default: first.
/// - `RO_AUTOLOGIN_CHAR`: character name or slot number. Default: slot 0.
/// - `RO_AUTOLOGIN_CMD`: chat lines sent once the map is loaded, separated by `;` (for example `@warp geffen`).
///   `commandsDone` is marked after the last command and the map that follows it has loaded.
/// - `RO_AUTOLOGIN_LOOP`: chat lines sent over and over, one every `RO_AUTOLOGIN_LOOP_MS` (default 250), starting after
///   `commandsDone`. Use it to keep many effects on screen (for example `@effect 89;@effect 92;@effect 113`).
/// - `RO_AUTOLOGIN_FULLSCREEN=1`: put the game window in full screen once the map is loaded.
@MainActor
public enum AutoLogin {
    struct Settings: CustomStringConvertible {
        var user: String
        var password: String
        var server: String?
        var charServer: String?
        var character: String?
        var commands: [String]
        var loop: [String]
        var loopIntervalMs: Int
        var fullscreen: Bool

        // The password stays out of every description, log line and interpolation.
        var description: String {
            "AutoLogin(user: \(user), server: \(server ?? "default"), charServer: \(charServer ?? "first"), character: \(character ?? "slot 0"), commands: \(commands.count))"
        }
    }

    private static let settings: Settings? = {
        let environment = ProcessInfo.processInfo.environment
        guard let user = environment["RO_AUTOLOGIN_USER"], !user.isEmpty else {
            return nil
        }
        return Settings(
            user: user,
            password: environment["RO_AUTOLOGIN_PASS"] ?? "",
            server: environment["RO_AUTOLOGIN_SERVER"].flatMap { $0.isEmpty ? nil : $0 },
            charServer: environment["RO_AUTOLOGIN_CHARSERVER"].flatMap { $0.isEmpty ? nil : $0 },
            character: environment["RO_AUTOLOGIN_CHAR"].flatMap { $0.isEmpty ? nil : $0 },
            commands: chatLines(environment["RO_AUTOLOGIN_CMD"]),
            loop: chatLines(environment["RO_AUTOLOGIN_LOOP"]),
            loopIntervalMs: environment["RO_AUTOLOGIN_LOOP_MS"].flatMap(Int.init) ?? 250,
            fullscreen: environment["RO_AUTOLOGIN_FULLSCREEN"] == "1"
        )
    }()

    private static var task: Task<Void, Never>?

    private static func chatLines(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The configuration to open the game window with, or `nil` when automation is off.
    /// The launcher calls this instead of waiting for the Play button.
    public static func launchConfiguration(defaultAddress: String, defaultPort: UInt16) -> GameSession.Configuration? {
        guard let settings else {
            return nil
        }
        var address = defaultAddress
        var port = defaultPort
        if let server = settings.server {
            let parts = server.split(separator: ":", maxSplits: 1).map(String.init)
            address = parts[0]
            if parts.count > 1, let parsedPort = UInt16(parts[1]) {
                port = parsedPort
            }
        }
        logger.info("\(settings)")
        return GameSession.Configuration(serverAddress: address, serverPort: port)
    }

    /// Starts driving `gameSession` through login, character select and the map. Runs once per process.
    static func attach(to gameSession: GameSession) {
        guard let settings, task == nil else {
            return
        }
        PerfProbe.mark("autologinStarted")

        task = Task { @MainActor [weak gameSession] in
            var sentLogin = false
            var selectedCharServer = false
            var selectedCharacter = false
            var markedLoading = false
            var markedLoaded = false
            var ranCommands = false

            while !Task.isCancelled {
                guard let gameSession else {
                    return
                }

                switch gameSession.stage {
                case .login(let phase):
                    switch phase {
                    case .login:
                        if sentLogin {
                            fail("returned to the login screen after sending the login: \(gameSession.errorMessages.map(\.content))")
                            return
                        }
                        sentLogin = true
                        PerfProbe.mark("loginSent")
                        gameSession.login(username: settings.user, password: settings.password)
                    case .charServerList(let charServers):
                        guard !selectedCharServer else {
                            break
                        }
                        selectedCharServer = true
                        guard let charServer = pickCharServer(settings.charServer, from: charServers) else {
                            fail("no char server matches \(settings.charServer ?? "first")")
                            return
                        }
                        gameSession.selectCharServer(charServer)
                    case .characterSelect(let characters):
                        if selectedCharacter {
                            fail("returned to character select after choosing: \(gameSession.errorMessages.map(\.content))")
                            return
                        }
                        PerfProbe.mark("characterSelectShown")
                        guard let character = pickCharacter(settings.character, from: characters) else {
                            fail("no character matches \(settings.character ?? "slot 0") among \(characters.map(\.name))")
                            return
                        }
                        selectedCharacter = true
                        gameSession.selectedCharacterSlot = character.charNum
                        gameSession.selectCharacter(slot: character.charNum)
                    case .pincode, .characterMake:
                        fail("login needs a PIN or a new character, which automation does not handle")
                        return
                    case .loggingIn, .connectingCharServer, .waitingForMapServer:
                        break
                    }
                case .play(let playSession):
                    PerfProbe.mark("playStage")
                    switch playSession.mapPhase {
                    case .connecting:
                        break
                    case .loading:
                        if !markedLoading {
                            markedLoading = true
                            PerfProbe.mark("mapLoading")
                        }
                    case .loaded:
                        if !markedLoaded {
                            markedLoaded = true
                            PerfProbe.mark("mapLoaded")
                            if settings.fullscreen {
                                enterFullscreen()
                            }
                        }
                        if !ranCommands {
                            ranCommands = true
                            let current: @MainActor () -> PlaySession? = { [weak gameSession] in gameSession?.playSession }
                            Task { @MainActor in
                                await run(settings.commands, current: current)
                                await loop(settings.loop, intervalMs: settings.loopIntervalMs, current: current)
                            }
                            // Everything after the first loaded map is handled by the task above.
                            return
                        }
                    }
                }

                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    // MARK: - Steps

    /// Sends each command as a chat line, one every 700 ms, then waits for the map to be loaded again
    /// (a warp reloads it) and marks `commandsDone`.
    private static func run(_ commands: [String], current: @MainActor () -> PlaySession?) async {
        guard !commands.isEmpty else {
            PerfProbe.mark("commandsDone")
            return
        }
        try? await Task.sleep(for: .seconds(2))
        for command in commands {
            guard let playSession = current() else {
                return
            }
            logger.info("AutoLogin command: \(command)")
            playSession.sendMessage(command)
            try? await Task.sleep(for: .milliseconds(700))
        }

        // Give a warp time to start loading, then wait until the map is loaded again.
        try? await Task.sleep(for: .seconds(2))
        while let playSession = current() {
            if case .loaded = playSession.mapPhase {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        PerfProbe.mark("commandsDone")
    }

    /// Sends `lines` in turn, one every `intervalMs`, until the session is gone.
    private static func loop(_ lines: [String], intervalMs: Int, current: @MainActor () -> PlaySession?) async {
        guard !lines.isEmpty else {
            return
        }
        var index = 0
        while let playSession = current(), !Task.isCancelled {
            playSession.sendMessage(lines[index % lines.count])
            index += 1
            try? await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    private static func pickCharServer(_ selector: String?, from charServers: [CharServerInfo]) -> CharServerInfo? {
        guard let selector else {
            return charServers.first
        }
        if let index = Int(selector), charServers.indices.contains(index) {
            return charServers[index]
        }
        return charServers.first { $0.name == selector }
    }

    private static func pickCharacter(_ selector: String?, from characters: [CharacterInfo]) -> CharacterInfo? {
        guard let selector else {
            return characters.first { $0.charNum == 0 } ?? characters.first
        }
        if let slot = Int(selector) {
            return characters.first { $0.charNum == slot }
        }
        return characters.first { $0.name == selector }
    }

    private static func enterFullscreen() {
        #if canImport(AppKit)
        // The game window is titled "Game" (WindowGroup); the launcher is not the key window when started from a shell.
        guard let window = NSApp.windows.first(where: { $0.title == "Game" }) ?? NSApp.keyWindow,
              !window.styleMask.contains(.fullScreen) else {
            return
        }
        window.toggleFullScreen(nil)
        #endif
    }

    private static func fail(_ reason: String) {
        logger.error("AutoLogin stopped: \(reason)")
        PerfProbe.mark("autologinFailed")
    }
}

#endif
