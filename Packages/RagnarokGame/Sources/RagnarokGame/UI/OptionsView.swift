//
//  OptionsView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2025/10/16.
//

import SwiftUI

struct OptionsView: View {
    private enum Panel {
        case sound
        case graphics
    }

    var isPlayerDead: Bool
    var onClose: () -> Void = {}

    @Environment(GameContext.self) private var gameContext
    @Environment(PlaySession.self) private var playSession
    @Environment(KeyBindings.self) private var keyBindings

    @State private var isShowingKeyBindings = false

    @State private var presentedPanel: Panel?

    var body: some View {
        if let presentedPanel {
            switch presentedPanel {
            case .sound:
                SoundOptionsView(preferences: gameContext.preferences) {
                    self.presentedPanel = nil
                }
            case .graphics:
                GraphicsOptionsView(preferences: gameContext.preferences) {
                    self.presentedPanel = nil
                }
            }
        } else {
            menu
        }
    }

    private var menu: some View {
        GameWindow {
            VStack(spacing: 3) {
                if isPlayerDead {
                    // esc_05a.bmp
                    Button {
                        playSession.resurrectInPlace()
                    } label: {
                        Text("Resurrection", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)
                    .disabled(!playSession.inventory.hasTokenOfSiegfried)

                    // esc_04a.bmp
                    Button {
                        playSession.returnToLastSavePoint()
                    } label: {
                        Text("Return to last save point", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)
                } else {
                    // esc_01a.bmp
                    Button {
                        playSession.returnToCharacterSelect()
                    } label: {
                        Text("Character Select", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)

                    // esc_06a.bmp
                    Button {
                        presentedPanel = .graphics
                    } label: {
                        Text("Settings", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)

                    // esc_07a.bmp
                    Button {
                        presentedPanel = .sound
                    } label: {
                        Text("Sound", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)

                    // esc_08a.bmp
                    Button {
                        isShowingKeyBindings = true
                    } label: {
                        Text("BM/Shortcut Settings", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)
                    #if !os(macOS)
                    .disabled(true)
                    #endif

                    // esc_03a.bmp
                    Button {
                        playSession.requestExit()
                    } label: {
                        Text("Exit", bundle: #bundle)
                    }
                    .buttonStyle(.game)
                    .frame(width: 220, height: 20)
                }
            }
            .padding(.vertical, 20)
        }
        .gameWindowTitle(Text(gameContext.messageStringTable.localizedMessageString(forID: 1483)))
        .gameWindowCloseAction(onClose)
        .sheet(isPresented: $isShowingKeyBindings) {
            KeyBindingsView()
                .environment(keyBindings)
        }
        .frame(width: 280)
    }
}

#Preview {
    OptionsView(isPlayerDead: false)
        .padding()
        .environment(GameSession.testing)
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
        .environment(KeyBindings())
}
