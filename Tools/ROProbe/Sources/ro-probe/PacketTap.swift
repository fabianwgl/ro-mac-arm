import BinaryIO
import Darwin
import Foundation
@testable import RagnarokPackets

/// A loopback TCP relay between `GameSession` and the rAthena servers.
///
/// `GameSession` owns its `NetworkClient`s, and their packet streams are private. To count every packet by
/// opcode, including unimplemented and unknown ones that never reach the client, the probe points
/// `GameSession` at three listeners of this tap. Each accepted connection is relayed byte for byte to the real
/// server. The only edit is the address and port in `AC_ACCEPT_LOGIN` and `HC_NOTIFY_ZONESVR`, which are
/// pointed back at the tap so the char and map connections are relayed too.
///
/// Framing mirrors `PacketDecoder.decode` (registered size, else packet database length, else unknown), so the
/// tally equals what the client's decoder sees for the same bytes.
final class PacketTap: @unchecked Sendable {
    enum Role: String, Sendable, CaseIterable {
        case login, char, map
    }

    struct Endpoint: Sendable {
        var host: String
        var port: UInt16
    }

    let stats: ProbeStats

    /// Split a CZ_ENTER that left the client in the same TCP segment as the following packet.
    /// See the client bug notes in the report. Off with `--no-enter-workaround`.
    let splitEnter: Bool

    private let lock = NSLock()
    private var upstreams: [Role: Endpoint]
    private var listenerDescriptors: [Role: Int32] = [:]
    private var listenerPorts: [Role: UInt16] = [:]
    private var running = true

    init(stats: ProbeStats, loginUpstream: Endpoint, splitEnter: Bool) {
        self.stats = stats
        self.splitEnter = splitEnter
        self.upstreams = [.login: loginUpstream]
        signal(SIGPIPE, SIG_IGN)
    }

    func port(for role: Role) -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return listenerPorts[role] ?? 0
    }

    func setUpstream(_ endpoint: Endpoint, for role: Role) {
        lock.lock()
        upstreams[role] = endpoint
        lock.unlock()
    }

    private func upstream(for role: Role) -> Endpoint? {
        lock.lock()
        defer { lock.unlock() }
        return upstreams[role]
    }

    // MARK: - Lifecycle

    func start() throws {
        for role in Role.allCases {
            try listen(role)
        }
        Log.line("tap listening: login \(port(for: .login)), char \(port(for: .char)), map \(port(for: .map))")
    }

    func stop() {
        lock.lock()
        running = false
        let descriptors = Array(listenerDescriptors.values)
        lock.unlock()
        for descriptor in descriptors {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func listen(_ role: Role) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw TapError("socket() failed: \(String(cString: strerror(errno)))")
        }

        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw TapError("bind() failed: \(String(cString: strerror(errno)))")
        }
        guard Darwin.listen(descriptor, 16) == 0 else {
            throw TapError("listen() failed: \(String(cString: strerror(errno)))")
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }

        lock.lock()
        listenerDescriptors[role] = descriptor
        listenerPorts[role] = UInt16(bigEndian: bound.sin_port)
        lock.unlock()

        Thread.detachNewThread { [self] in
            acceptLoop(descriptor: descriptor, role: role)
        }
    }

    private func acceptLoop(descriptor: Int32, role: Role) {
        while isRunning {
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR {
                    continue
                }
                break
            }
            Thread.detachNewThread { [self] in
                handle(client: client, role: role)
            }
        }
    }

    // MARK: - Relay

    private func handle(client: Int32, role: Role) {
        guard let endpoint = upstream(for: role) else {
            stats.recordError("tap \(role.rawValue): no upstream known")
            close(client)
            return
        }

        guard let server = connectUpstream(endpoint) else {
            stats.recordError("tap \(role.rawValue): cannot connect to \(endpoint.host):\(endpoint.port): \(String(cString: strerror(errno)))")
            // Closing the client side is what the real client sees when the server is down.
            close(client)
            return
        }

        for descriptor in [client, server] {
            var one: Int32 = 1
            setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        }

        stats.recordConnection(role: role.rawValue)
        Log.line("tap \(role.rawValue): relaying to \(endpoint.host):\(endpoint.port)")

        let connection = Connection(client: client, server: server)
        let serverToClient = StreamFramer(tap: self, role: role, direction: .serverToClient)
        let clientToServer = StreamFramer(tap: self, role: role, direction: .clientToServer)

        Thread.detachNewThread { [self] in
            pump(from: server, to: client, connection: connection, role: role, label: "server closed") {
                serverToClient.process($0)
            }
        }
        pump(from: client, to: server, connection: connection, role: role, label: "client closed") {
            clientToServer.process($0)
        }
    }

    private func pump(from source: Int32, to destination: Int32, connection: Connection, role: Role, label: String, transform: (Data) -> [Data]) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        outer: while true {
            let count = read(source, &buffer, buffer.count)
            if count <= 0 {
                break
            }
            let segments = transform(Data(buffer[0..<count]))
            for (index, segment) in segments.enumerated() {
                if index > 0 {
                    // Segments exist only to keep the map server's connect packet alone in its TCP read.
                    usleep(150_000)
                }
                if !segment.isEmpty, !writeAll(destination, segment) {
                    break outer
                }
            }
        }
        Log.line("tap \(role.rawValue): \(label)")
        shutdown(source, SHUT_RDWR)
        shutdown(destination, SHUT_RDWR)
        connection.finishOne()
    }

    private func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if written <= 0 {
                    if written < 0 && errno == EINTR {
                        continue
                    }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private func connectUpstream(_ endpoint: Endpoint) -> Int32? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(endpoint.host, String(endpoint.port), &hints, &result) == 0, let result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        let descriptor = socket(result.pointee.ai_family, result.pointee.ai_socktype, result.pointee.ai_protocol)
        guard descriptor >= 0 else {
            return nil
        }
        guard connect(descriptor, result.pointee.ai_addr, result.pointee.ai_addrlen) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private final class Connection: @unchecked Sendable {
        let client: Int32
        let server: Int32
        private let lock = NSLock()
        private var finished = 0

        init(client: Int32, server: Int32) {
            self.client = client
            self.server = server
        }

        func finishOne() {
            lock.lock()
            finished += 1
            let done = finished == 2
            lock.unlock()
            if done {
                close(client)
                close(server)
            }
        }
    }

    struct TapError: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) {
            self.description = description
        }
    }
}

