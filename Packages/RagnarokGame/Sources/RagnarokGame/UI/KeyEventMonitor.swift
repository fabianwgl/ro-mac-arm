//
//  KeyEventMonitor.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

#if os(macOS)

import AppKit
import SwiftUI

/// A key press or release in the game window.
struct KeyEvent {
    enum Phase {
        case down
        case up
    }

    var phase: Phase
    /// The binding the key and modifiers form, or nil for keys no binding can use.
    var chord: KeyChord?
    /// The physical key, so a release matches its press even if modifiers changed in between.
    var keyCode: UInt16
    var isRepeat: Bool
    var isTextInputFocused: Bool
}

/// Installs a local key monitor for the window which hosts this view.
///
/// The handler receives every key-down and key-up event in the window and returns true
/// when the event was consumed. Key events from other windows, including sheets, are
/// ignored. `onFocusLost` runs when the window stops being the key window, because key-up
/// events for keys still held then never arrive. `onFocusGained` runs when it becomes the
/// key window, and once when the monitor attaches to a window which already is.
struct KeyEventMonitor: NSViewRepresentable {
    var handler: (KeyEvent) -> Bool
    var onFocusLost: () -> Void = {}
    var onFocusGained: () -> Void = {}

    func makeNSView(context: Context) -> KeyMonitorHostView {
        let view = KeyMonitorHostView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: KeyMonitorHostView, context: Context) {
        context.coordinator.handler = handler
        context.coordinator.onFocusLost = onFocusLost
        context.coordinator.onFocusGained = onFocusGained
        nsView.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: KeyMonitorHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler, onFocusLost: onFocusLost, onFocusGained: onFocusGained)
    }

    @MainActor
    final class Coordinator {
        var handler: (KeyEvent) -> Bool
        var onFocusLost: () -> Void
        var onFocusGained: () -> Void

        private weak var window: NSWindow?
        private var monitor: Any?
        private var resignKeyObserver: (any NSObjectProtocol)?
        private var becomeKeyObserver: (any NSObjectProtocol)?

        init(handler: @escaping (KeyEvent) -> Bool, onFocusLost: @escaping () -> Void, onFocusGained: @escaping () -> Void) {
            self.handler = handler
            self.onFocusLost = onFocusLost
            self.onFocusGained = onFocusGained
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else {
                return
            }

            detach()
            self.window = window

            guard let window else {
                return
            }

            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onFocusLost()
                }
            }

            becomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onFocusGained()
                }
            }

            if window.isKeyWindow {
                // Attaching can happen during a view update, so report the focus afterwards.
                Task { @MainActor [weak self, weak window] in
                    if let self, let window, self.window === window, window.isKeyWindow {
                        self.onFocusGained()
                    }
                }
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                let eventWindowID = event.window.map(ObjectIdentifier.init)
                let phase: KeyEvent.Phase = event.type == .keyUp ? .up : .down
                let keyCode = event.keyCode
                let characters = event.characters
                let charactersIgnoringModifiers = event.charactersIgnoringModifiers
                let modifiers = KeyChord.Modifiers(event.modifierFlags)
                let isRepeat = phase == .down && event.isARepeat

                let handled = MainActor.assumeIsolated {
                    guard let self,
                          eventWindowID == self.window.map(ObjectIdentifier.init) else {
                        return false
                    }

                    let chord = KeyChord(
                        keyCode: keyCode,
                        characters: characters,
                        charactersIgnoringModifiers: charactersIgnoringModifiers,
                        modifiers: modifiers
                    )
                    let isTextInputFocused = self.window?.firstResponder is NSTextView
                        || self.window?.firstResponder is NSTextField
                    return self.handler(KeyEvent(
                        phase: phase,
                        chord: chord,
                        keyCode: keyCode,
                        isRepeat: isRepeat,
                        isTextInputFocused: isTextInputFocused
                    ))
                }

                return handled ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            if let resignKeyObserver {
                NotificationCenter.default.removeObserver(resignKeyObserver)
            }
            if let becomeKeyObserver {
                NotificationCenter.default.removeObserver(becomeKeyObserver)
            }
            monitor = nil
            resignKeyObserver = nil
            becomeKeyObserver = nil
            window = nil
        }
    }
}

final class KeyMonitorHostView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The monitor only listens for key events; it must not cover the game view.
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}

private extension KeyChord.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyChord.Modifiers = []

        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }

        self = modifiers
    }
}

#endif
