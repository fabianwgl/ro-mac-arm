//
//  KeyBindingsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct KeyBindingsView: View {
    @Environment(KeyBindings.self) private var keyBindings
    @Environment(\.dismiss) private var dismiss

    @State private var capturingAction: GameAction?

    var body: some View {
        GameWindow {
            VStack(spacing: 0) {
                Text(verbatim: instruction)
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(GameAction.all) { action in
                            actionRow(action)
                        }
                    }
                }
            }
        } bottomBar: {
            GameBottomBar {
                Button {
                    keyBindings.resetToDefaults()
                    capturingAction = nil
                } label: {
                    Text(verbatim: "Reset to defaults")
                }
                .buttonStyle(.game)
                .frame(width: 120, height: 20)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(verbatim: "Close")
                }
                .buttonStyle(.game)
                .frame(width: 60, height: 20)
            }
        }
        .gameWindowTitle(Text("BM/Shortcut Settings", bundle: #bundle))
        .gameWindowCloseAction {
            dismiss()
        }
        .frame(width: 420, height: 520)
        #if os(macOS)
        .background {
            if capturingAction != nil {
                KeyEventMonitor { event in
                    guard event.phase == .down, !event.isRepeat, let chord = event.chord else {
                        return false
                    }
                    capture(chord)
                    return true
                }
            }
        }
        #endif
    }

    private var instruction: String {
        if capturingAction != nil {
            return "Press the keys to assign, or click the binding again to cancel."
        }
        return "Click a binding, then press the keys to assign."
    }

    private func actionRow(_ action: GameAction) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: action.title)
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)
                .frame(width: 180, alignment: .leading)

            Button {
                capturingAction = capturingAction == action ? nil : action
            } label: {
                Text(verbatim: bindingTitle(for: action))
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(Color(#colorLiteral(red: 0.9372549020, green: 0.9568627451, blue: 0.9411764706, alpha: 1)))
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color.gameBoxBorder)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                keyBindings.setChord(nil, for: action)
                if capturingAction == action {
                    capturingAction = nil
                }
            } label: {
                Text(verbatim: "Clear")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)
                    .frame(width: 48, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(keyBindings.chord(for: action) == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func bindingTitle(for action: GameAction) -> String {
        if capturingAction == action {
            return "Press keys…"
        }

        guard let chord = keyBindings.chord(for: action) else {
            return "Unbound"
        }
        return chord.displayString
    }

    private func capture(_ chord: KeyChord) {
        guard let action = capturingAction else {
            return
        }

        keyBindings.setChord(chord, for: action)
        capturingAction = nil
    }
}

#Preview {
    KeyBindingsView()
        .environment(KeyBindings())
}
