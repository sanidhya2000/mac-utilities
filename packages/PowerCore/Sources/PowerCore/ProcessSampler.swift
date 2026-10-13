import Foundation
import Darwin
import AppKit

/// Converts mach absolute time units to nanoseconds.
///
/// `proc_pid_rusage` reports CPU time in mach units, not nanoseconds. On Intel
/// the timebase is 1/1 so the two coincide, which is why this is easy to miss;
/// on Apple silicon it is 125/3, and skipping the conversion under-reports CPU
/// by ~42x — enough to make a fully pinned core look idle.
private let machTimebase: (numer: UInt64, denom: UInt64) = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return (UInt64(info.numer), UInt64(info.denom))
}()

@inline(__always)
private func machToNanos(_ ticks: UInt64) -> UInt64 {
    ticks / machTimebase.denom * machTimebase.numer
        + ticks % machTimebase.denom * machTimebase.numer / machTimebase.denom
}

/// One process as seen at a point in time. Counters are cumulative since the
/// process started; rates come from differencing two samples.
public struct RawSample {
    public let pid: pid_t
    public let executable: String
    public let bundleID: String?
    public let displayName: String
    public let cpuNanos: UInt64
    public let diskBytes: UInt64
}

/// Per-process CPU and disk figures, read straight from libproc — the same
/// counters Activity Monitor displays. No private API, no entitlement needed.
public final class ProcessSampler {

    public init() {}

    /// `PROC_PIDPATHINFO_MAXSIZE` (4 * MAXPATHLEN). The macro is not
    /// re-exported to Swift, so the value is restated here.
    private static let maxPathSize = 4 * 1024

    /// Bundle identifiers and display names for GUI apps, refreshed per sweep.
    private var guiApps: [pid_t: NSRunningApplication] = [:]

    public func sample() -> [RawSample] {
        refreshGUIApps()

        var samples: [RawSample] = []
        for pid in livePIDs() {
            guard let usage = resourceUsage(for: pid) else { continue }

            let app = guiApps[pid]
            let executable = executableName(for: pid, fallback: app?.localizedName ?? "")
            guard !executable.isEmpty else { continue }

            samples.append(RawSample(
                pid: pid,
                executable: executable,
                bundleID: app?.bundleIdentifier,
                displayName: app?.localizedName ?? executable,
                cpuNanos: machToNanos(usage.ri_user_time &+ usage.ri_system_time),
                diskBytes: usage.ri_diskio_bytesread &+ usage.ri_diskio_byteswritten
            ))
        }
        return samples
    }

    private func refreshGUIApps() {
        guiApps.removeAll(keepingCapacity: true)
        for app in NSWorkspace.shared.runningApplications {
            guiApps[app.processIdentifier] = app
        }
    }

    private func livePIDs() -> [pid_t] {
        let capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard capacity > 0 else { return [] }

        let count = Int(capacity) / MemoryLayout<pid_t>.size
        var buffer = [pid_t](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, capacity)
        guard written > 0 else { return [] }

        let valid = Int(written) / MemoryLayout<pid_t>.size
        return buffer.prefix(valid).filter { $0 > 0 }
    }

    /// `proc_pid_rusage` reports another process's counters only when the caller
    /// owns it or runs as root; processes we cannot read are simply skipped.
    private func resourceUsage(for pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        return rc == 0 ? info : nil
    }

    /// Prefers the enclosing `.app` name so "Final Cut Pro" never surfaces as
    /// its inner helper executable.
    private func executableName(for pid: pid_t, fallback: String) -> String {
        var pathBuffer = [CChar](repeating: 0, count: Self.maxPathSize)
        let length = proc_pidpath(pid, &pathBuffer, UInt32(Self.maxPathSize))
        guard length > 0 else { return fallback }

        let path = String(cString: pathBuffer)
        if let range = path.range(of: ".app/", options: String.CompareOptions.backwards) {
            let bundlePath = String(path[path.startIndex..<range.lowerBound])
            if let name = bundlePath.split(separator: "/").last { return String(name) }
        }
        return (path as NSString).lastPathComponent
    }
}
