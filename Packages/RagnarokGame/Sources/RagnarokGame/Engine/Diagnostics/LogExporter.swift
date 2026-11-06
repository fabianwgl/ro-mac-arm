//
//  LogExporter.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import OSLog

public enum LogExporter {
    /// Writes entries from OSLogStore(scope: .currentProcessIdentifier) since `since`, one line
    /// each: ISO-8601 date, level, subsystem/category, message. Returns the file URL.
    public static func exportCurrentProcessLogs(to directory: URL, since: Date) throws -> URL {
        let fileNameFormatter = DateFormatter()
        fileNameFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameFormatter.dateFormat = "yyyyMMdd-HHmmss"

        let fileName = "ro-mac-client-\(fileNameFormatter.string(from: .now)).log"
        let fileURL = directory.appending(path: fileName)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let contents: String
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)
            let entries = try store.getEntries(at: position)

            contents = entries.compactMap { entry -> String? in
                guard let entry = entry as? OSLogEntryLog else {
                    return nil
                }

                let timestamp = timestampFormatter.string(from: entry.date)
                return "\(timestamp) \(entry.level) \(entry.subsystem)/\(entry.category) \(entry.composedMessage)"
            }.joined(separator: "\n")
        } catch {
            contents = "Failed to read logs: \(error.localizedDescription)"
        }

        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
