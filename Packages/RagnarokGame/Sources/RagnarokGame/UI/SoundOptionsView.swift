//
//  SoundOptionsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

struct SoundOptionsView: View {
    @Bindable var preferences: GamePreferences
    var onClose: () -> Void = {}

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("BGM", isOn: $preferences.isBGMEnabled)

                HStack(spacing: 8) {
                    Text(verbatim: "Music volume")
                        .frame(width: 92, alignment: .leading)

                    Slider(value: $preferences.bgmVolume, in: 0...1)

                    Text(verbatim: "\(Int((preferences.bgmVolume * 100).rounded()))%")
                        .frame(width: 34, alignment: .trailing)
                }
                .disabled(!preferences.isBGMEnabled)

                Divider()

                Toggle("Sound Effects", isOn: $preferences.isSoundEffectEnabled)

                HStack(spacing: 8) {
                    Text(verbatim: "Effect volume")
                        .frame(width: 92, alignment: .leading)

                    Slider(value: $preferences.soundEffectVolume, in: 0...1)

                    Text(verbatim: "\(Int((preferences.soundEffectVolume * 100).rounded()))%")
                        .frame(width: 34, alignment: .trailing)
                }
                .disabled(!preferences.isSoundEffectEnabled)
            }
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .gameWindowTitle(Text("Sound", bundle: #bundle))
        .gameWindowCloseAction(onClose)
        .frame(width: 280)
    }
}

#Preview {
    SoundOptionsView(preferences: GamePreferences())
        .padding()
}
