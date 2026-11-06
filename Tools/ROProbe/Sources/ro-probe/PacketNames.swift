import Foundation

/// Opcode to packet names, read from the generated `packets.swift` of RagnarokPackets.
///
/// The names exist only as Swift constants, so the table is built by scanning the source file next to this
/// package in the repository. Without the file, names fall back to the implemented struct name or the
/// rAthena function name from the packet database.
enum PacketNames {
    private static let names: [Int: [String]] = load()

    static var allOpcodes: [Int: [String]] {
        names
    }

    /// Opcodes the server sends that have no generated constant.
    private static let extraNames: [Int: String] = [
        0x08e2: "ZC_NAVIGATE_TO (clif_navigateTo)",
    ]

    static func name(for opcode: Int) -> String? {
        guard let list = names[opcode], !list.isEmpty else {
            return extraNames[opcode]
        }
        return list.prefix(3).joined(separator: " | ")
    }

    private static func load() -> [Int: [String]] {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ro-probe
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // ROProbe
            .deletingLastPathComponent() // Tools
            .deletingLastPathComponent() // repo root
            .appending(path: "Packages/RagnarokPackets/Sources/RagnarokPackets/Generated/packets.swift")

        guard let text = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return [:]
        }

        guard let regex = try? NSRegularExpression(pattern: #"public let (HEADER_\w+|packet_header_(\w+?)Type): Int16 = 0x([0-9a-fA-F]+)"#) else {
            return [:]
        }

        var result: [Int: [String]] = [:]
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 3), in: text),
                  let value = Int(text[valueRange], radix: 16) else {
                return
            }

            var name = String(text[nameRange])
            if name.hasPrefix("packet_header_"), let shortRange = Range(match.range(at: 2), in: text) {
                name = "packet_" + String(text[shortRange])
            }
            if !(result[value]?.contains(name) ?? false) {
                result[value, default: []].append(name)
            }
        }
        return result
    }
}
