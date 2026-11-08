//
//  PerfProbe.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Metal
import MetalKit
import QuartzCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Frame statistics and start-up timestamps for the performance tasks (P5-04..P5-06).
///
/// The probe exists only when `RO_PERF_LOG=<path>` is set in the environment. Without it `shared` is `nil`
/// and every call site is a single optional check, so it costs nothing in a normal run.
///
/// Environment:
/// - `RO_PERF_LOG`      path of the JSON summary (a sandboxed app can only write inside its container).
/// - `RO_PERF_SECONDS`  length of the measured window in seconds (default 30).
/// - `RO_PERF_WARMUP`   seconds dropped after the first map frame, or after `RO_PERF_AFTER` (default 5).
/// - `RO_PERF_AFTER`    name of a milestone; frames before it are not measured (for example `commandsDone`).
/// - `RO_PERF_LABEL`    free text copied into the summary (map, run number).
/// - `RO_PERF_EXIT`     `1` quits the app (clean-exit marker, then `exit(0)`) once the summary is written.
/// - `RO_PERF_FPS`      overrides `MTKView.preferredFramesPerSecond` (default: the MTKView default of 60).
///
/// Milestones are wall-clock instants reported as seconds since the process started.
public final class PerfProbe: @unchecked Sendable {
    public static let shared: PerfProbe? = {
        guard let path = ProcessInfo.processInfo.environment["RO_PERF_LOG"], !path.isEmpty else {
            return nil
        }
        return PerfProbe(path: path, environment: ProcessInfo.processInfo.environment)
    }()

    /// Records a named instant (first call per name wins). A no-op when `RO_PERF_LOG` is unset.
    public static func mark(_ name: String) {
        shared?.recordMilestone(name)
    }

    /// `RO_PERF_FPS` when set, otherwise `nil` (leave the view's default).
    static var preferredFramesPerSecondOverride: Int? {
        guard shared != nil,
              let value = ProcessInfo.processInfo.environment["RO_PERF_FPS"],
              let fps = Int(value), fps > 0 else {
            return nil
        }
        return fps
    }

    private let path: String
    private let label: String
    private let measureSeconds: Double
    private let warmupSeconds: Double
    private let afterMilestone: String?
    private let exitWhenDone: Bool
    private let processStart: Date

    private let lock = NSLock()
    private var milestones: [(name: String, date: Date)] = []
    private var milestoneNames: Set<String> = []

    private enum Phase {
        case waiting
        case warmup(until: CFTimeInterval)
        case measuring(start: CFTimeInterval, until: CFTimeInterval)
        case finished
    }
    private var phase: Phase = .waiting

    private var lastFrameBegin: CFTimeInterval?
    private var currentFrameBegin: CFTimeInterval = 0
    private var intervalsMs: [Double] = []
    private var cpuMs: [Double] = []
    private var gpuMs: [Double] = []
    private var gpuUnavailable = 0

    private var drawableSize: CGSize = .zero
    private var screenHz = 0
    private var preferredFPS = 0
    private var frameCounter = 0
    private var memoryAtFirstFrame: [String: Any] = [:]

    private init(path: String, environment: [String: String]) {
        self.path = path
        label = environment["RO_PERF_LABEL"] ?? ""
        measureSeconds = environment["RO_PERF_SECONDS"].flatMap(Double.init) ?? 30
        warmupSeconds = environment["RO_PERF_WARMUP"].flatMap(Double.init) ?? 5
        afterMilestone = environment["RO_PERF_AFTER"].flatMap { $0.isEmpty ? nil : $0 }
        exitWhenDone = environment["RO_PERF_EXIT"] == "1"
        processStart = Self.processStartDate() ?? Date()
        intervalsMs.reserveCapacity(Int((measureSeconds + 1) * 240))
        cpuMs.reserveCapacity(Int((measureSeconds + 1) * 240))
        gpuMs.reserveCapacity(Int((measureSeconds + 1) * 240))
    }

    // MARK: - Milestones

    func recordMilestone(_ name: String) {
        let date = Date()
        lock.lock()
        defer { lock.unlock() }
        guard milestoneNames.insert(name).inserted else {
            return
        }
        milestones.append((name, date))
    }

    // MARK: - Frames

    /// Call at the top of a presented frame, after the drawable was acquired.
    func beginFrame(_ view: MTKView) {
        let now = CACurrentMediaTime()

        lock.lock()
        defer { lock.unlock() }

        currentFrameBegin = now
        frameCounter += 1
        if frameCounter == 1 || frameCounter % 120 == 0 {
            refreshViewInfo(view)
        }

        if milestoneNames.insert("mapFirstFrame").inserted {
            milestones.append(("mapFirstFrame", Date()))
            memoryAtFirstFrame = Self.memoryInfo()
        }

        switch phase {
        case .waiting:
            if let afterMilestone, !milestoneNames.contains(afterMilestone) {
                lastFrameBegin = now
                return
            }
            phase = .warmup(until: now + warmupSeconds)
        case .warmup(let until):
            if now >= until {
                phase = .measuring(start: now, until: now + measureSeconds)
            }
        case .measuring(_, let until):
            if now >= until {
                phase = .finished
                finishLocked(endedAt: now)
            } else if let lastFrameBegin {
                intervalsMs.append((now - lastFrameBegin) * 1000)
            }
        case .finished:
            break
        }
        lastFrameBegin = now
    }

