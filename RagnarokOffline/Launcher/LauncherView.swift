//
//  LauncherView.swift
//  RO Mac Client
//
//  Created by RO Mac Client contributors on 2026/11/5.
//

// SPDX-License-Identifier: GPL-3.0-only

#if os(macOS)

import AppKit
import Network
import RagnarokGame
import RagnarokPackets
import SwiftUI

/// Default content of the main window: server endpoint, client asset status, and the Play button.
struct LauncherView: View {
    let settings: SettingsModel

    @Environment(\.openWindow) private var openWindow

    @AppStorage(DeveloperTools.defaultsKey) private var showsDeveloperTools = false

    @State private var serverAddress: String
    @State private var serverPort: String
    @State private var assetStatus = ClientAssetStatus.check(in: localClientURL)
    @State private var playState: PlayState = .idle

    private enum PlayState: Equatable {
        case idle
        case testingConnection
        case serverUnreachable(String)
    }

    init(settings: SettingsModel) {
        self.settings = settings
        _serverAddress = State(initialValue: settings.serverAddress)
        _serverPort = State(initialValue: settings.serverPort)
    }

    private var validAddress: String? {
        ServerEndpointInput.address(serverAddress)
    }

    private var validPort: UInt16? {
        ServerEndpointInput.port(serverPort)
    }

    private var canPlay: Bool {
        assetStatus.isReady && validAddress != nil && validPort != nil && playState != .testingConnection
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                serverSection
                assetsSection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Pinned so Play stays visible however tall the status rows grow.
            playSection
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 720)
        .onAppear {
            PerfProbe.mark("launcherShown")
            refreshAssets()
            #if DEBUG || RO_AUTOMATION
            // Performance runs (scripts/perf-run.sh): skip Play and open the game window straight away.
            if let configuration = AutoLogin.launchConfiguration(
                defaultAddress: settings.serverAddress,
                defaultPort: UInt16(settings.serverPort) ?? 6900
            ) {
                openWindow(id: GameSession.windowID, value: configuration)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAssets()
        }
        .onChange(of: serverAddress) {
            playState = .idle
            if let validAddress {
                settings.serverAddress = validAddress
            }
        }
        .onChange(of: serverPort) {
            playState = .idle
            if let validPort {
                settings.serverPort = String(validPort)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text(verbatim: "RO Mac Client")
                .font(.largeTitle)
                .bold()

            Text(verbatim: "Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text(verbatim: "rAthena PACKETVER \(PACKET_VERSION)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.background.secondary, in: Capsule())
                .help("The server must speak this packet version")
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Server")

            VStack(spacing: 0) {
                LabeledContent("Address") {
                    TextField(String(), text: $serverAddress, prompt: Text(verbatim: "127.0.0.1"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding()

                Divider()
                    .padding(.horizontal)

                LabeledContent("Port") {
                    TextField(String(), text: $serverPort, prompt: Text(verbatim: "6900"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
                .padding()
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            if validAddress == nil {
                validationMessage("Enter a host name or IP address.")
            }
            if validPort == nil {
                validationMessage("The port must be a number from 1 to 65535.")
            }
        }
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Client Files")

            VStack(alignment: .leading, spacing: 0) {
                assetRow(
                    systemImage: dataGRFImage.name,
                    color: dataGRFImage.color,
                    title: "data.grf",
                    detail: dataGRFDetail
                )
                .padding()

                Divider()
                    .padding(.horizontal)

                assetRow(
                    systemImage: assetStatus.hasBGM ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: assetStatus.hasBGM ? .green : .orange,
                    title: "BGM/",
                    detail: assetStatus.hasBGM ? "Found" : "Not found. The game will play without music."
                )
                .padding()
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            Text(verbatim: assetStatus.directory.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)

            if !assetStatus.isReady || !assetStatus.hasBGM {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Copy `data.grf` and the `BGM` folder from your own kRO client (2021-04-06) into the client files folder above, then come back to this window.")
                    Text("Or run `scripts/provision-assets.sh <kRO client dir>` from the source folder.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Client Files Folder") {
                    openClientFilesFolder()
                }

                Button("Check Again") {
                    refreshAssets()
                }
            }
        }
    }

    private var playSection: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await play()
                }
            } label: {
                Text("Play")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .adaptiveProminentButtonStyle()
            .keyboardShortcut(.defaultAction)
            .disabled(!canPlay)

            switch playState {
            case .idle:
                EmptyView()
            case .testingConnection:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Contacting the server…")
                        .foregroundStyle(.secondary)
                }
            case .serverUnreachable(let message):
                VStack(spacing: 4) {
                    Text("Cannot reach the server.")
                        .fontWeight(.medium)
                    Text(verbatim: message)
                        .font(.callout)
                }
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            }

            Button("Developer Tools") {
                showsDeveloperTools = true
            }
            .buttonStyle(.link)
            .font(.callout)
            .help("Show the client file browser, servers, databases, simulators and viewers (View menu, Shift-Command-D)")
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
    }

    private func validationMessage(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func assetRow(systemImage: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .fontWeight(.medium)
                Text(verbatim: detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var dataGRFImage: (name: String, color: Color) {
        assetStatus.isReady ? ("checkmark.circle.fill", .green) : ("xmark.circle.fill", .red)
    }

    private var dataGRFDetail: String {
        switch assetStatus.dataGRF {
        case .missing:
            "Not found."
        case .unreadable:
            "Found, but the app cannot read it."
        case .notAGRF:
            "Found, but it is not a GRF archive."
        case .unsupportedVersion(let version) where version == 0x300:
            "GRF version 0x300 is not supported. Use a version 0x200 data.grf."
        case .unsupportedVersion(let version):
            "GRF version 0x\(String(version, radix: 16)) is not supported. Use a version 0x200 data.grf."
        case .valid(let version):
            "GRF version 0x\(String(version, radix: 16)), supported."
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(shortVersion) (\(version))"
    }

    // MARK: - Actions

    private func refreshAssets() {
        assetStatus = ClientAssetStatus.check(in: localClientURL)
    }

    private func openClientFilesFolder() {
        try? FileManager.default.createDirectory(at: localClientURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(localClientURL)
    }

    /// Same start sequence as the Game Client screen: check that the server is reachable, then open the game window.
    private func play() async {
        guard let address = validAddress, let port = validPort else {
            return
        }

        refreshAssets()
        guard assetStatus.isReady else {
            return
        }

        playState = .testingConnection

        let configuration = GameSession.Configuration(serverAddress: address, serverPort: port)
        if let error = await GameClientView.testConnection(configuration) {
            playState = .serverUnreachable(error.localizedDescription)
            return
        }

        playState = .idle
        openWindow(id: GameSession.windowID, value: configuration)
    }
}

#endif
