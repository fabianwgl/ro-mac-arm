//
//  MailComposeView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokConstants
import RagnarokModels
import SwiftUI

struct MailComposeView: View {
    @Environment(PlaySession.self) private var playSession
    @Environment(GameContext.self) private var gameContext

    @State private var isPickingItem = false
    @State private var amountItem: InventoryItem?

    var body: some View {
        if let draft = playSession.mail.draft {
            GameWindow {
                VStack(alignment: .leading, spacing: 5) {
                    receiverRow(draft)
                    titleRow(draft)
                    bodyEditor(draft)
                    zenyRow(draft)
                    attachmentRow(draft)

                    if isPickingItem {
                        itemPicker(draft)
                    }
                }
                .padding(5)
                .blur(radius: amountItem == nil ? 0 : 5)
                .overlay {
                    amountInputBox(draft)
                }
            } bottomBar: {
                GameBottomBar {
                    Text(verbatim: costText(draft))
                        .font(.game(size: 11))
                        .foregroundStyle(costColor(draft))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button {
                        playSession.sendMail()
                    } label: {
                        Text(verbatim: draft.isSending ? "Sending..." : "Send")
                    }
                    .buttonStyle(.game)
                    .frame(width: 66, height: 20)
                    .disabled(!draft.isServerReady || draft.isSending)

                    Button {
                        playSession.closeMailCompose()
                    } label: {
                        Text(verbatim: "Cancel")
                    }
                    .buttonStyle(.game)
                    .frame(width: 58, height: 20)
                }
            }
            .gameWindowTitle(Text(verbatim: "Write Mail"))
            .gameWindowCloseAction {
                playSession.closeMailCompose()
            }
            .frame(width: 380)
            .animation(.easeInOut(duration: 0.25), value: amountItem?.index)
        }
    }

    // MARK: - Rows

    private func receiverRow(_ draft: MailDraft) -> some View {
        HStack(spacing: 5) {
            label("To")

            TextField("Character name", text: Binding {
                draft.receiverName
            } set: { name in
                playSession.mail.draft?.setReceiverName(name)
            })
            .textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 3)
            .frame(height: 18)
            .background(fieldBackground)
            .onSubmit {
                playSession.checkMailReceiver()
            }

            Button {
                playSession.checkMailReceiver()
            } label: {
                Text(verbatim: "Check")
            }
            .buttonStyle(.game)
            .frame(width: 50, height: 18)
            .disabled(draft.trimmedReceiverName.isEmpty || draft.receiver == .checking || !draft.isServerReady)
        }
        .overlay(alignment: .bottomLeading) {
            receiverStatus(draft)
                .offset(x: 28, y: 11)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder private func receiverStatus(_ draft: MailDraft) -> some View {
        switch draft.receiver {
        case .unchecked:
            EmptyView()
        case .checking:
            statusText("Checking...", color: Color.gameProminentLabel)
        case .found(_, let job, let baseLevel):
            statusText(foundText(job: job, baseLevel: baseLevel), color: Color.green)
        case .notFound:
            statusText("No such character.", color: Color.red)
        }
    }

    private func foundText(job: Int, baseLevel: Int) -> String {
        var parts = ["Found"]
        if baseLevel > 0 {
            parts.append("Lv \(baseLevel)")
        }
        if let jobID = JobID(rawValue: job), let name = jobID.localizedName {
            parts.append(String(localized: name))
        }
        return parts.joined(separator: " | ")
    }

    private func titleRow(_ draft: MailDraft) -> some View {
        HStack(spacing: 5) {
            label("Title")

            TextField("Title", text: Binding {
                draft.title
            } set: { title in
                playSession.mail.draft?.title = limited(title, bytes: MailDraft.maxTitleBytes)
            })
            .textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 3)
            .frame(height: 18)
            .background(fieldBackground)
        }
    }

    private func bodyEditor(_ draft: MailDraft) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            TextEditor(text: Binding {
                draft.body
            } set: { body in
                playSession.mail.draft?.body = limited(body, bytes: MailDraft.maxBodyBytes)
            })
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .scrollContentBackground(.hidden)
            .padding(2)
            .frame(height: 96)
            .background(fieldBackground)

