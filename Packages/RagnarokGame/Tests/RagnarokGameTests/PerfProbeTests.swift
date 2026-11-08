import Foundation
import Testing
@testable import RagnarokGame

struct PerfProbeTests {
    @Test func percentileUsesNearestRank() {
        let values = (1...100).map(Double.init)

        #expect(PerfProbe.percentile(values, 50) == 50)
        #expect(PerfProbe.percentile(values, 95) == 95)
        #expect(PerfProbe.percentile(values, 99) == 99)
        #expect(PerfProbe.percentile(values, 100) == 100)
    }

    @Test func percentileOfEmptyIsNil() {
        #expect(PerfProbe.percentile([], 95) == nil)
    }

    @Test func percentileIgnoresInputOrder() {
        #expect(PerfProbe.percentile([9, 1, 5, 3, 7], 50) == 5)
    }

    @Test func statisticsSummarizeSamples() {
        let statistics = PerfProbe.statistics([8, 8, 8, 8, 20])

        #expect(statistics["avg"] == 10.4)
        #expect(statistics["min"] == 8)
        #expect(statistics["p50"] == 8)
        #expect(statistics["max"] == 20)
    }

    @Test func statisticsOfEmptyIsEmpty() {
        #expect(PerfProbe.statistics([]).isEmpty)
    }

    @Test func probeIsOffWithoutEnvironment() {
        // The test runner does not set RO_PERF_LOG, so call sites must see nil and do nothing.
        #expect(PerfProbe.shared == nil)
        #expect(PerfProbe.preferredFramesPerSecondOverride == nil)
        PerfProbe.mark("ignored")
    }

    #if DEBUG
    @MainActor
    @Test func autoLoginDescriptionHidesPassword() {
        let settings = AutoLogin.Settings(
            user: "perf1",
            password: "hunter2-secret",
            server: nil,
            charServer: nil,
            character: nil,
            commands: [],
            loop: [],
            loopIntervalMs: 250,
            fullscreen: false
        )

        #expect(settings.description.contains("perf1"))
        #expect(!settings.description.contains("hunter2-secret"))
        #expect(!"\(settings)".contains("hunter2-secret"))
    }
    #endif
}
