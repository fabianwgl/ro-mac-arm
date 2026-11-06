import Foundation

/// Timestamped line logger on stderr.
enum Log {
    private static let lock = NSLock()
    private static let startDate = Date()

    static func line(_ message: String) {
        let elapsed = Date().timeIntervalSince(startDate)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) [+\(String(format: "%7.1f", elapsed))s] \(message)\n"
        lock.lock()
        FileHandle.standardError.write(Data(text.utf8))
        lock.unlock()
    }
}
