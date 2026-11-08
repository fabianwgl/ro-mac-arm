import Foundation
import RagnarokGRF
import RagnarokResources

/// Resolves client resources from a kRO client directory the way the app's `LocalClientResourceProvider` does:
/// a loose file under the directory first, then the GRF archives (`rdata.grf` before `data.grf`, the order of
/// `DATA.INI`).
///
/// Audio is muted by default. `GameAudioPlayer` loads BGM and sound effects through the resource manager, so
/// answering "not found" for them keeps a headless run silent without touching client code.
struct ClientFilesProvider: ResourceProvider {
    let url: URL
    let archives: [GRFArchive]
    let allowAudio: Bool
    /// Receives every audio request and whether it resolved, so a run can list what the client asked for.
    let stats: ProbeStats?

    init(url: URL, allowAudio: Bool, stats: ProbeStats? = nil) {
        self.url = url
        self.allowAudio = allowAudio
        self.stats = stats

        var archives: [GRFArchive] = []
        for name in ["rdata.grf", "data.grf"] {
            let archiveURL = url.appending(path: name)
            if FileManager.default.fileExists(atPath: archiveURL.path(percentEncoded: false)) {
                archives.append(GRFArchive(url: archiveURL))
            }
        }
        self.archives = archives
    }

    func contentsOfResource(at path: ResourcePath) async throws -> Data {
        let isAudio = path.components.last.map { $0.lowercased().hasSuffix(".wav") || $0.lowercased().hasSuffix(".mp3") } ?? false
        if !allowAudio, isAudio {
            throw ResourceError.resourceNotFound(path)
        }
        guard isAudio, let stats else {
            return try await load(path)
        }
        let name = path.components.joined(separator: "/")
        do {
            let data = try await load(path)
            stats.recordAudio(path: name, found: true, bytes: data.count, error: nil)
            return data
        } catch {
            stats.recordAudio(path: name, found: false, bytes: 0, error: "\(error)")
            throw error
        }
    }

    private func load(_ path: ResourcePath) async throws -> Data {
        let fileURL = url.absoluteURL.appending(path: L2K(path))
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            return try Data(contentsOf: fileURL)
        }

        let grfPath = GRFPath(components: path.components)
        for archive in archives {
            if let node = await archive.entryNode(at: grfPath) {
                return try await archive.contentsOfEntryNode(at: node.path)
            }
        }

        throw ResourceError.resourceNotFound(path)
    }
}
