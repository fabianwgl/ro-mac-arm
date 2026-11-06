//
//  KeyEventMonitor.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

#if os(macOS)

import AppKit
import SwiftUI

/// Installs a local key monitor for the window which hosts this view.
///
/// The handler receives every key-down event in the window and returns true when the
/// event was consumed. Key events from other windows, including sheets, are ignored.
struct KeyEventMonitor: NSViewRepresentable {
    var handler: (KeyChord, _ isTextInputFocused: Bool) -> Bool

    func makeNSView(context: Context) -> KeyMonitorHostView {
        let view = KeyMonitorHostView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: KeyMonitorHostView, context: Context) {
        context.coordinator.handler = handler
        nsView.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: KeyMonitorHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    @MainActor
    final class Coordinator {
        var handler: (KeyChord, _ isTextInputFocused: Bool) -> Bool

        private weak var window: NSWindow?
        private var monitor: Any?

        init(handler: @escaping (KeyChord, _ isTextInputFocused: Bool) -> Bool) {
            self.handler = handler
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else {
                return
            }

            detach()
            self.window = window

            guard window != nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let eventWindowID = event.window.map(ObjectIdentifier.init)
                let keyCode = event.keyCode
                let characters = event.characters
                let charactersIgnoringModifiers = event.charactersIgnoringModifiers
                let modifiers = KeyChord.Modifiers(event.modifierFlags)
                let isRepeat = event.isARepeat

                let handled = MainActor.assumeIsolated {
                    guard let self,
                          !isRepeat,
                          eventWindowID == self.window.map(ObjectIdentifier.init),
                          let chord = KeyChord(
                              keyCode: keyCode,
                              characters: characters,
                              charactersIgnoringModifiers: charactersIgnoringModifiers,
                              modifiers: modifiers
                          ) else {
                        return false
                    }

                    let isTextInputFocused = self.window?.firstResponder is NSTextView
                        || self.window?.firstResponder is NSTextField
                    return self.handler(chord, isTextInputFocused)
                }

                return handled ? nil : event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
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