/// Splits one direction of a relayed connection into packets, tallies them, and patches addresses.
final class StreamFramer: @unchecked Sendable {
    enum Direction {
        case serverToClient, clientToServer
    }

    private unowned let tap: PacketTap
    private let role: PacketTap.Role
    private let direction: Direction
    private var buffer: [UInt8] = []
    private var prefixRemaining: Int
    private var framesSeen = 0

    private var stats: ProbeStats { tap.stats }

    init(tap: PacketTap, role: PacketTap.Role, direction: Direction) {
        self.tap = tap
        self.role = role
        self.direction = direction
        // `GameSession.startCharClient` reads 4 raw bytes (the account id) before the first packet.
        // `PlaySession.start` does the same only for PACKET_VERSION < 20070521.
        if direction == .serverToClient {
            switch role {
            case .char: prefixRemaining = 4
            case .map: prefixRemaining = PACKET_VERSION < 20070521 ? 4 : 0
            case .login: prefixRemaining = 0
            }
        } else {
            prefixRemaining = 0
        }
    }

    func process(_ chunk: Data) -> [Data] {
        var chunk = chunk
        var output = Data()
        var firstFrameLength: Int?

        if prefixRemaining > 0 {
            let take = min(prefixRemaining, chunk.count)
            output.append(chunk.prefix(take))
            chunk = Data(chunk.dropFirst(take))
            prefixRemaining -= take
        }

        buffer.append(contentsOf: chunk)

        var position = 0
        while buffer.count - position >= 2 {
            let type = Int16(bitPattern: UInt16(buffer[position]) | UInt16(buffer[position + 1]) << 8)
            let opcode = Int(UInt16(bitPattern: type))
            let registered = direction == .serverToClient ? registeredPackets[type] : nil
            let entry = packetDatabase.entriesByPacketType[type]
            let sentEntry = direction == .clientToServer ? SentPacketTable.entries[opcode] : nil

            var length: Int
            if let registered {
                length = registered.size
            } else if let sentEntry {
                length = sentEntry.length
            } else if let entry {
                length = Int(entry.packetLength)
            } else {
                recordUnknown(opcode: opcode, remaining: buffer.count - position)
                output.append(contentsOf: buffer[position...])
                buffer.removeAll()
                return [output]
            }

            if length == -1 {
                if buffer.count - position < 4 {
                    break
                }
                length = Int(UInt16(buffer[position + 2]) | UInt16(buffer[position + 3]) << 8)
                if length < 4 {
                    stats.recordError("tap \(role.rawValue): invalid length \(length) for opcode 0x\(String(format: "%04x", opcode))")
                    stats.recordDesync()
                    output.append(contentsOf: buffer[position...])
                    buffer.removeAll()
                    return [output]
                }
            } else if length < 2 {
                stats.recordError("tap \(role.rawValue): bad table length \(length) for opcode 0x\(String(format: "%04x", opcode))")
                stats.recordDesync()
                output.append(contentsOf: buffer[position...])
                buffer.removeAll()
                return [output]
            }

            if buffer.count - position < length {
                break
            }

            var frame = Array(buffer[position..<position + length])
            switch direction {
            case .serverToClient:
                classifyReceived(frame, type: type, opcode: opcode, registered: registered, entry: entry)
                patchAddress(&frame, opcode: opcode)
            case .clientToServer:
                let name = sentEntry?.name ?? PacketNames.name(for: opcode) ?? entry?.functionName
                stats.recordSent(opcode: opcode, name: name, bytes: length, payload: Array(frame.prefix(48)))
            }
            if direction == .clientToServer, role == .map, framesSeen == 0 {
                firstFrameLength = output.count + frame.count
            }
            framesSeen += 1
            output.append(contentsOf: frame)
            position += length
        }

        buffer.removeFirst(position)

        // rAthena checks the connect packet against everything buffered, so a CZ_ENTER followed in the same
        // read by CZ_REQUEST_TIME (what PlaySession.start does) is refused as "wrong length".
        if let firstFrameLength, output.count > firstFrameLength {
            stats.recordClientBug("map connect packet shared a TCP read with \(output.count - firstFrameLength) more bytes")
            if tap.splitEnter {
                return [Data(output.prefix(firstFrameLength)), Data(output.dropFirst(firstFrameLength))]
            }
        }
        return [output]
    }

