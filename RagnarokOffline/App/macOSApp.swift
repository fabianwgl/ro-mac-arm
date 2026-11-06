//
//  macOSApp.swift
//  RagnarokOffline
//
//  Created by Leon Li on 2026/2/28.
//

#if os(macOS)

import AppKit
import RagnarokGame
import SwiftUI

@main
struct macOSApp: App {
    @Environment(\.dismissWindow) private var dismissWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appModel = AppModel()

    private let launchDate = Date()

    var body: some Scene {
        WindowGroup(id: appModel.mainWindowID) {
            MainWindowView()
                .environment(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                }
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Export Logs…") {
                    exportLogs()
                }
            }
        }

        WindowGroup("Game", id: GameSession.windowID, for: GameSession.Configuration.self) { configuration in
            GameView(gameSession: appModel.gameSession)
                .onAppear {
                    if let configuration = configuration.wrappedValue {
                        appModel.gameSession.start(configuration)
                    } else {
                        let configuration = GameSession.Configuration(
                            serverAddress: appModel.settings.serverAddress,
                            serverPort: UInt16(appModel.settings.serverPort)!
                        )
                        appModel.gameSession.start(configuration)
                    }
                }
                .onDisappear {
                    appModel.gameSession.stop()
                }
                .onExitGame {
                    dismissWindow(id: GameSession.windowID)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        // Scene commands are app-wide: this adds View > Developer Tools, which swaps the launcher for the upstream tool sidebar.
        .commands {
            DeveloperToolsCommands()
        }
    }

    init() {
        configureTips()
    }

    private func exportLogs() {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let directory = libraryURL.appending(path: "Logs/RO Mac Client", directoryHint: .isDirectory)

        guard let fileURL = try? LogExporter.exportCurrentProcessLogs(to: directory, since: launchDate) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppModel? {
        didSet {
            appModel?.previousUncleanExit = previousUncleanExit
        }
    }

    private let sessionMarker = SessionMarker(directory: SessionMarker.defaultDirectory())
    private var previousUncleanExit: SessionMarker.PreviousSession?

    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        previousUncleanExit = try? sessionMarker.begin(appVersion: appVersion)
        appModel?.previousUncleanExit = previousUncleanExit
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? sessionMarker.end()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel else {
            return .terminateNow
        }

        guard !isTerminating else {
            return .terminateLater
        }

        isTerminating = true

        Task {
            await appModel.serverManager.stopAllServers()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

#endif
