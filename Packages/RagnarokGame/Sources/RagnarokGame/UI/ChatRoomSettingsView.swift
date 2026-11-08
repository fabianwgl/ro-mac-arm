//
//  ChatRoomSettingsView.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import SwiftUI

/// The window that opens a chat room (title, members, public or private with a password) and the owner's window that
/// changes those. Both send the same fields: `CZ_CREATE_CHATROOM` and `CZ_CHANGE_CHATROOM` have one layout.
struct ChatRoomSettingsView: View {
    enum Mode {
        case create
        case change
    }

    var mode: Mode

    @Environment(PlaySession.self) private var playSession

    @State private var settings: ChatRoomSettings

    var body: some View {
        GameWindow {
            VStack(alignment: .leading, spacing: 6) {
                labeled("Title") {
                    TextField(String(), text: Binding {
                        settings.title
                    } set: {
                        settings.setTitle($0)
                    })
                    .textFieldStyle(.plain)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .disableAutocorrection(true)
                    .modifier(FieldStyle(width: 190))
                }

                labeled("Members") {
                    GameStepper(value: Binding {
                        settings.limit
                    } set: {
                        settings.setLimit($0)
                    }, in: ChatRoomSettings.minLimit...ChatRoomSettings.maxLimit)
                }

                labeled("Access") {
                    HStack(spacing: 10) {
                        accessButton("Public", isPublic: true)
                        accessButton("Private", isPublic: false)
                    }
                }

                if !settings.isPublic {
                    labeled("Password") {
                        SecureField(String(), text: Binding {
                            settings.password
                        } set: {
                            settings.setPassword($0)
                        })
                        .textFieldStyle(.plain)
                        .modifier(FieldStyle(width: 110))
                    }
                }

                if let problem = settings.problem, !isUntouched {
                    Text(verbatim: problem.message)
                        .font(.game())
                        .foregroundStyle(Color.red)
                }
            }
            .padding(10)
        } bottomBar: {
            GameBottomBar {
                // btn_ok.bmp
                Button {
                    switch mode {
                    case .create:
                        playSession.createChatRoom(settings)
                    case .change:
                        playSession.changeChatRoom(settings)
                    }
                } label: {
                    Text("OK", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
                .disabled(settings.problem != nil)

                // btn_cancel.bmp
                Button {
                    cancel()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: mode == .create ? "Create Chat Room" : "Chat Room Settings"))
        .gameWindowCloseAction {
            cancel()
        }
        .frame(width: 300)
    }

    init(mode: Mode, settings: ChatRoomSettings) {
        self.mode = mode
        self._settings = State(initialValue: settings)
    }

    /// A fresh create window does not scold about the empty title before anything was typed.
    private var isUntouched: Bool {
        settings.title.isEmpty
    }

    private func cancel() {
        switch mode {
        case .create:
            playSession.cancelChatRoomCreation()
        case .change:
            playSession.cancelChatRoomSettings()
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(.game())
                .foregroundStyle(Color.gameLabel)
                .frame(width: 64, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
    }

    private func accessButton(_ title: String, isPublic: Bool) -> some View {
        Button {
            settings.isPublic = isPublic
        } label: {
            HStack(spacing: 3) {
                Image(systemName: settings.isPublic == isPublic ? "largecircle.fill.circle" : "circle")
                Text(verbatim: title)
            }
            .font(.game())
            .foregroundStyle(Color.gameLabel)
        }
        .buttonStyle(.plain)
    }
}

private struct FieldStyle: ViewModifier {
    var width: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.game())
            .foregroundStyle(Color.gameLabel)
            .padding(.horizontal, 4)
            .frame(width: width, height: 18)
            .background(Color(#colorLiteral(red: 0.9686274510, green: 0.9686274510, blue: 0.9686274510, alpha: 1)))
            .border(Color(#colorLiteral(red: 0.7764705882, green: 0.7764705882, blue: 0.7764705882, alpha: 1)))
    }
}

/// The prompt for the password of a private room the player clicked.
struct ChatRoomPasswordView: View {
    var sign: ChatRoomSign

    @Environment(PlaySession.self) private var playSession

    @State private var password = ""

    var body: some View {
        GameWindow {
            VStack(spacing: 8) {
                Text(verbatim: "\"\(sign.title)\" is a private chat room. Enter the password.")
                    .font(.game())
                    .foregroundStyle(Color.gameLabel)
                    .multilineTextAlignment(.center)

                SecureField(String(), text: Binding {
                    password
                } set: {
                    password = ChatRoomSettings.truncated($0, maxBytes: ChatRoomSettings.packetPasswordBytes)
                })
                .textFieldStyle(.plain)
                .modifier(FieldStyle(width: 120))
                .onSubmit {
                    join()
                }
            }
            .padding(10)
            .frame(height: 82)
        } bottomBar: {
            GameBottomBar {
                Button {
                    join()
                } label: {
                    Text(verbatim: "Enter")
                }
                .buttonStyle(.game)
                .frame(width: 50, height: 20)

                // btn_cancel.bmp
                Button {
                    playSession.cancelChatRoomPassword()
                } label: {
                    Text("cancel", bundle: #bundle)
                }
                .buttonStyle(.game)
                .frame(width: 42, height: 20)
            }
        }
        .gameWindowTitle(Text(verbatim: "Chat Room"))
        .gameWindowCloseAction {
            playSession.cancelChatRoomPassword()
        }
        .frame(width: 280)
    }

    private func join() {
        playSession.joinChatRoom(sign, password: password)
    }
}

#Preview("Create") {
    ChatRoomSettingsView(mode: .create, settings: ChatRoomSettings(title: "Prontera meetup"))
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}

#Preview("Password") {
    ChatRoomPasswordView(sign: ChatRoomSign(chatID: 5, ownerID: 2_000_002, title: "Secret", limit: 5, users: 2, access: .privateRoom))
        .padding()
        .environment(GameContext.testing)
        .environment(PlaySession.testing)
}
