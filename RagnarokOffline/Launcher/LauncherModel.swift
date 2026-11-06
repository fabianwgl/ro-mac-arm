//
//  LauncherModel.swift
//  RO Mac Client
//
//  Created by RO Mac Client contributors on 2026/11/5.
//

// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// What the launcher checks in the local client folder before it lets the player start the game.
///
/// The folder is the one the app already reads its resources from (`localClientURL`, the sandbox
/// Documents directory). Nothing here copies or modifies files.
struct ClientAssetStatus: Equatable {
    enum DataGRF: Equatable {
        case missing
        case unreadable
        case notAGRF
        case unsupportedVersion(UInt32)
        case valid(version: UInt32)
    }

    /// The only GRF container version the resource loader reads.
    static let supportedGRFVersion: UInt32 = 0x200

    private static let grfMagic = Data("Master of Magic".utf8)
    private static let grfVersionOffset = 42

    var directory: URL
    var dataGRF: DataGRF
    var hasBGM: Bool

    var isReady: Bool {
        if case .valid = dataGRF {
            return true
        }
        return false
    }

    static func check(in directory: URL, fileManager: FileManager = .default) -> ClientAssetStatus {
        ClientAssetStatus(
            directory: directory,
            dataGRF: inspectDataGRF(at: directory.appending(path: "data.grf"), fileManager: fileManager),
            hasBGM: isDirectory(directory.appending(path: "BGM"), fileManager: fileManager)
        )
    }

    /// Reads the 46 byte GRF header: `Master of Magic` at offset 0, little-endian UInt32 version at offset 42.
    static func inspectDataGRF(at url: URL, fileManager: FileManager = .default) -> DataGRF {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .missing
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unreadable
        }
        defer {
            try? handle.close()
        }

        guard let header = try? handle.read(upToCount: grfVersionOffset + 4) else {
            return .unreadable
        }
        return inspectGRFHeader(header)
    }

    static func inspectGRFHeader(_ header: Data) -> DataGRF {
        let bytes = Array(header)
        guard bytes.count >= grfVersionOffset + 4, Data(bytes.prefix(grfMagic.count)) == grfMagic else {
            return .notAGRF
        }

        let version = (0..<4).reduce(UInt32(0)) { partial, index in
            partial | UInt32(bytes[grfVersionOffset + index]) << (8 * UInt32(index))
        }
        return version == supportedGRFVersion ? .valid(version: version) : .unsupportedVersion(version)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

/// Validation of the server address and port typed into the launcher.
enum ServerEndpointInput {
    /// A port from 1 to 65535 written with ASCII digits only.
    static func port(_ text: String) -> UInt16? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 5, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = UInt16(text), port >= 1 else {
            return nil
        }
        return port
    }

    /// A host name or IP address: not empty, no whitespace, not a URL.
    static func address(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace || $0 == "/" }) else {
            return nil
        }
        return text
    }
}
