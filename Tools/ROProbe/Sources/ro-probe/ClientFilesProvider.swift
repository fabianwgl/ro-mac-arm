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

    init(url: URL, allowAudio: Bool) {
        self.url = url
        self.allowAudio = allowAudio

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
        if !allowAudio, let last = path.components.last?.lowercased(), last.hasSuffix(".wav") || last.hasSuffix(".mp3") {
            throw ResourceError.resourceNotFound(path)
        }

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
