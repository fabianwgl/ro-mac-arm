//
//  PacketDecoder.swift
//  RagnarokPackets
//
//  Created by Leon Li on 2021/6/28.
//

import BinaryIO
import Foundation
import os

public enum PacketDecodingError: Error, Sendable {
    case packetMismatch(Int16)
    case unknownPacket(Int16)
    case invalidPacketLength(Int16, Int)
    case bufferOverflow(Int)
}

public func packetHexDump(_ data: Data, limit: Int = 256) -> String {
    guard !data.isEmpty else {
        return ""
    }

    let dumpedCount = min(data.count, max(limit, 0))
    let dumpedData = data.prefix(dumpedCount)
    var dump = dumpedData.map { String(format: "%02x", $0) }.joined(separator: " ")

    let omittedCount = data.count - dumpedCount
    if omittedCount > 0 {
        dump += " ... (+\(omittedCount) bytes)"
    }

    return dump
}

private func packetSlice(of buffer: Data, at position: Int, length: Int) -> Data {
    let start = buffer.index(buffer.startIndex, offsetBy: position)
    let end = buffer.index(start, offsetBy: length)
    return buffer[start..<end]
}

final public class PacketDecoder: Sendable {
    public static let maximumBufferedBytes = 1 << 20

    private let buffer = OSAllocatedUnfairLock(initialState: Data())

    public init() {
    }

    public func decode(from data: Data, packetHandler: (any DecodablePacket) -> Void) throws {
        try buffer.withLockUnchecked { buffer in
            buffer.append(data)

            if buffer.count > Self.maximumBufferedBytes {
                let bufferedByteCount = buffer.count
                buffer.removeAll()
                throw PacketDecodingError.bufferOverflow(bufferedByteCount)
            }

            let stream = MemoryStream(data: buffer)
            defer {
                stream.close()
            }

            let decoder = BinaryDecoder(stream: stream)

            while stream.length - stream.position >= 2 {
                let packetPosition = stream.position

                let packetType = try decoder.decode(Int16.self)

                var packetLength: Int
                if let registeredPacket = registeredPackets[packetType] {
                    packetLength = registeredPacket.size
                } else if let entry = packetDatabase.entriesByPacketType[packetType] {
                    packetLength = Int(entry.packetLength)
                } else {
                    let remainingByteCount = stream.length - packetPosition
                    let hexDump = packetHexDump(packetSlice(of: buffer, at: packetPosition, length: remainingByteCount))
                    logger.warning("Unknown packet: 0x\(UInt16(bitPattern: packetType), format: .hex, privacy: .public), remaining bytes: \(remainingByteCount, privacy: .public), data: \(hexDump, privacy: .public)")
                    buffer.removeAll()
                    throw PacketDecodingError.unknownPacket(packetType)
                }

                if packetLength == -1 {
                    if stream.length - stream.position < 2 {
                        try stream.seek(packetPosition, origin: .begin)
                        break
                    }

                    packetLength = Int(try decoder.decode(UInt16.self))

                    if packetLength < 4 {
                        buffer.removeAll()
                        throw PacketDecodingError.invalidPacketLength(packetType, packetLength)
                    }
                }

                try stream.seek(packetPosition, origin: .begin)

                if stream.length - packetPosition < packetLength {
                    break
                }

                if let registeredPacket = registeredPackets[packetType] {
                    do {
                        let packet = try registeredPacket.init(from: decoder)
                        packetHandler(packet)

                        let consumedLength = stream.position - packetPosition
                        if consumedLength != packetLength {
                            logger.warning("Packet size mismatch: 0x\(UInt16(bitPattern: packetType), format: .hex, privacy: .public), expected: \(packetLength, privacy: .public), consumed: \(consumedLength, privacy: .public)")
                        }
                    } catch {
                        let hexDump = packetHexDump(packetSlice(of: buffer, at: packetPosition, length: packetLength))
                        logger.warning("Failed to decode packet 0x\(UInt16(bitPattern: packetType), format: .hex, privacy: .public), length: \(packetLength, privacy: .public), data: \(hexDump, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                } else {
                    let hexDump = packetHexDump(packetSlice(of: buffer, at: packetPosition, length: packetLength))
                    logger.info("Unimplemented packet: 0x\(UInt16(bitPattern: packetType), format: .hex, privacy: .public), length: \(packetLength, privacy: .public), data: \(hexDump, privacy: .public)")
                }

                try stream.seek(packetPosition + packetLength, origin: .begin)
            }

            buffer.removeFirst(stream.position)
        }
    }
}
