//
//  GraphicsOptionsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct GraphicsOptionsView: View {
    @Bindable var preferences: GamePreferences
    var onClose: () -> Void = {}

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show names", isOn: $preferences.showsNames)

                Toggle("Show miss text", isOn: $preferences.showsMissText)

                Toggle("Show effects", isOn: $preferences.effectsEnabled)

                Divider()

                HStack(spacing: 8) {
                    Text(verbatim: "Default zoom")
                        .frame(width: 92, alignment: .leading)

                    Slider(
                        value: $preferences.defaultZoom,
                        in: GamePreferences.zoomRange,
                        step: 1
                    )

                    Text(verbatim: "\(Int(preferences.defaultZoom))")
                        .frame(width: 34, alignment: .trailing)
                }

                Text(verbatim: "Display changes apply immediately. Default zoom applies when the next map loads.")
                    .font(.game(size: 10))
                    .foregroundStyle(Color.gameProminentLabel)
            }
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        } bottomBar: {
            GameBottomBar {
                Button {
                    preferences.resetToDefaults()
                } label: {
                    Text(verbatim: "Reset to Defaults")
                }
                .buttonStyle(.game)
                .frame(width: 110, height: 20)
            }
        }
        .gameWindowTitle(Text("Settings", bundle: #bundle))
        .gameWindowCloseAction(onClose)
        .frame(width: 280)
    }
}

#Preview {
    GraphicsOptionsView(preferences: GamePreferences())
        .padding()
}
