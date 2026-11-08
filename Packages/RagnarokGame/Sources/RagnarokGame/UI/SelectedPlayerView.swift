//
//  SelectedPlayerView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

/// The player the user selected on the map, with the action to request a trade.
struct SelectedPlayerView: View {
    var player: MapSceneState.SelectedPlayer
    var onRequestTrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.game(size: 12, weight: .bold))
                .foregroundStyle(.white)

            Text(verbatim: player.name)
                .font(.game(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Button(action: onRequestTrade) {
                Text(verbatim: "Request trade")
            }
            .buttonStyle(.game)
            .frame(width: 92, height: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
    }
}

#Preview {
    SelectedPlayerView(player: MapSceneState.SelectedPlayer(accountID: 2_000_002, name: "Poring")) {
    }
    .padding()
}
