//
//  PacketRecording.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import os

public struct PacketRecord: Sendable, Equatable {
    public enum Kind: UInt8, Sendable, Equatable {
        case inbound = 0
        case outbound = 1
        case inboundPrefix = 2
        case event = 3
    }

    public var milliseconds: UInt32
    public var kind: Kind
    public var payload: Data

    public init(milliseconds: UInt32, kind: Kind, payload: Data) {
        self.milliseconds = milliseconds
        self.kind = kind
        self.payload = payload
    }
}

public struct PacketRecording: Sendable, Equatable {
    public var clientName: String
    public var startTime: Date
    public var records: [PacketRecord]

    public init(clientName: String, startTime: Date, records: [PacketRecord]) {
        self.clientName = clientName
        self.startTime = startTime
        self.records = records
    }

    public init(data: Data) throws {
        var reader = PacketRecordingReader(data: data)

        guard try reader.readBytes(4) == recordingMagic else {
            throw PacketRecordingError.badMagic
        }

        let version = try reader.readInteger(UInt16.self)
        guard version == recordingVersion else {
            throw PacketRecordingError.unsupportedVersion(version)
        }

        let nameLength = Int(try reader.readInteger(UInt16.self))
        let nameData = try reader.readBytes(nameLength)
        let startMilliseconds = try reader.readInteger(UInt64.self)

        var records: [PacketRecord] = []
        while reader.remaining > 0 {
            let milliseconds = try reader.readInteger(UInt32.self)
            let kindRawValue = try reader.readInteger(UInt8.self)
            guard let kind = PacketRecord.Kind(rawValue: kindRawValue) else {
                throw PacketRecordingError.truncated
            }
            let payloadLength = Int(try reader.readInteger(UInt32.self))
            let payload = try reader.readBytes(payloadLength)
            records.append(PacketRecord(milliseconds: milliseconds, kind: kind, payload: payload))
        }

        self.clientName = String(decoding: nameData, as: UTF8.self)
        self.startTime = Date(timeIntervalSince1970: Double(startMilliseconds) / 1000)
        self.records = records
    }

    public func encoded() -> Data {
        var data = recordingHeader(clientName: clientName, startTime: startTime)

        for record in records {
            data.appendLittleEndian(record.milliseconds)
            data.append(record.kind.rawValue)
            data.appendLittleEndian(UInt32(record.payload.count))
            data.append(record.payload)
        }

        return data
    }
}

public enum PacketRecordingError: Error, Sendable, Equatable {
    case badMagic
    case unsupportedVersion(UInt16)
    case truncated
}

final public class PacketRecorder: Sendable {
    public static let environmentKey = "RO_PACKET_RECORD_DIR"

    private struct State: @unchecked Sendable {
        var fileHandle: FileHandle?
    }

    public let fileURL: URL

    private let startTime: Date
    private let lock: OSAllocatedUnfairLock<State>

    public init(directory: URL, clientName: String, now: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(Self.fileName(clientName: clientName, now: now))
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.write(contentsOf: recordingHeader(clientName: clientName, startTime: now))

        self.fileURL = fileURL
        self.startTime = now
        self.lock = OSAllocatedUnfairLock(initialState: State(fileHandle: fileHandle))
    }

    public static func fromEnvironment(
        clientName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PacketRecorder? {
        guard let directory = environment[environmentKey], !directory.isEmpty else {
            return nil
        }

        do {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            return try PacketRecorder(directory: url, clientName: clientName)
        } catch {
            logger.warning("Failed to create packet recorder: \(error)")
            return nil
        }
    }

    public func record(_ kind: PacketRecord.Kind, _ payload: Data) {
        let milliseconds = elapsedMilliseconds(since: startTime, now: .now)

        lock.withLock { state in
            guard let fileHandle = state.fileHandle else {
                return
            }

            var data = Data()
            data.appendLittleEndian(milliseconds)
            data.append(kind.rawValue)
            data.appendLittleEndian(UInt32(payload.count))
            data.append(payload)

            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                logger.warning("Failed to write packet record: \(error)")
            }
        }
    }

    public func close() {
        lock.withLock { state in
            guard let fileHandle = state.fileHandle else {
                return
            }

            state.fileHandle = nil

            do {
                try fileHandle.close()
            } catch {
                logger.warning("Failed to close packet recording: \(error)")
            }
        }
    }

    private static func fileName(clientName: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: now)
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        return "\(timestamp)-\(clientName)-\(processIdentifier).rorec"
    }
}

private let recordingMagic = Data("RORC".utf8)
private let recordingVersion: UInt16 = 1

private func recordingHeader(clientName: String, startTime: Date) -> Data {
    let nameData = Data(clientName.utf8)
    let startMilliseconds = UInt64(max((startTime.timeIntervalSince1970 * 1000).rounded(), 0))

    var data = Data()
    data.append(recordingMagic)
    data.appendLittleEndian(recordingVersion)
    data.appendLittleEndian(UInt16(nameData.count))
    data.append(nameData)
    data.appendLittleEndian(startMilliseconds)
    return data
}

private func elapsedMilliseconds(since startTime: Date, now: Date) -> UInt32 {
    let milliseconds = (now.timeIntervalSince(startTime) * 1000).rounded()
    return UInt32(clamping: Int64(max(milliseconds, 0)))
}

private struct PacketRecordingReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    var remaining: Int {
        data.count - offset
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else {
            throw PacketRecordingError.truncated
        }

        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        offset += count
        return Data(data[start..<end])
    }

    mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let bytes = try readBytes(MemoryLayout<T>.size)

        var value: T = 0
        for index in 0..<bytes.count {
            let byte = bytes[bytes.index(bytes.startIndex, offsetBy: index)]
            value |= T(byte) << (8 * index)
        }
        return value
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        for index in 0..<MemoryLayout<T>.size {
            append(UInt8(truncatingIfNeeded: value >> (8 * index)))
        }
    }
}
