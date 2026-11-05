//
//  PacketVersionSupport.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

public struct UnsupportedPacketVersionError: Error, Sendable, Equatable, CustomStringConvertible {
    public let requested: String
    public let supported: [Int]

    public init(requested: String, supported: [Int]) {
        self.requested = requested
        self.supported = supported
    }

    public var description: String {
        let versions = supported.map { String($0) }.joined(separator: ", ")
        return "Unsupported packet version \(requested). This client supports: \(versions)."
    }
}

public enum PacketVersionSupport {
    public static let environmentKey = "RO_PACKET_VERSION"

    public static let supportedVersions: [Int] = [PACKET_VERSION]

    /// Resolve the requested packet version.
    ///
    /// A nil, empty or whitespace-only request resolves to ``PACKET_VERSION``.
    /// Otherwise the request must be exactly 8 ASCII digits forming a supported date.
    public static func resolve(requested: String?) throws(UnsupportedPacketVersionError) -> Int {
        guard let requested else {
            return PACKET_VERSION
        }

        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return PACKET_VERSION
        }

        let isEightDigits = trimmed.utf8.count == 8 && trimmed.utf8.allSatisfy { byte in
            byte >= 0x30 && byte <= 0x39
        }
        guard isEightDigits, let version = Int(trimmed), supportedVersions.contains(version) else {
            throw UnsupportedPacketVersionError(requested: trimmed, supported: supportedVersions)
        }
        return version
    }

    /// Resolve the packet version requested via ``environmentKey``.
    public static func resolveFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(UnsupportedPacketVersionError) -> Int {
        try resolve(requested: environment[environmentKey])
    }
}
