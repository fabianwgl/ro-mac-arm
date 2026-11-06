//
//  LoginView.swift
//  RagnarokGame
//
//  Created by Leon Li on 2024/9/4.
//

import SwiftUI

struct LoginView: View {
    @Environment(GameSession.self) private var gameSession
    @Environment(\.exitGame) private var exitGame

    @AppStorage("game.username") private var username = ""
    @AppStorage("game.remembersPassword") private var remembersPassword = false

    @State private var password = ""

    private let credentialStore = CredentialStore()

    var body: some View {
        // login_interface/win_login.bmp
        GameWindow {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Text("ID", bundle: #bundle)
                        .font(.game(weight: .bold))
                        .foregroundStyle(Color.gameProminentLabel)
                        .frame(width: 70, alignment: .trailing)

                    TextField(String(), text: $username)
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

                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("Password", bundle: #bundle)
                        .font(.game(weight: .bold))
                        .foregroundStyle(Color.gameProminentLabel)
                        .frame(width: 70, alignment: .trailing)

                    SecureField(String(), text: $password)
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

                    Spacer()
                }

                HStack(spacing: 10) {
                    Spacer()
                        .frame(width: 70)

                    Toggle("Remember password", isOn: $remembersPassword)
                        .font(.game())
                        .foregroundStyle(Color.gameLabel)

                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 13)
        } bottomBar: {
            GameBottomBar {
                // login_interface/btn_connect.bmp
                Button {
                    gameSession.audioPlayer.playButtonSoundEffect()
                    updateSavedPassword()
                    gameSession.login(username: username, password: password)
                    username = usernameWithoutSuffix
                } label: {
                    Text("login", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(!isValidUsername || !isValidPassword)

                // login_interface/btn_exit.bmp
                Button {
                    gameSession.exitSession()
                    exitGame()
                } label: {
                    Text("exit", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text("LogOn", bundle: #bundle))
        .frame(width: 280)
        .onAppear {
            migrateLegacyPassword()
            loadSavedPassword()
        }
    }

    private func migrateLegacyPassword() {
        let defaults = UserDefaults.standard
        guard let legacyPassword = defaults.string(forKey: "game.password"), !legacyPassword.isEmpty else {
            return
        }

        let account = usernameWithoutSuffix
        guard !account.isEmpty else {
            return
        }

        do {
            try credentialStore.setPassword(legacyPassword, for: account)
            remembersPassword = true
            defaults.removeObject(forKey: "game.password")
        } catch {
            logger.warning("Failed to migrate password to the Keychain: \(error)")
        }
    }

    private func loadSavedPassword() {
        guard remembersPassword else {
            return
        }

        let account = usernameWithoutSuffix
        guard !account.isEmpty else {
            return
        }

        do {
            password = try credentialStore.password(for: account) ?? ""
        } catch {
            logger.warning("Failed to load password from the Keychain: \(error)")
        }
    }

    private func updateSavedPassword() {
        let account = usernameWithoutSuffix

        do {
            if remembersPassword {
                try credentialStore.setPassword(password, for: account)
            } else {
                try credentialStore.deletePassword(for: account)
            }
        } catch {
            logger.warning("Failed to update the saved password in the Keychain: \(error)")
        }
    }

    private var usernameWithoutSuffix: String {
        username.replacingOccurrences(
            of: "_[mMfF]$",
            with: "",
            options: .regularExpression
        )
    }

    private var isValidUsername: Bool {
        usernameWithoutSuffix.count >= 6
    }

    private var isValidPassword: Bool {
        password.count >= 6
    }
}

#Preview {
    LoginView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(GameSession.testing)
}