    /// Call after the frame was encoded and presented, before `commandBuffer.commit()`.
    func endFrame(_ commandBuffer: any MTLCommandBuffer) {
        let now = CACurrentMediaTime()

        lock.lock()
        let isMeasuring: Bool
        if case .measuring = phase {
            isMeasuring = true
            cpuMs.append((now - currentFrameBegin) * 1000)
        } else {
            isMeasuring = false
        }
        lock.unlock()

        guard isMeasuring else {
            return
        }
        commandBuffer.addCompletedHandler { [self] buffer in
            let duration = buffer.gpuEndTime - buffer.gpuStartTime
            lock.lock()
            defer { lock.unlock() }
            if duration > 0 {
                gpuMs.append(duration * 1000)
            } else {
                gpuUnavailable += 1
            }
        }
    }

    private func refreshViewInfo(_ view: MTKView) {
        drawableSize = view.drawableSize
        preferredFPS = view.preferredFramesPerSecond
        #if canImport(AppKit)
        screenHz = view.window?.screen?.maximumFramesPerSecond ?? 0
        #elseif canImport(UIKit)
        screenHz = view.window?.screen.maximumFramesPerSecond ?? 0
        #endif
    }

    // MARK: - Summary

    private func finishLocked(endedAt: CFTimeInterval) {
        // GPU completion handlers of the last frames may still be in flight; they only add samples.
        var summary: [String: Any] = [
            "schema": 1,
            "label": label,
            "endedAt": ISO8601DateFormatter().string(from: Date()),
            "build": Self.buildConfiguration,
            "machine": Self.machineInfo(),
            "windowSeconds": measureSeconds,
            "warmupSeconds": warmupSeconds,
            "drawable": ["width": Int(drawableSize.width), "height": Int(drawableSize.height)],
            "displayMaxHz": screenHz,
            "preferredFramesPerSecond": preferredFPS,
        ]
        if let afterMilestone {
            summary["measuredAfterMilestone"] = afterMilestone
        }

        let frameStats = Self.statistics(intervalsMs)
        summary["samples"] = intervalsMs.count
        summary["frameMs"] = frameStats
        summary["fps"] = [
            "average": intervalsMs.isEmpty ? 0 : Self.rnd(1000 / (intervalsMs.reduce(0, +) / Double(intervalsMs.count))),
            "atP95FrameTime": Self.percentile(intervalsMs, 95).map { Self.rnd(1000 / $0) } ?? 0,
            "atP99FrameTime": Self.percentile(intervalsMs, 99).map { Self.rnd(1000 / $0) } ?? 0,
        ]
        let over: (Double) -> Double = { limit in
            self.intervalsMs.isEmpty ? 0 : Self.rnd(Double(self.intervalsMs.filter { $0 > limit }.count) / Double(self.intervalsMs.count) * 100)
        }
        summary["framesOverPercent"] = ["8.3ms": over(8.34), "16.7ms": over(16.7), "33.3ms": over(33.4)]
        summary["cpuDrawMs"] = Self.statistics(cpuMs)
        summary["gpuMs"] = Self.statistics(gpuMs)
        summary["gpuSamples"] = gpuMs.count
        summary["gpuUnavailable"] = gpuUnavailable

        var memory = Self.memoryInfo()
        memory["atFirstMapFrame"] = memoryAtFirstFrame
        summary["memory"] = memory

        var milestoneTimes: [String: Double] = [:]
        for milestone in milestones {
            milestoneTimes[milestone.name] = Self.rnd(milestone.date.timeIntervalSince(processStart), digits: 3)
        }
        summary["processStartedAt"] = ISO8601DateFormatter().string(from: processStart)
        summary["milestonesSinceProcessStart"] = milestoneTimes

        let url = URL(fileURLWithPath: path)
        do {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("PerfProbe could not write \(self.path): \(error)")
        }

        if exitWhenDone {
            // NSApp.terminate hangs in an unattended run (the app delegate waits for its server manager),
            // so end the session marker, which marks a clean exit, and leave directly.
            DispatchQueue.main.async {
                try? SessionMarker(directory: SessionMarker.defaultDirectory()).end()
                exit(0)
            }
        }
    }

    // MARK: - Helpers

    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    static func statistics(_ values: [Double]) -> [String: Double] {
        guard !values.isEmpty else {
            return [:]
        }
        let sorted = values.sorted()
        func at(_ p: Double) -> Double {
            let rank = Int((p / 100 * Double(sorted.count)).rounded(.up)) - 1
            return sorted[min(max(rank, 0), sorted.count - 1)]
        }
        return [
            "avg": rnd(values.reduce(0, +) / Double(values.count)),
            "min": rnd(sorted[0]),
            "p50": rnd(at(50)),
            "p95": rnd(at(95)),
            "p99": rnd(at(99)),
            "max": rnd(sorted[sorted.count - 1]),
        ]
    }

    private static func rnd(_ value: Double, digits: Int = 2) -> Double {
        let scale = pow(10.0, Double(digits))
        return (value * scale).rounded() / scale
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    private static func machineInfo() -> [String: Any] {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return [
            "cpu": String(cString: brand),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryMB": Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
        ]
    }

    /// Resident size and physical footprint of this process, in megabytes.
    private static func memoryInfo() -> [String: Any] {
        #if os(macOS)
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0 else {
            return [:]
        }
        let megabyte = 1_048_576.0
        return [
            "residentMB": rnd(Double(info.ri_resident_size) / megabyte, digits: 1),
            "physFootprintMB": rnd(Double(info.ri_phys_footprint) / megabyte, digits: 1),
            "peakPhysFootprintMB": rnd(Double(info.ri_lifetime_max_phys_footprint) / megabyte, digits: 1),
        ]
        #else
        // libproc is not in the iOS SDK. The performance runs are macOS only.
        return [:]
        #endif
    }

    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
