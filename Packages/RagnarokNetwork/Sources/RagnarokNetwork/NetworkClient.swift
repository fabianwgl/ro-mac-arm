//
//  NetworkClient.swift
//  RagnarokNetwork
//
//  Created by Leon Li on 2024/8/12.
//

import BinaryIO
import Foundation
import Network
import RagnarokPackets

public enum NetworkClientError: Error, Sendable {
    case decoding(any Error)
    case encoding(any Error)
    case network(NWError)
    case disconnected
}

final public class NetworkClient: Sendable {
    private let name: String
    private let connection: NWConnection
    private let recorder: PacketRecorder?

    private let encoder = PacketEncoder()
    private let decoder = PacketDecoder()

    public let errorStream: AsyncStream<NetworkClientError>
    private let errorContinuation: AsyncStream<NetworkClientError>.Continuation

    public let packetStream: AsyncStream<any DecodablePacket>
    private let packetContinuation: AsyncStream<any DecodablePacket>.Continuation

    public init(name: String, address: String, port: UInt16) {
        self.name = name
        self.recorder = PacketRecorder.fromEnvironment(clientName: name)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10

        self.connection = NWConnection(
            host: NWEndpoint.Host(address),
            port: NWEndpoint.Port(rawValue: port)!,
            using: NWParameters(tls: nil, tcp: tcp)
        )

        let (errorStream, errorContinuation) = AsyncStream<NetworkClientError>.makeStream()
        self.errorStream = errorStream
        self.errorContinuation = errorContinuation

        let (packetStream, packetContinuation) = AsyncStream<any DecodablePacket>.makeStream()
        self.packetStream = packetStream
        self.packetContinuation = packetContinuation
    }

    public func connect() {
        let name = name
        let errorContinuation = errorContinuation
        let recorder = recorder

        connection.stateUpdateHandler = { state in
            logger.info("\(name) client connection state changed: \(String(describing: state))")
            recorder?.record(.event, Data(String(describing: state).utf8))

            switch state {
            case .waiting(let error), .failed(let error):
                errorContinuation.yield(.network(error))
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "com.github.arkadeleon.ragnarok-offline.client")
        connection.start(queue: queue)
    }

    public func disconnect() {
        connection.stateUpdateHandler = nil

        connection.cancel()

        recorder?.close()

        errorContinuation.finish()
        packetContinuation.finish()
    }

    public func sendPacket(_ packet: some EncodablePacket) {
        do {
            let data = try encoder.encode(packet)
            recorder?.record(.outbound, data)

            connection.send(content: data, completion: .contentProcessed({ [weak self] error in
                if let error {
                    self?.errorContinuation.yield(.network(error))
                } else {
                    logger.info("Sent packet: \(String(describing: packet))")
                }
            }))
        } catch {
            errorContinuation.yield(.encoding(error))
        }
    }

    public func receiveDataAndPacket(count: Int, completion: @escaping @Sendable (_ data: Data) -> Void) {
        receiveDataAndPacket(count: count, buffer: Data(), completion: completion)
    }

    private func receiveDataAndPacket(count: Int, buffer: Data, completion: @escaping @Sendable (_ data: Data) -> Void) {
        connection.receive(minimumIncompleteLength: max(count - buffer.count, 1), maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                return
            }

            var buffer = buffer
            if let content {
                logger.info("Received \(content.count) bytes")

                if let recorder {
                    let prefixCount = min(content.count, max(count - buffer.count, 0))
                    if prefixCount > 0 {
                        recorder.record(.inboundPrefix, Data(content.prefix(prefixCount)))
                    }
                    if prefixCount < content.count {
                        recorder.record(.inbound, Data(content.dropFirst(prefixCount)))
                    }
                }

                buffer.append(content)
            }

            if buffer.count >= count {
                let data = buffer[0..<count]
                completion(data)

                let remaining = buffer[count...]
                do {
                    try decoder.decode(from: remaining) { packet in
                        logger.info("Received packet: \(String(describing: packet))")
                        packetContinuation.yield(packet)
                    }
                } catch {
                    logger.warning("\(error)")
                    self.errorContinuation.yield(.decoding(error))
                }
            }

            if let error {
                self.errorContinuation.yield(.network(error))
            } else if isComplete {
                self.errorContinuation.yield(.disconnected)
            } else if buffer.count < count {
                self.receiveDataAndPacket(count: count, buffer: buffer, completion: completion)
            } else {
                self.receivePacket()
            }
        }
    }

    public func receivePacket() {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                return
            }

            if let content {
                logger.info("Received \(content.count) bytes")
                recorder?.record(.inbound, content)
                do {
                    try decoder.decode(from: content) { packet in
                        logger.info("Received packet: \(String(describing: packet))")
                        packetContinuation.yield(packet)
                    }
                } catch {
                    logger.warning("\(error)")
                    self.errorContinuation.yield(.decoding(error))
                }
            }

            if let error {
                self.errorContinuation.yield(.network(error))
            } else if isComplete {
                self.errorContinuation.yield(.disconnected)
            } else {
                self.receivePacket()
            }
        }
    }
}
