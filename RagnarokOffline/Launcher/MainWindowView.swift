//
//  MainWindowView.swift
//  RO Mac Client
//
//  Created by RO Mac Client contributors on 2026/11/5.
//

// SPDX-License-Identifier: GPL-3.0-only

#if os(macOS)

import AppKit
import SwiftUI

enum DeveloperTools {
    /// UserDefaults key. When true the main window shows the upstream tool sidebar instead of the launcher.
    static let defaultsKey = "app.showsDeveloperTools"
}

/// Content of the macOS main window: the launcher by default, or the upstream `ContentView`
/// (client files, servers, databases, simulators, viewers) when Developer Tools are on.
///
/// This is a thin shell so `ContentView` and the tools behind it stay identical to upstream.
struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel

    @AppStorage(DeveloperTools.defaultsKey) private var showsDeveloperTools = false

    var body: some View {
        Group {
            if showsDeveloperTools {
                ContentView()
            } else {
                LauncherView(settings: appModel.settings)
            }
        }
        .alert(uncleanExitAlertTitle, isPresented: isUncleanExitAlertPresented) {
            Button("Open Crash Reports") {
                openCrashReports()
            }
            Button("OK", role: .cancel) {}
        }
    }

    private var uncleanExitAlertTitle: String {
        let startedAt = appModel.previousUncleanExit?.startedAt.formatted(date: .numeric, time: .shortened) ?? "unknown"
        return "RO Mac Client did not quit cleanly last time (started \(startedAt)). Crash reports are in ~/Library/Logs/DiagnosticReports."
    }

    private var isUncleanExitAlertPresented: Binding<Bool> {
        Binding {
            appModel.previousUncleanExit != nil
        } set: { isPresented in
            if !isPresented {
                appModel.previousUncleanExit = nil
            }
        }
    }

    /// The app is sandboxed, so the user's real Library is resolved from the home directory
    /// path rather than `FileManager` (which returns the container).
    private func openCrashReports() {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let directoryURL = URL(filePath: home).appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        NSWorkspace.shared.open(directoryURL)
    }
}

/// View menu item that switches the main window between the launcher and the developer tools.
struct DeveloperToolsCommands: Commands {
    @AppStorage(DeveloperTools.defaultsKey) private var showsDeveloperTools = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Developer Tools", isOn: $showsDeveloperTools)
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

#endif
