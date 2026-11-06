import Foundation
import RagnarokConstants
@testable import RagnarokGame
import RagnarokModels
import RagnarokPackets
import RagnarokResources
import simd

/// Drives the real `GameSession` headlessly: login, char server, character create or select, map server, then
/// walk, chat and attack through the same `MapScene` and `PlaySession` entry points the UI uses.
@MainActor
final class ProbeRunner {
    enum Outcome {
        case completed
        case disconnected(String)
        case failed(String)
        case stopped
    }

    let options: Options
    let stats: ProbeStats
    let tap: PacketTap?
    let resourceManager: ResourceManager

    private(set) var stopRequested = false
    private var mapEntryDate: Date?
    private var chatCounter = 0
    private var distinctCells: Set<SIMD2<Int>> = []
    private var routeLastOrigin: SIMD2<Int>?
    private var routeStall = 0

    init(options: Options, stats: ProbeStats, tap: PacketTap?, resourceManager: ResourceManager) {
        self.options = options
        self.stats = stats
        self.tap = tap
        self.resourceManager = resourceManager
    }

    func requestStop() {
        stopRequested = true
    }

    // MARK: - Entry points

    func run() async -> Bool {
        if options.deleteTest {
            return await runDeleteTest()
        }
        return await runPlay()
    }

    private func runPlay() async -> Bool {
        var backoff: TimeInterval = 1
        var attempt = 0
        let giveUpDate = Date().addingTimeInterval(max(900, options.duration + 600))

        while !stopRequested {
            attempt += 1
            Log.line("session attempt \(attempt)")

            let outcome = await playOneSession(attempt: attempt)

            switch outcome {
            case .completed:
                return stats.reachedMap
            case .stopped:
                return stats.reachedMap
            case .disconnected(let reason), .failed(let reason):
                if case .disconnected = outcome {
                    stats.recordDisconnect(reason)
                } else {
                    stats.recordError("session failed: \(reason)")
                }

                guard options.reconnect else {
                    return false
                }
                if let mapEntryDate, Date().timeIntervalSince(mapEntryDate) >= options.duration {
                    return stats.reachedMap
                }
                if !stats.reachedMap, Date() > giveUpDate {
                    stats.recordError("giving up: map never reached")
                    return false
                }

                Log.line("reconnecting in \(Int(backoff)) s")
                if await sleepUnlessStopped(backoff) == false {
                    return stats.reachedMap
                }
                stats.recordReconnect()
                backoff = min(backoff * 2, options.maxReconnectBackoff)
            }

            // The backoff restarts from 1 s once a session got as far as the map.
            if stats.reachedMap, case .disconnected = outcome {
                backoff = 1
            }
        }
        return stats.reachedMap
    }

    // MARK: - One login to map session

    private func makeSession() -> (GameSession, Task<Void, Never>) {
        let gameSession = GameSession(resourceManager: resourceManager)
        let port = tap?.port(for: .login) ?? options.port
        let host = tap == nil ? options.host : "127.0.0.1"
        gameSession.start(GameSession.Configuration(serverAddress: host, serverPort: port))
        let watcher = Task { @MainActor in
            await self.watchStages(of: gameSession)
        }
        return (gameSession, watcher)
    }

