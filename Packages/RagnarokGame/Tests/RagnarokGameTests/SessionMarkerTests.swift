import Foundation
import Testing
@testable import RagnarokGame

struct SessionMarkerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func firstBeginReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let marker = SessionMarker(directory: directory)
        let previousSession = try marker.begin(appVersion: "1.0", pid: 42)

        #expect(previousSession == nil)
    }

    @Test func secondBeginReturnsFirstSession() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let marker = SessionMarker(directory: directory)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try marker.begin(appVersion: "1.0", pid: 42, now: startedAt)

        let previousSession = try marker.begin(appVersion: "2.0", pid: 43)

        #expect(previousSession == SessionMarker.PreviousSession(startedAt: startedAt, appVersion: "1.0", pid: 42))
    }

    @Test func beginEndBeginReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let marker = SessionMarker(directory: directory)
        _ = try marker.begin(appVersion: "1.0", pid: 42)
        try marker.end()

        let previousSession = try marker.begin(appVersion: "1.0", pid: 42)

        #expect(previousSession == nil)
    }

    @Test func corruptMarkerReturnsFallbackSession() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let markerURL = directory.appending(path: "session.json")
        try Data("not json".utf8).write(to: markerURL)

        let marker = SessionMarker(directory: directory)
        let previousSession = try marker.begin(appVersion: "1.0", pid: 42)

        #expect(previousSession == SessionMarker.PreviousSession(startedAt: .distantPast, appVersion: "unknown", pid: 0))
    }

    @Test func endWithoutMarkerDoesNotThrow() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let marker = SessionMarker(directory: directory)
        try marker.end()
    }
}