    private func recordUnknown(opcode: Int, remaining: Int) {
        switch direction {
        case .serverToClient:
            stats.recordReceived(opcode: opcode, name: PacketNames.name(for: opcode), kind: "unknown", bytes: remaining, role: role.rawValue)
            Log.line("tap \(role.rawValue): UNKNOWN server packet 0x\(String(format: "%04x", opcode)) with \(remaining) bytes buffered")
        case .clientToServer:
            stats.recordSent(opcode: opcode, name: PacketNames.name(for: opcode).map { $0 + " (not in packet database)" } ?? "(not in packet database)", bytes: remaining)
            Log.line("tap \(role.rawValue): client sent opcode 0x\(String(format: "%04x", opcode)) that is not in the packet database")
        }
        stats.recordDesync()
    }

    private func classifyReceived(
        _ frame: [UInt8],
        type: Int16,
        opcode: Int,
        registered: (any DecodablePacket.Type)?,
        entry: PacketDatabase.Entry?
    ) {
        let roleName = role.rawValue

        if let registered {
            let name = String(describing: registered)

            // The decoder trusts the registered size. When the database says the packet is variable length,
            // the length field on the wire must agree with it.
            var mismatch = false
            if registered.size != -1, entry?.packetLength == -1, frame.count >= 4 {
                let wireLength = Int(UInt16(frame[2]) | UInt16(frame[3]) << 8)
                mismatch = wireLength != frame.count
            }

            do {
                let decoder = BinaryDecoder(data: Data(frame))
                let packet = try registered.init(from: decoder)
                stats.recordReceived(opcode: opcode, name: name, kind: "decoded", bytes: frame.count, role: roleName, lengthMismatch: mismatch)
                observe(packet)
            } catch {
                stats.recordReceived(opcode: opcode, name: name, kind: "decodeFailure", bytes: frame.count, role: roleName, lengthMismatch: mismatch, error: "\(error)")
                Log.line("tap \(roleName): decode failed for \(name) 0x\(String(format: "%04x", opcode)): \(error)")
            }
        } else {
            let name = PacketNames.name(for: opcode) ?? entry?.functionName
            stats.recordReceived(opcode: opcode, name: name, kind: "unimplemented", bytes: frame.count, role: roleName)
        }
    }

