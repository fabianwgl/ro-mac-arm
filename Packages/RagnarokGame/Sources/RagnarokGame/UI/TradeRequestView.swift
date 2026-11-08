//
//  TradeRequestView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

/// The prompt for a trade request from another player.
struct TradeRequestView: View {
    var request: TradeRequest

    @Environment(PlaySession.self) private var playSession

    var body: some View {
        MessageBoxView(message) {
            Button {
                playSession.answerTradeRequest(accept: true)
            } label: {
                Text(verbatim: "Accept")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)

            Button {
                playSession.answerTradeRequest(accept: false)
            } label: {
                Text(verbatim: "Decline")
            }
            .buttonStyle(.game)
            .frame(width: 58, height: 20)
        }
        .gameWindowTitle(Text(verbatim: "Trade Request"))
    }

    private var message: String {
        if request.baseLevel > 0 {
            "\(request.name) (Lv \(request.baseLevel)) wants to trade with you."
        } else {
            "\(request.name) wants to trade with you."
        }
    }
}

#Preview {
    TradeRequestView(request: TradeRequest(accountID: 2_000_002, name: "Poring", baseLevel: 50))
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
