//
//  TradeView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokModels
import SwiftUI

/// The trade window: what both players offer, with OK, Trade and Cancel.
struct TradeView: View {
    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    @State private var isPickingItem = false
    @State private var amountItem: InventoryItem?
    @State private var zenyText = ""

    var body: some View {
        if let trade = playSession.trade.current {
            GameWindow {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 5) {
                        sideColumn(
                            title: "You",
                            side: trade.mine,
                            pendingCount: trade.pendingAdds.count
                        )

                        Rectangle()
                            .fill(Color.gameBoxBorder)
                            .frame(width: 1)

                        sideColumn(
                            title: trade.partner.name,
                            side: trade.theirs,
                            pendingCount: 0
                        )
                    }

                    ownControls(trade)

                    if isPickingItem && trade.canChangeOffer {
                        itemPicker(trade)
                    }

                    statusText(trade)
                }
                .padding(5)
                .blur(radius: amountItem == nil ? 0 : 5)
                .overlay {
                    amountInputBox(trade)
                }
            } bottomBar: {
                GameBottomBar {
                    Button {
                        playSession.lockTrade()
                    } label: {
                        Text(verbatim: "OK")
                    }
                    .buttonStyle(.game)
                    .frame(width: 50, height: 20)
                    .disabled(!trade.canLock)

                    Button {
                        playSession.confirmTrade()
                    } label: {
                        Text(verbatim: "Trade")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                    .disabled(!trade.canConfirm)

                    Button {
                        playSession.cancelTrade()
                    } label: {
                        Text(verbatim: "Cancel")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }
            }
            .gameWindowTitle(Text(verbatim: "Trade with \(trade.partner.name)"))
            .gameWindowCloseAction {
                playSession.cancelTrade()
            }
            .frame(width: 380)
            .animation(.easeInOut(duration: 0.25), value: amountItem?.index)
            .onChange(of: trade.mine.isLocked) { _, isLocked in
                if isLocked {
                    isPickingItem = false
                    amountItem = nil
                }
            }
        }
    }

    // MARK: - Sides

    private func sideColumn(title: String, side: Trade.Side, pendingCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .font(.game(size: 12, weight: .bold))
                    .foregroundStyle(Color.gameProminentLabel)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if side.isLocked {
                    Text(verbatim: side.hasConfirmed ? "Trade" : "OK")
                        .font(.game(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 3), count: 5), spacing: 3) {
                ForEach(0..<Trade.maxOffers, id: \.self) { slot in
                    ZStack {
                        GameItemShadowView()
                            .offset(y: 5)

                        if slot < side.offers.count {
                            let offer = side.offers[slot]

                            MailAttachmentView(
                                itemID: offer.itemID,
                                amount: offer.amount,
                                refine: offer.refine,
                                cards: offer.cards,
                                isIdentified: offer.isIdentified
                            )
                        }
                    }
                    .frame(width: 32, height: 32)
                }
            }

            HStack(spacing: 4) {
                Text(verbatim: "Zeny")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel)

                Text(verbatim: side.zeny.formatted())
                    .font(.game(size: 11, weight: .bold))
                    .foregroundStyle(Color.gameLabel)
            }

            if pendingCount > 0 {
                Text(verbatim: "Adding...")
                    .font(.game(size: 10))
                    .foregroundStyle(Color.gameProminentLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Own offer

    private func ownControls(_ trade: Trade) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: "Zeny")
                .font(.game(size: 11))
                .foregroundStyle(Color.gameLabel)

            TextField("0", text: $zenyText)
                .textFieldStyle(.plain)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 3)
                .frame(width: 100, height: 18)
                .background(fieldBackground)
                .onSubmit {
                    offerZeny()
                }
                .onChange(of: zenyText) { _, text in
                    let digits = String(text.filter(\.isNumber).prefix(10))
                    if digits != text {
                        zenyText = digits
                    }
                }
                #if !os(macOS)
                .keyboardType(.numberPad)
                #endif