    private func observe(_ packet: any DecodablePacket) {
        switch packet {
        case let packet as PACKET_HC_ACCEPT_MAKECHAR:
            stats.recordNote("HC_ACCEPT_MAKECHAR charID \(packet.character.GID) name \(packet.character.name)")
        case let packet as PACKET_HC_REFUSE_MAKECHAR:
            stats.recordNote("HC_REFUSE_MAKECHAR error \(packet.error)")
        case let packet as PACKET_HC_DELETE_CHAR3_RESERVED:
            stats.recordNote("HC_DELETE_CHAR3_RESERVED charID \(packet.CID) result \(packet.result) date \(packet.date)")
        case let packet as PACKET_HC_DELETE_CHAR3:
            stats.recordNote("HC_DELETE_CHAR3 charID \(packet.CID) result \(packet.result)")
        case let packet as PACKET_HC_REFUSE_ENTER:
            stats.recordNote("HC_REFUSE_ENTER error \(packet.error)")
        case let packet as PACKET_ZC_REFUSE_ENTER:
            stats.recordNote("ZC_REFUSE_ENTER errorCode \(packet.errorCode)")
        case let packet as packet_idle_unit where packet.objecttype == 5:
            stats.recordMonster(id: packet.AID)
        case let packet as packet_spawn_unit where packet.objecttype == 5:
            stats.recordMonster(id: packet.AID)
        case let packet as packet_unit_walking where packet.objecttype == 5:
            stats.recordMonster(id: packet.AID)
        default:
            break
        }
    }

    /// Points the char and map server addresses at the tap.
    private func patchAddress(_ frame: inout [UInt8], opcode: Int) {
        switch role {
        case .login where Int16(truncatingIfNeeded: opcode) == HEADER_AC_ACCEPT_LOGIN:
            // 0xac4: 64 byte header, then 160 byte entries (ip 4, port 2, name 20, ...).
            // Before 20170315 (0x69): 47 byte header and 32 byte entries.
            let headerSize = PACKET_VERSION >= 20170315 ? 64 : 47
            let entrySize = PACKET_VERSION >= 20170315 ? 160 : 32
            var offset = headerSize
            var first = true
            while offset + 6 <= frame.count {
                let port = UInt16(frame[offset + 4]) | UInt16(frame[offset + 5]) << 8
                let host = "\(frame[offset]).\(frame[offset + 1]).\(frame[offset + 2]).\(frame[offset + 3])"
                if first {
                    tap.setUpstream(PacketTap.Endpoint(host: host, port: port), for: .char)
                    Log.line("tap login: char server advertised as \(host):\(port), redirecting to tap port \(tap.port(for: .char))")
                    first = false
                }
                let tapPort = tap.port(for: .char)
                frame[offset] = 127
                frame[offset + 1] = 0
                frame[offset + 2] = 0
                frame[offset + 3] = 1
                frame[offset + 4] = UInt8(tapPort & 0xff)
                frame[offset + 5] = UInt8(tapPort >> 8)
                offset += entrySize
            }
        case .char where Int16(truncatingIfNeeded: opcode) == HEADER_HC_NOTIFY_ZONESVR:
            // 2 type, 4 char id, 16 map name, 4 ip, 2 port.
            guard frame.count >= 28 else {
                return
            }
            let port = UInt16(frame[26]) | UInt16(frame[27]) << 8
            let host = "\(frame[22]).\(frame[23]).\(frame[24]).\(frame[25])"
            tap.setUpstream(PacketTap.Endpoint(host: host, port: port), for: .map)
            let tapPort = tap.port(for: .map)
            Log.line("tap char: map server advertised as \(host):\(port), redirecting to tap port \(tapPort)")
            frame[22] = 127
            frame[23] = 0
            frame[24] = 0
            frame[25] = 1
            frame[26] = UInt8(tapPort & 0xff)
            frame[27] = UInt8(tapPort >> 8)
        default:
            break
        }
    }
}