            Text(verbatim: "\(MailDraft.byteCount(of: draft.body)) / \(MailDraft.maxBodyBytes)")
                .font(.game(size: 10))
                .foregroundStyle(Color.gameProminentLabel)
        }
    }

    private func zenyRow(_ draft: MailDraft) -> some View {
        HStack(spacing: 5) {
            label("Zeny")

            TextField("0", text: Binding {
                draft.zeny == 0 ? "" : "\(draft.zeny)"
            } set: { text in
                let digits = text.filter(\.isNumber).prefix(10)
                let zeny = Int64(digits) ?? 0
                playSession.mail.draft?.zeny = min(zeny, Int64(max(playSession.playerStatus.zeny, 0)))
            })
            .textFieldStyle(.plain)
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 3)
            .frame(width: 110, height: 18)
            .background(fieldBackground)
            #if !os(macOS)
            .keyboardType(.numberPad)
            #endif

            Text(verbatim: "of \(playSession.playerStatus.zeny.formatted())")
                .font(.game(size: 10))
                .foregroundStyle(Color.gameProminentLabel)

            Spacer(minLength: 0)
        }
    }

    private func attachmentRow(_ draft: MailDraft) -> some View {
        HStack(spacing: 5) {
            label("Items")

            ForEach(draft.attachments) { attachment in
                MailAttachmentView(
                    itemID: attachment.itemID,
                    amount: attachment.amount,
                    refine: attachment.refine,
                    cards: attachment.cards,
                    isIdentified: attachment.isIdentified
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        playSession.detachMailItem(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.game(size: 11))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Button {
                isPickingItem.toggle()
            } label: {
                Text(verbatim: isPickingItem ? "Hide" : "Add item")
            }
            .buttonStyle(.game)
            .frame(width: 62, height: 18)
            .disabled(!draft.isServerReady || (!draft.canAttachMore && !isPickingItem))
        }
    }

    private func itemPicker(_ draft: MailDraft) -> some View {
        let items = availableItems(draft)

        return ScrollView {
            if items.isEmpty {
                Text(verbatim: "No items to attach.")
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
                                    playSession.attachMailItem(index: item.index, amount: 1)
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

    @ViewBuilder private func amountInputBox(_ draft: MailDraft) -> some View {
        if let item = amountItem {
            GameNumberInputBox(
                gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "\(item.itemID)",
                bounds: 1...max(item.amount, 1)
            ) { amount in
                playSession.attachMailItem(index: item.index, amount: amount)
                amountItem = nil
            } onClose: {
                amountItem = nil
            }
            .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Helpers

    /// Inventory items that can go into the mail: not worn, and not attached in full already.
    private func availableItems(_ draft: MailDraft) -> [InventoryItem] {
        playSession.inventory.items.values
            .filter { !$0.isEquipped }
            .compactMap { item -> InventoryItem? in
                var item = item
                item.amount -= draft.attachedAmount(index: item.index)
                return item.amount > 0 ? item : nil
            }
            .sorted()
    }

    private func costText(_ draft: MailDraft) -> String {
        if draft.fee > 0 {
            "Fee: \(draft.fee.formatted()) zeny"
        } else {
            "No fee"
        }
    }

    private func costColor(_ draft: MailDraft) -> Color {
        draft.totalCost > Int64(playSession.playerStatus.zeny) ? Color.red : Color.gameLabel
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.game(size: 11))
            .foregroundStyle(Color.gameLabel)
            .frame(width: 30, alignment: .leading)
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.game(size: 10))
            .foregroundStyle(color)
    }

    private var fieldBackground: Color {
        Color(#colorLiteral(red: 0.9372549020, green: 0.9372549020, blue: 0.9372549020, alpha: 1))
    }

    /// Cuts text to at most `bytes` UTF-8 bytes, which is the limit the server keeps.
    private func limited(_ text: String, bytes: Int) -> String {
        var text = text
        while MailDraft.byteCount(of: text) > bytes {
            text.removeLast()
        }
        return text
    }
}

#Preview {
    MailComposeView()
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
        .task {
            var draft = MailDraft(receiverName: "Poring")
            draft.title = "Hello"
            draft.isServerReady = true
            PlaySession.testing.mail.draft = draft
        }
}
