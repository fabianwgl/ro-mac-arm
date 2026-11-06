//
//  SessionMarker.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

public struct SessionMarker: Sendable {
    public struct PreviousSession: Sendable, Equatable {
        public var startedAt: Date
        public var appVersion: String
        public var pid: Int32

        public init(startedAt: Date, appVersion: String, pid: Int32) {
            self.startedAt = startedAt
            self.appVersion = appVersion
            self.pid = pid
        }
    }

    private struct Marker: Codable {
        var startedAt: Date
        var appVersion: String
        var pid: Int32
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "RagnarokOffline"
        return applicationSupportURL
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    /// Reads any leftover marker (= previous run did not exit cleanly), then writes a new marker
    /// for this run. Returns the previous session if there was one.
    public func begin(appVersion: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier, now: Date = .now) throws -> PreviousSession? {
        let previousSession = previousSession()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let marker = Marker(startedAt: now, appVersion: appVersion, pid: pid)
        let data = try JSONEncoder().encode(marker)
        try data.write(to: markerURL, options: .atomic)

        return previousSession
    }

    /// Removes the marker (clean exit).
    public func end() throws {
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: markerURL)
    }

    private var markerURL: URL {
        directory.appending(path: "session.json")
    }

    private func previousSession() -> PreviousSession? {
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else {
            return PreviousSession(startedAt: .distantPast, appVersion: "unknown", pid: 0)
        }

        return PreviousSession(startedAt: marker.startedAt, appVersion: marker.appVersion, pid: marker.pid)
    }
}
