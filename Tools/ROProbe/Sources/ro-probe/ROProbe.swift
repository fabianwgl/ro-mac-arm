import Foundation
import RagnarokResources

@main
struct ROProbe {
    @MainActor
    static func main() async {
        let options: Options
        do {
            options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("ro-probe: \(error)\n\n\(Options.usage)\n".utf8))
            exit(2)
        }

        if options.coverageOnly {
            let coverage = Coverage.compute()
            Coverage.printSummary(coverage)
            if let path = options.jsonPath {
                if let data = try? JSONSerialization.data(withJSONObject: coverage, options: [.prettyPrinted, .sortedKeys]) {
                    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
            exit(0)
        }

        if options.tradeTest {
            exit(await TradeScenario.run(options: options) ? 0 : 1)
        }

        let stats = ProbeStats()
        stats.setTapEnabled(!options.noTap)

        let clientURL = URL(fileURLWithPath: options.clientDir, isDirectory: true)
        guard FileManager.default.fileExists(atPath: clientURL.appending(path: "data.grf").path(percentEncoded: false)) else {
            Log.line("data.grf not found in \(options.clientDir)")
            exit(2)
        }
        let provider = ClientFilesProvider(url: clientURL, allowAudio: options.withAudio, stats: stats)
        let resourceManager = ResourceManager(resourceProvider: provider)

        if options.appraisalTest {
            exit(await AppraisalScenario(options: options, resourceManager: resourceManager).run() ? 0 : 1)
        }

        if let role = options.vendingRole.flatMap(VendingScenario.Role.init(rawValue:)) {
            let scenario = VendingScenario(options: options, role: role, resourceManager: resourceManager)
            exit(await scenario.run() ? 0 : 1)
        }

        var tap: PacketTap?
        if !options.noTap {
            let created = PacketTap(stats: stats, loginUpstream: .init(host: options.host, port: options.port), splitEnter: !options.noEnterWorkaround)
            do {
                try created.start()
            } catch {
                Log.line("cannot start the packet tap: \(error)")
                exit(2)
            }
            tap = created
        }

        let runner = ProbeRunner(options: options, stats: stats, tap: tap, resourceManager: resourceManager)

        // SIGINT and SIGTERM stop the run and still write the summary. A second one exits at once.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let signalState = SignalState()
        var sources: [DispatchSourceSignal] = []
        for number in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                if signalState.increment() > 1 {
                    Log.line("second signal, exiting now")
                    stats.finish()
                    stats.printSummary(options: options)
                    stats.writeJSON(options: options)
                    exit(130)
                }
                Log.line("signal \(number) received, stopping")
                Task { @MainActor in
                    runner.requestStop()
                }
            }
            source.resume()
            sources.append(source)
        }

        Log.line("ro-probe starting: login \(options.host):\(options.port), user \(options.user), char \(options.charName), duration \(Int(options.duration)) s, tap \(options.noTap ? "off" : "on"), reconnect \(options.reconnect)")

        let succeeded = await runner.run()

        stats.finish()
        tap?.stop()
        stats.printSummary(options: options)
        stats.writeJSON(options: options)
        withExtendedLifetime(sources) {}
        exit(succeeded ? 0 : 1)
    }
}

final class SignalState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
