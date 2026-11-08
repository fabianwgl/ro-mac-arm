//
//  MapSceneView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/5/30.
//

import simd
import SwiftUI

struct MapSceneView: View {
    var runtime: MapSceneRuntime

    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif

    @Environment(PlaySession.self) private var playSession
    @Environment(KeyBindings.self) private var keyBindings

    @State private var screenWidth: CGFloat = 320
    @State private var actionBarHeight: CGFloat = 0
    @State private var presentedMenuItem: MenuItem?
    @State private var chatFocusRequest = 0
    /// Movement keys held down, by key code, with the screen direction each one pushes.
    @State private var heldMovementKeys: [UInt16: SIMD2<Float>] = [:]
    #if os(macOS)
    @State private var gamepad = GamepadInput()
    #endif

    var body: some View {
        ZStack {
            #if os(visionOS)
            Color.clear
                .onAppear {
                    Task {
                        await openImmersiveSpace(id: GameSession.immersiveSpaceID)
                    }
                }
                .onDisappear {
                    Task {
                        await dismissImmersiveSpace()
                    }
                }
            #elseif os(iOS)
            MapView(runtime: runtime, isWidescreen: isWidescreen)
            #else
            MapView(runtime: runtime)
            #endif
        }
        .overlay(alignment: .bottomLeading) {
            #if os(macOS)
            ChatBoxView(focusRequest: chatFocusRequest)
                .frame(width: 440)
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            if isWidescreen {
                actionBar
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .bottom) {
            if !isWidescreen {
                actionBar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, ChatBoxView.contentHeight(for: .compact) + 8)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                BasicInfoView(character: playSession.character, status: playSession.playerStatus)

                MenuView(hasUnreadMail: playSession.mail.mailbox.hasUnread) { item in
                    if item == presentedMenuItem {
                        presentedMenuItem = nil
                    } else if item == .attendance {
                        // The server decides: it opens the window with the current state, or refuses.
                        playSession.requestAttendanceWindow()
                    } else {
                        presentedMenuItem = item
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                MinimapView(scene: runtime.scene)

                StatusIconBarView(statusChanges: playSession.statusChanges)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .padding(.trailing, 16)
            .padding(.bottom, statusIconBarBottomPadding)
        }
        .ignoresSafeArea()
        .overlay {
            #if os(iOS)
            ChatBoxView()
                .frame(width: chatBoxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isWidescreen ? .bottomLeading : .bottom)
            #endif
        }
        .overlay(alignment: .center) {
            if let item = presentedMenuItem {
                switch item {
                case .status:
                    StatusView(status: playSession.playerStatus) {
                        presentedMenuItem = nil
                    }
                case .equipment:
                    EquipmentView {
                        presentedMenuItem = nil
                    }
                case .inventory:
                    InventoryView(inventory: playSession.inventory) {
                        presentedMenuItem = nil
                    }
                case .skill:
                    SkillListView(skillList: playSession.skillList) {
                        presentedMenuItem = nil
                    }
                case .party:
                    PartyView(party: playSession.social.party) {
                        presentedMenuItem = nil
                    }
                case .guild:
                    GuildView(guild: playSession.guildState.guild) {
                        presentedMenuItem = nil
                    }
                case .pet:
                    PetView(pet: playSession.companions.pet) {
                        presentedMenuItem = nil
                    }
                case .homunculus:
                    HomunculusView(homunculus: playSession.companions.homunculus) {
                        presentedMenuItem = nil
                    }
                case .friends:
                    FriendsView(friendList: playSession.social.friendList) {
                        presentedMenuItem = nil
                    }
                case .quest:
                    QuestLogView(questLog: playSession.questLog) {
                        presentedMenuItem = nil
                    }
                case .attendance:
                    AttendanceView(attendance: playSession.attendance) {
                        presentedMenuItem = nil
                    }
                case .achievement:
                    AchievementsView(achievements: playSession.achievements) {
                        presentedMenuItem = nil
                    }
                case .mail:
                    MailboxView(mailbox: playSession.mail.mailbox) {
                        presentedMenuItem = nil
                    }
                case .worldMap:
                    WorldMapView(currentMapName: runtime.scene.mapName) {
                        presentedMenuItem = nil
                    }
                case .options:
                    OptionsView(isPlayerDead: runtime.scene.state.isPlayerDead) {
                        presentedMenuItem = nil
                    }
                }
            }
        }
        .overlay(alignment: .center) {
            if let eggIndices = playSession.companions.petEggIndices {
                PetEggListView(inventory: playSession.inventory, eggIndices: eggIndices)
            }
        }
        .overlay(alignment: .center) {
            if let dialog = playSession.dialog {
                NPCDialogView(dialog: dialog)
            }
            if let warpList = playSession.warpList {
                WarpListView(warpList: warpList)
            }
            if let npcShop = playSession.npcShop {
                NPCShopView(shop: npcShop)
            }
            if playSession.dealSelectionNPCID != nil {
                NPCShopDealTypeView()
            }
            if let storage = playSession.storage {
                StorageView(storage: storage)
            }
            if let invitation = playSession.social.invitation {
                SocialInvitationView(invitation: invitation)
            }
            if let invitation = playSession.guildState.invitation {
                GuildInvitationView(invitation: invitation)
            }
            if playSession.mail.draft != nil {
                MailComposeView()
                    .offset(x: 24, y: 24)
            }
        }
        .onChange(of: runtime.scene.state.isPlayerDead) { _, newValue in
            if newValue {
                presentedMenuItem = .options
            } else if presentedMenuItem == .options {
                presentedMenuItem = nil
            }
        }
        .onChange(of: playSession.attendance.isPresentationRequested, initial: true) { _, isRequested in
            // The server opens the window at login, before this view exists, so the flag is consumed once.
            if isRequested {
                playSession.attendance.isPresentationRequested = false
                presentedMenuItem = .attendance
            }
        }
        .onChange(of: playSession.storage != nil) { _, isStorageOpen in
            if isStorageOpen {
                presentedMenuItem = nil
            }
        }
        .onChange(of: playSession.mail.openRequestCount) {
            presentedMenuItem = .mail
        }
        .onChange(of: playSession.mail.closeRequestCount) {
            if presentedMenuItem == .mail {
                presentedMenuItem = nil
            }
        }
        .ignoresSafeArea(.container)
        #if os(macOS)
        .background {
            KeyEventMonitor(handler: handleKeyEvent, onFocusLost: {
                // Releases of keys and controller input held now would never arrive.
                gamepad.isActive = false
                heldMovementKeys.removeAll()
                updateWalking()
            }, onFocusGained: {
                gamepad.isActive = true
            })
        }
        .onAppear {
            connectGamepad()
        }
        .onChange(of: ObjectIdentifier(runtime)) {
            connectGamepad()
        }
        .onDisappear {
            gamepad.stop()
            heldMovementKeys.removeAll()
            updateWalking()
        }
        #endif
        .onGeometryChange(for: CGFloat.self) { geometryProxy in
            geometryProxy.size.width + geometryProxy.safeAreaInsets.leading + geometryProxy.safeAreaInsets.trailing
        } action: { containerWidth in
            self.screenWidth = containerWidth
        }
    }

    private var actionBar: some View {
        ActionBarView(
            selectedTargetType: runtime.scene.state.selectedTargetType,
            onTargetAction: {
                runtime.scene.performTargetAction()
            },
            onSelectNextTarget: {
                runtime.selectNextTarget()
            },
            onDeselectTarget: {
                runtime.scene.selectTarget(nil)
            },
            onPickup: {
                runtime.scene.pickUpNearestItem()
            },
            onSit: {
                runtime.scene.toggleSit()
            },
            onShortcut: { shortcut in
                playSession.useShortcut(shortcut)
            }
        )
        .onGeometryChange(for: CGFloat.self) { geometryProxy in
            geometryProxy.size.height
        } action: { height in
            actionBarHeight = height
        }
    }

    private var isUltraWidescreen: Bool {
        screenWidth >= 780
    }

    private var isWidescreen: Bool {
        screenWidth >= 640
    }

    private var chatBoxWidth: CGFloat {
        if isUltraWidescreen {
            360
        } else if isWidescreen {
            280
        } else {
            screenWidth - 16 * 2
        }
    }

    private var statusIconBarBottomPadding: CGFloat {
        if isWidescreen {
            16 + actionBarHeight + 8
        } else {
            ChatBoxView.contentHeight(for: .compact) + 8 + actionBarHeight + 8
        }
    }

    #if os(macOS)
    private func handleKeyEvent(_ event: KeyEvent) -> Bool {
        if event.phase == .up {
            // Releases are matched by key code, so they stop movement even after the
            // chat field took focus or a modifier changed.
            guard heldMovementKeys.removeValue(forKey: event.keyCode) != nil else {
                return false
            }
            updateWalking()
            return true
        }

        if event.isRepeat {
            // A held movement key keeps walking on its own; swallow its repeats.
            return heldMovementKeys[event.keyCode] != nil
        }

        guard let chord = event.chord, let action = keyBindings.action(for: chord) else {
            return false
        }

        // Text fields keep their keys. Return is left to the chat field so it can send
        // the message, while Escape still closes the top window.
        if event.isTextInputFocused && action != .closeTopWindow {
            return false
        }

        switch action {
        case .moveUp, .moveLeft, .moveDown, .moveRight:
            heldMovementKeys[event.keyCode] = action.movementDirection
            updateWalking()
        default:
            perform(action)
        }

        return true
    }

    /// Runs an action which happens once per press, from the keyboard or the controller.
    private func perform(_ action: GameAction) {
        switch action {
        case .moveUp, .moveLeft, .moveDown, .moveRight:
            // Walking is continuous. It follows held keys and the stick, not one-shot actions.
            break
        case .attack:
            runtime.scene.attackSelectedOrNearestMonster()
        case .shortcut(let row, let slot):
            let rows = playSession.shortcutList.rows
            guard rows.indices.contains(row), rows[row].indices.contains(slot) else {
                return
            }
            playSession.useShortcut(rows[row][slot])
        case .toggleInventory:
            toggle(.inventory)
        case .toggleEquipment:
            toggle(.equipment)
        case .toggleSkills:
            toggle(.skill)
        case .toggleStatus:
            toggle(.status)
        case .togglePet:
            toggle(.pet)
        case .toggleHomunculus:
            toggle(.homunculus)
        case .toggleWorldMap:
            toggle(.worldMap)
        case .toggleOptions:
            toggle(.options)
        case .focusChat:
            chatFocusRequest += 1
        case .sitStand:
            runtime.scene.toggleSit()
        case .nextShortcutRow:
            let rowCount = playSession.shortcutList.rows.count
            guard rowCount > 0 else {
                return
            }
            playSession.setShortcutRowShift((playSession.shortcutList.rowShift + 1) % rowCount)
        case .closeTopWindow:
            closeTopWindow()
        }
    }

    /// Starts the controller reader, which walks and presses buttons through the same paths as the keyboard.
    private func connectGamepad() {
        gamepad.onMovementChange = { _ in
            updateWalking()
        }
        gamepad.onAction = { action in
            perform(action)
        }
        gamepad.start()
    }

    /// Drives the scene's thumbstick walking from the held movement keys and the controller,
    /// so both walk, turn, slide along walls and stop exactly like the touch thumbstick.
    /// This is the only place which sets the thumbstick on macOS: the keyboard and the
    /// controller are combined here, so letting go of one does not stop the other.
    private func updateWalking() {
        let keyboard = GamepadMapping.keyboardMovement(directions: heldMovementKeys.values)
        let value = GamepadMapping.walking(keyboard: keyboard, gamepad: gamepad.movement)
        runtime.scene.thumbstickValue = CGPoint(x: CGFloat(value.x), y: CGFloat(value.y))
    }

    private func toggle(_ item: MenuItem) {
        presentedMenuItem = presentedMenuItem == item ? nil : item
    }

    private func closeTopWindow() {
        if playSession.mail.draft != nil {
            playSession.closeMailCompose()
        } else if playSession.companions.petEggIndices != nil {
            playSession.cancelPetEggSelection()
        } else if playSession.storage != nil {
            playSession.closeStorage()
        } else if playSession.dealSelectionNPCID != nil {
            playSession.cancelDealSelection()
        } else if playSession.npcShop != nil {
            playSession.closeNPCShop()
        } else if playSession.warpList != nil {
            playSession.cancelWarpPoint()
        } else if playSession.dialog != nil {
            playSession.closeDialog()
        } else if presentedMenuItem != nil {
            presentedMenuItem = nil
        } else {
            presentedMenuItem = .options
        }
    }
    #endif
}
