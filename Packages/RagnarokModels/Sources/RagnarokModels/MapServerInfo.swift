//
//  MapServerInfo.swift
//  RagnarokModels
//
//  Created by Leon Li on 2024/8/26.
//

import Darwin
import RagnarokPackets

public struct MapServerInfo: Sendable {
    public var ip: String
    public var port: UInt16

    public init(ip: UInt32, port: UInt16) {
        let addri = in_addr(s_addr: ip)
        if let addrs = inet_ntoa(addri) {
            self.ip = String(cString: addrs)
        } else {
            self.ip = ""
        }

        self.port = port
    }

    public init(from packet: PACKET_HC_NOTIFY_ZONESVR) {
        self.init(ip: packet.ip, port: packet.port)
    }
}