    private func playOneSession(attempt: Int) async -> Outcome {
        let (gameSession, watcher) = makeSession()
        defer {
            watcher.cancel()
            gameSession.stop()
        }

        let sessionStart = Date()
        var session: [String: Any] = ["attempt": attempt]
        defer {
            session["seconds"] = (Date().timeIntervalSince(sessionStart) * 10).rounded() / 10
            stats.recordSession(session)
        }

        // Login.
        Log.line("login as \(options.user)")
        gameSession.login(username: options.user, password: options.pass)

        guard let characters = await waitForCharacterSelect(gameSession, what: "login and char server") else {
            session["result"] = "no character select"
            return failure(gameSession, default: "login did not reach character select")
        }
        Log.line("character select: \(characters.count) character(s): \(characters.map { "\($0.name)#\($0.charID)@slot\($0.charNum)" })")

        // Create or select.
        var character = characters.first(where: { $0.name.caseInsensitiveCompare(options.charName) == .orderedSame })
        if character == nil {
            Log.line("character \(options.charName) not found, creating")
            guard let created = await createCharacter(gameSession, name: options.charName) else {
                session["result"] = "character creation failed"
                return failure(gameSession, default: "character creation failed")
            }
            character = created
            stats.setCharacterCreated(created.name)
            Log.line("created \(created.name) charID \(created.charID) slot \(created.charNum)")
        }
        guard let character else {
            return .failed("no character")
        }

        Log.line("select character slot \(character.charNum)")
        gameSession.selectCharacter(slot: character.charNum)

        // Map server.
        guard await waitFor(timeout: options.stageTimeout, "play stage", { gameSession.playSession != nil || self.hasError(gameSession) }),
              let playSession = gameSession.playSession else {
            session["result"] = "no play stage"
            return failure(gameSession, default: "map server was not entered")
        }
        Log.line("map server entered, loading map")

        let loadStart = Date()
        var lastProgressLog = Date()
        let loaded = await waitFor(timeout: options.mapLoadTimeout, "map load", {
            if gameSession.mapScene != nil {
                return true
            }
            if gameSession.isDisconnected || self.hasError(gameSession) {
                return true
            }
            if case .loading(let progress) = playSession.mapPhase, Date().timeIntervalSince(lastProgressLog) > 5 {
                lastProgressLog = Date()
                Log.line("map loading \(Int(progress.fractionCompleted * 100)) %")
            }
            return false
        })

        guard loaded, let scene = gameSession.mapScene else {
            if gameSession.isDisconnected {
                session["result"] = "disconnected while loading"
                return .disconnected("disconnected while loading the map")
            }
            session["result"] = "map did not load"
            return failure(gameSession, default: "map did not finish loading within \(Int(options.mapLoadTimeout)) s (see os log subsystem RagnarokGame)")
        }

        let mapName = scene.mapName
        let loadSeconds = Date().timeIntervalSince(loadStart)
        Log.line("map \(mapName) loaded in \(String(format: "%.1f", loadSeconds)) s, player at \(scene.player.gridPosition), actor init sent")
        stats.setReachedMap(mapName: mapName)
        stats.recordStage("play.loaded")
        session["map"] = mapName
        session["mapLoadSeconds"] = (loadSeconds * 10).rounded() / 10

        if mapEntryDate == nil {
            mapEntryDate = Date()
        }
        let deadline = (mapEntryDate ?? Date()).addingTimeInterval(options.duration)

        // Gameplay loop.
        let enteredAt = Date()
        defer {
            stats.addTimeOnMap(Date().timeIntervalSince(enteredAt))
        }

        var nextWalk = Date().addingTimeInterval(1)
        var nextChat = Date().addingTimeInterval(5)
        var nextAttack = Date().addingTimeInterval(options.attackInterval)
        var nextStatus = Date().addingTimeInterval(30)
        var currentMapName = mapName
        var nextRespawn = Date()

        while Date() < deadline {
            if stopRequested {
                session["result"] = "stopped"
                return .stopped
            }
            if gameSession.isDisconnected {
                session["result"] = "disconnected on map"
                return .disconnected("map connection lost")
            }
            if gameSession.playSession == nil {
                session["result"] = "left play stage"
                return .disconnected("left the play stage (\(describe(gameSession.stage)))")
            }
            if let message = gameSession.errorMessages.first {
                gameSession.removeErrorMessage(message)
                stats.recordError("client error message: \(message.content)")
            }

            let now = Date()
            if now >= nextChat {
                nextChat = now.addingTimeInterval(options.chatInterval)
                chat(playSession: playSession)
            }

            // The scene changes when the server moves the player to another map. While it loads there is none.
            if let scene = gameSession.mapScene, let runtime = playSession.mapRuntime {
                if scene.mapName != currentMapName {
                    currentMapName = scene.mapName
                    stats.setReachedMap(mapName: scene.mapName)
                    Log.line("now on map \(scene.mapName), player at \(scene.player.gridPosition)")
                }

                // What the app's render loop calls every frame, without drawing: advances movement and
                // arrival actions, loads sprites for objects in view, and syncs the render resources.
                runtime.update(at: .now, renderTime: ProcessInfo.processInfo.systemUptime)

                if now >= nextWalk {
                    nextWalk = now.addingTimeInterval(options.walkInterval)
                    walk(scene: scene)
                }
                if now >= nextAttack {
                    nextAttack = now.addingTimeInterval(options.attackInterval)
                    if attack(scene: scene, playSession: playSession) {
                        // Let the attack run before the next walk request cancels it.
                        nextWalk = max(nextWalk, now.addingTimeInterval(options.attackInterval - 1))
                    }
                }

                // Dead: ask to go back to the save point, as the respawn button does.
                if playSession.playerStatus.hp <= 0 {
                    if now >= nextRespawn {
                        nextRespawn = now.addingTimeInterval(10)
                        Log.line("player is dead (hp \(playSession.playerStatus.hp)), requesting respawn at the save point")
                        stats.addDeath()
                        playSession.returnToLastSavePoint()
                    }
                }
                if now >= nextStatus {
                    nextStatus = now.addingTimeInterval(30)
                    let remaining = Int(deadline.timeIntervalSince(now))
                    Log.line("status: pos \(scene.player.gridPosition), walks \(stats.walkRequestsSent), chats \(stats.chatLinesSent), attacks \(stats.attacksSent), monsters seen \(stats.monstersSeen.count), objects in view \(scene.objects.count - 1), \(remaining) s left")
                }
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        Log.line("duration reached, leaving map (distinct cells visited \(distinctCells.count))")
        stats.recordNote("distinct cells visited by the player: \(distinctCells.count)")
        session["result"] = "completed"
        return .completed
    }

    // MARK: - Map actions

    private func walk(scene: MapScene) {
        let origin = scene.player.gridPosition
        distinctCells.insert(origin)

        if scene.player.action.actionType == .sit {
            return
        }

        if let target = routeTarget(for: scene), origin != target {
            if navigate(scene: scene, from: origin, to: target) {
                return
            }
        }

        for _ in 0..<40 {
            let dx = Int.random(in: -6...6)
            let dy = Int.random(in: -6...6)
            if dx == 0 && dy == 0 {
                continue
            }
            let target = SIMD2(origin.x + dx, origin.y + dy)
            guard scene.mapGrid.contains(target), scene.mapGrid[target].isWalkable else {
                continue
            }
            guard scene.pathFinder.canRequestMove(from: origin, to: target) else {
                continue
            }

            Log.line("walk \(origin) -> \(target)")
            stats.recordPosition("t=\(String(format: "%.0f", stats.elapsed))s \(origin.x),\(origin.y) -> \(target.x),\(target.y)")
            // The same call a tap on the ground makes: selects the tile and sends CZ_REQUEST_MOVE.
            scene.handleInteraction(.ground(position: target))
            stats.addWalk()
            return
        }
        Log.line("walk: no reachable cell near \(origin)")
    }

    /// The cell of the `--route` entry for the current map, if there is one.
    private func routeTarget(for scene: MapScene) -> SIMD2<Int>? {
        let name = scene.mapName.replacingOccurrences(of: ".rsw", with: "")
        // A trailing number is ignored, so `iz_int` also matches the room copies `iz_int01` to `iz_int04`
        // that the server picks for new characters.
        let stop = options.route.first { stop in
            if name == stop.map {
                return true
            }
            let rest = name.dropFirst(stop.map.count)
            return name.hasPrefix(stop.map) && !rest.isEmpty && rest.allSatisfy(\.isNumber)
        }
        return stop.map { SIMD2($0.x, $0.y) }
    }

    /// Walks toward a far cell in requests the client accepts: the farthest cell of the path that
    /// `PathFinder.canRequestMove` allows, as repeated taps on the ground would.
    private func navigate(scene: MapScene, from origin: SIMD2<Int>, to target: SIMD2<Int>) -> Bool {
        let path = scene.pathFinder.findPath(from: origin, to: target)
        guard path.count > 1 else {
            Log.line("route: no path from \(origin) to \(target) on \(scene.mapName)")
            return false
        }

        // A request the server could not path leaves the player where he is. Ask for shorter hops after that,
        // and give up on the route for a while (random wandering) after four of them.
        routeStall = routeLastOrigin == origin ? routeStall + 1 : 0
        routeLastOrigin = origin
        if routeStall >= 4 {
            routeStall = 0
            Log.line("route: no progress from \(origin), wandering instead")
            return false
        }
        let longestHop = max(2, 12 - 3 * routeStall)

        for index in stride(from: min(path.count - 1, longestHop), through: 1, by: -1) {
            let step = path[index]
            if scene.pathFinder.canRequestMove(from: origin, to: step) {
                Log.line("route: \(scene.mapName) \(origin) -> \(step) on the way to \(target) (\(path.count - 1) cells left)")
                stats.recordPosition("t=\(String(format: "%.0f", stats.elapsed))s route \(origin.x),\(origin.y) -> \(step.x),\(step.y) toward \(target.x),\(target.y)")
                scene.handleInteraction(.ground(position: step))
                stats.addWalk()
                return true
            }
        }
        return false
    }

    private func chat(playSession: PlaySession) {
        chatCounter += 1
        let text = "probe hello \(chatCounter)"
        Log.line("chat: \(text)")
        playSession.sendMessage(text)
        stats.addChat()
    }

    @discardableResult
    private func attack(scene: MapScene, playSession: PlaySession) -> Bool {
        let origin = scene.player.gridPosition
        let monsters = scene.objects.values
            .filter { $0.type == .monster && !$0.isDead }
            .sorted { chebyshev($0.gridPosition, origin) < chebyshev($1.gridPosition, origin) }

        guard let target = monsters.first else {
            return false
        }

        Log.line("attack monster \(target.objectID) \(target.name) at \(target.gridPosition), distance \(chebyshev(target.gridPosition, origin)), hp \(playSession.playerStatus.hp)")
        // Walks into range and sends CZ_REQUEST_ACT (repeat), as the UI does for a tapped monster.
        scene.attackMonster(targetID: target.objectID)
        stats.addAttack()
        return true
    }

    private func chebyshev(_ a: SIMD2<Int>, _ b: SIMD2<Int>) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }

    // MARK: - Character create and delete

    private func createCharacter(_ gameSession: GameSession, name: String) async -> CharacterInfo? {
        let used = Set(gameSession.characters.map(\.charNum))
        guard let slot = (0..<max(gameSession.maxCharacterSlots, 1)).first(where: { !used.contains($0) }) else {
            stats.recordError("no free character slot")
            return nil
        }

        // Same values CharacterMakeView sets before the make button.
        var info = CharacterInfo()
        info.name = name
        info.job = 0
        info.head = 2
        info.headPalette = 0
        info.str = 5
        info.agi = 5
        info.vit = 5
        info.int = 5
        info.dex = 5
        info.luk = 5
        info.charNum = slot
        if let account = gameSession.account {
            info.sex = account.sex
        }

        gameSession.makeCharacter(slot: slot)
        gameSession.createCharacter(info)

        let before = gameSession.characters.count
        let created = await waitFor(timeout: 30, "character creation", {
            gameSession.characters.count > before || self.hasError(gameSession)
        })
        guard created, gameSession.characters.count > before else {
            return nil
        }
        return gameSession.characters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    }

    private func runDeleteTest() async -> Bool {
        let (gameSession, watcher) = makeSession()
        defer {
            watcher.cancel()
            gameSession.stop()
        }

        var result: [String: Any] = [:]

        Log.line("delete test: login as \(options.user)")
        gameSession.login(username: options.user, password: options.pass)
        guard let before = await waitForCharacterSelect(gameSession, what: "login and char server") else {
            result["passed"] = false
            result["reason"] = "login did not reach character select: \(gameSession.errorMessages.first?.content ?? "timeout")"
            stats.setDeleteTest(result)
            return false
        }
        result["charactersBefore"] = before.map(\.name)

        let name = "DelTest" + String((0..<5).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        Log.line("delete test: creating throwaway character \(name)")
        guard let created = await createCharacter(gameSession, name: name) else {
            result["passed"] = false
            result["reason"] = "creation failed: \(gameSession.errorMessages.first?.content ?? "timeout")"
            stats.setDeleteTest(result)
            return false
        }
        result["created"] = ["name": created.name, "charID": Int(created.charID), "slot": created.charNum]
        Log.line("delete test: created \(created.name) charID \(created.charID)")

        // Wait for the select stage again, as after HC_ACCEPT_MAKECHAR.
        _ = await waitFor(timeout: 10, "select stage after create", {
            if case .login(.characterSelect) = gameSession.stage { return true }
            return false
        })

        Log.line("delete test: deleting charID \(created.charID) (CH_DELETE_CHAR3_RESERVED then CH_DELETE_CHAR3)")
        gameSession.deleteCharacter(charID: created.charID)

        let removed = await waitFor(timeout: 30, "character deletion", {
            !gameSession.characters.contains(where: { $0.charID == created.charID }) || self.hasError(gameSession)
        })
        let removedLocally = removed && !gameSession.characters.contains(where: { $0.charID == created.charID })
        result["removedFromClientList"] = removedLocally
        if let message = gameSession.errorMessages.first {
            result["clientError"] = message.content
        }
        Log.line("delete test: client list no longer has the character: \(removedLocally)")

        // Confirm on the server with a fresh login.
        gameSession.exitSession()
        let (verify, verifyWatcher) = makeSession()
        defer {
            verifyWatcher.cancel()
            verify.stop()
        }
        verify.login(username: options.user, password: options.pass)
        guard let after = await waitForCharacterSelect(verify, what: "second login") else {
            result["passed"] = false
            result["reason"] = "second login did not reach character select"
            stats.setDeleteTest(result)
            return false
        }
        result["charactersAfterRelogin"] = after.map(\.name)
        let gone = !after.contains(where: { $0.charID == created.charID })
        result["goneAfterRelogin"] = gone
        result["passed"] = removedLocally && gone
        stats.setDeleteTest(result)
        Log.line("delete test: gone after fresh login: \(gone) -> \(removedLocally && gone ? "PASS" : "FAIL")")
        return removedLocally && gone
    }

    // MARK: - Waiting helpers

    private func hasError(_ gameSession: GameSession) -> Bool {
        !gameSession.errorMessages.isEmpty
    }

    private func failure(_ gameSession: GameSession, default message: String) -> Outcome {
        if let error = gameSession.errorMessages.first {
            return .failed("\(message): client error message \"\(error.content)\"")
        }
        return .failed(message)
    }

    private func waitForCharacterSelect(_ gameSession: GameSession, what: String) async -> [CharacterInfo]? {
        // With --pincode the server sends the char list first and the pincode state right after it,
        // so character select only counts once a pincode stage was answered and left again.
        var answeredPincode = false
        let reached = await waitFor(timeout: options.stageTimeout, what, {
            if let pincode = self.options.pincode, case .login(.pincode(let request)) = gameSession.stage {
                if !answeredPincode {
                    Log.line("pincode stage \(request): answering")
                    switch request {
                    case .enter: gameSession.submitPincode(pincode)
                    case .create: gameSession.submitNewPincode(pincode)
                    case .change: gameSession.changePincode(old: pincode, new: pincode)
                    }
                    answeredPincode = true
                    self.stats.recordNote("pincode \(request) answered")
                }
                return false
            }
            if case .login(.characterSelect) = gameSession.stage {
                return self.options.pincode == nil || answeredPincode
            }
            return self.hasError(gameSession)
        })
        guard reached, case .login(.characterSelect(let characters)) = gameSession.stage else {
            return nil
        }
        return characters
    }

    /// Polls `condition` every 100 ms. Returns false on timeout or when a stop was requested.
    private func waitFor(timeout: TimeInterval, _ what: String, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if stopRequested {
                return false
            }
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        stats.recordError("timeout after \(Int(timeout)) s waiting for \(what)")
        return false
    }

    private func sleepUnlessStopped(_ seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if stopRequested {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !stopRequested
    }

    // MARK: - Stage naming

    func describe(_ stage: GameStage) -> String {
        switch stage {
        case .login(.login): "login.login"
        case .login(.loggingIn): "login.loggingIn"
        case .login(.charServerList(let servers)): "login.charServerList(\(servers.count))"
        case .login(.connectingCharServer): "login.connectingCharServer"
        case .login(.characterSelect(let characters)): "login.characterSelect(\(characters.count))"
        case .login(.characterMake(let slot)): "login.characterMake(slot \(slot))"
        case .login(.waitingForMapServer(let slot)): "login.waitingForMapServer(slot \(slot))"
        case .login(.pincode(let request)): "login.pincode(\(request))"
        case .play(let playSession):
            switch playSession.mapPhase {
            case .connecting: "play.connecting"
            case .loading: "play.loading"
            case .loaded: "play.loaded"
            }
        }
    }

    /// Records stage changes of a session for the summary. Called from the main loop watcher.
    func watchStages(of gameSession: GameSession) async {
        while !Task.isCancelled {
            stats.recordStage(describe(gameSession.stage))
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