            Button {
                offerZeny()
            } label: {
                Text(verbatim: "Set")
            }
            .buttonStyle(.game)
            .frame(width: 36, height: 18)
            .disabled(!trade.canChangeOffer)

            Text(verbatim: "of \(playSession.playerStatus.zeny.formatted())")
                .font(.game(size: 10))
                .foregroundStyle(Color.gameProminentLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                isPickingItem.toggle()
            } label: {
                Text(verbatim: isPickingItem ? "Hide" : "Add item")
            }
            .buttonStyle(.game)
            .frame(width: 62, height: 18)
            .disabled(!trade.canChangeOffer)
        }
    }

    private func itemPicker(_ trade: Trade) -> some View {
        let items = availableItems(trade)

        return ScrollView {
            if items.isEmpty {
                Text(verbatim: "No items to trade.")
                    .font(.game(size: 11))
                    .foregroundStyle(Color.gameProminentLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 4)], spacing: 4) {
                    ForEach(items, id: \.index) { item in
                        InventoryItemView(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if item.amount > 1 {
                                    amountItem = item
                                } else {
                                    playSession.offerTradeItem(index: item.index, amount: 1)
                                }
                            }
                    }
                }
                .padding(4)
            }
        }
        .frame(height: 84)
        .background(Color(#colorLiteral(red: 0.9764705882, green: 0.9764705882, blue: 0.9764705882, alpha: 1)))
    }

    @ViewBuilder private func amountInputBox(_ trade: Trade) -> some View {
        if let item = amountItem {
            GameNumberInputBox(
                gameContext.itemInfoTable.localizedItemName(forItemID: item.itemID, isIdentified: item.isIdentified) ?? "\(item.itemID)",
                bounds: 1...max(min(item.amount, Trade.maxAmountPerAdd), 1)
            ) { amount in
                playSession.offerTradeItem(index: item.index, amount: amount)
                amountItem = nil
            } onClose: {
                amountItem = nil
            }
            .transition(.opacity.combined(with: .scale))
        }
    }

    private func statusText(_ trade: Trade) -> some View {
        let name = trade.partner.name
        let (text, color): (String, Color) = switch trade.stage {
        case .negotiating:
            ("Add items and zeny, then press OK.", Color.gameProminentLabel)
        case .waitingForPartnerLock:
            ("Waiting for \(name) to press OK.", Color.gameProminentLabel)
        case .waitingForOwnLock:
            ("\(name) pressed OK. Check the offer, then press OK.", Color.gameProminentLabel)
        case .readyToConfirm:
            ("Both pressed OK. Press Trade to finish.", Color.green)
        case .waitingForPartnerConfirm:
            ("Waiting for \(name) to press Trade.", Color.gameProminentLabel)
        case .partnerChangedAfterLock:
            ("\(name) changed the offer after you pressed OK. Cancel the trade.", Color.red)
        }

        return Text(verbatim: text)
            .font(.game(size: 11))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// Inventory items that can go into the trade: not worn, and not taken in full by items on their way.
    private func availableItems(_ trade: Trade) -> [InventoryItem] {
        playSession.inventory.items.values
            .filter { !$0.isEquipped }
            .compactMap { item -> InventoryItem? in
                var item = item
                item.amount -= trade.pendingAmount(inventoryIndex: item.index)
                return item.amount > 0 ? item : nil
            }
            .sorted()
    }

    private func offerZeny() {
        playSession.offerTradeZeny(Int(zenyText) ?? 0)
    }

    private var fieldBackground: Color {
        Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1))
    }
}

#Preview {
    TradeView()
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
        .task {
            var trade = Trade(partner: Trade.Partner(accountID: 2_000_002, name: "Poring", baseLevel: 50))
            trade.partnerAdded(Trade.Offer(id: 0, itemID: 501, amount: 5))
            trade.partnerSetZeny(1_000)
            PlaySession.testing.trade.current = trade
        }
}
