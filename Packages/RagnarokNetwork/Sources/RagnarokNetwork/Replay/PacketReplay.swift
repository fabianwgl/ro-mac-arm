//
//  PacketReplay.swift
//  RagnarokNetwork
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets

public struct PacketReplayResult: Sendable {
    public var packets: [any DecodablePacket]
    public var errors: [String]
    public var outboundCount: Int

    public init(
        packets: [any DecodablePacket] = [],
        errors: [String] = [],
        outboundCount: Int = 0
    ) {
        self.packets = packets
        self.errors = errors
        self.outboundCount = outboundCount
    }
}

public enum PacketReplay {
    /// Feeds inbound records (kind 0) record by record into a fresh PacketDecoder, exactly as the
    /// network delivered them. Prefix and event records are skipped. A decode error is collected
    /// and replay continues with the next record.
    public static func replay(_ recording: PacketRecording) -> PacketReplayResult {
        let decoder = PacketDecoder()
        var packets: [any DecodablePacket] = []
        var errors: [String] = []
        var outboundCount = 0

        for record in recording.records {
            switch record.kind {
            case .inbound:
                do {
                    try decoder.decode(from: record.payload) { packet in
                        packets.append(packet)
                    }
                } catch {
                    errors.append(String(describing: error))
                }
            case .outbound:
                outboundCount += 1
            case .inboundPrefix, .event:
                break
            }
        }

        return PacketReplayResult(
            packets: packets,
            errors: errors,
            outboundCount: outboundCount
        )
    }
}
