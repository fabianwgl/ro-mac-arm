//
//  PincodeView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokNetwork
import SwiftUI

struct PincodeView: View {
    var request: LoginStage.PincodeRequest

    @Environment(GameSession.self) private var gameSession
    @Environment(GameContext.self) private var gameContext

    @State private var pin = ""
    @State private var newPin = ""
    @State private var confirmPin = ""

    private var isValid: Bool {
        switch request {
        case .enter:
            isValidPin(pin)
        case .create:
            isValidPin(newPin) && newPin == confirmPin
        case .change:
            isValidPin(pin) && isValidPin(newPin) && newPin == confirmPin
        }
    }

    var body: some View {
        // login_interface/win_pincode.bmp
        GameWindow {
            VStack(alignment: .leading, spacing: 13) {
                switch request {
                case .enter:
                    PincodeField("PIN", text: $pin)
                case .create:
                    PincodeField("New PIN", text: $newPin)
                    PincodeField("Confirm", text: $confirmPin)
                case .change:
                    PincodeField("PIN", text: $pin)
                    PincodeField("New PIN", text: $newPin)
                    PincodeField("Confirm", text: $confirmPin)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 13)
        } bottomBar: {
            GameBottomBar {
                // btn_ok.bmp
                Button {
                    gameSession.audioPlayer.playButtonSoundEffect()

                    switch request {
                    case .enter:
                        gameSession.submitPincode(pin)
                    case .create:
                        gameSession.submitNewPincode(newPin)
                    case .change:
                        gameSession.changePincode(old: pin, new: newPin)
                    }

                    pin = ""
                    newPin = ""
                    confirmPin = ""
                } label: {
                    Text("OK", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(!isValid)

                // btn_cancel.bmp
                Button {
                    gameSession.exitCurrentPhase()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(gameContext.messageStringTable.localizedMessageString(forID: 1898)))
        .frame(width: 280)
    }

    private func isValidPin(_ pin: String) -> Bool {
        pin.count == PincodeCipher.length && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

private struct PincodeField: View {
    var label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(.game(weight: .bold))
                .foregroundStyle(Color.gameProminentLabel)
                .frame(width: 70, alignment: .trailing)

            SecureField(String(), text: $text)
                .textFieldStyle(.plain)
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .padding(.horizontal, 3)
                .frame(width: 127, height: 18)
                .background(Color.gameSecondaryBoxBackground)
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.gameBoxBorder)
                }
                .onChange(of: text) { _, newValue in
                    text = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(PincodeCipher.length))
                }

            Spacer()
        }
    }
}

#Preview {
    PincodeView(request: .enter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(GameSession.testing)
        .environment(GameContext.testing)
}
