import Foundation

/// Per-process network byte counters, read by shelling out to `nettop`.
///
/// macOS exposes no public per-process network API, so `nettop -P -L 1` is the
/// supported route. It is run on a background queue with a hard timeout and its
/// failure is never fatal — WakeHold falls back to CPU and disk alone.
public final class NetworkSampler {

    public init() {}

    private let queue = DispatchQueue(label: "com.wakehold.nettop", qos: .utility)
    private var latest: [pid_t: UInt64] = [:]
    private let lock = NSLock()
    private var inFlight = false

    /// Cumulative bytes in+out per pid, as of the last completed `nettop` run.
    public func currentTotals() -> [pid_t: UInt64] {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Kicks off a refresh if one is not already running. Non-blocking.
    public func refresh() {
        lock.lock()
        if inFlight { lock.unlock(); return }
        inFlight = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let parsed = self.runNettop()
            self.lock.lock()
            if let parsed { self.latest = parsed }
            self.inFlight = false
            self.lock.unlock()
        }
    }

    private func runNettop() -> [pid_t: UInt64]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch {
            Log.error("nettop failed to launch: \(error.localizedDescription)")
            return nil
        }

        // Read before waiting so a large burst cannot fill the pipe and deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(8)
        while task.isRunning && Date() < deadline { usleep(50_000) }
        if task.isRunning { task.terminate() }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Lines look like `mDNSResponder.271,111694963,25406954,` — the pid is the
    /// trailing dot-component of the name, which may itself contain dots.
    private func parse(_ text: String) -> [pid_t: UInt64] {
        var totals: [pid_t: UInt64] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }

            let identity = fields[0]
            guard let dot = identity.lastIndex(of: "."),
                  let pid = pid_t(identity[identity.index(after: dot)...]),
                  let bytesIn = UInt64(fields[1].trimmingCharacters(in: .whitespaces)),
                  let bytesOut = UInt64(fields[2].trimmingCharacters(in: .whitespaces))
            else { continue }

            totals[pid, default: 0] += bytesIn &+ bytesOut
        }
        return totals
    }
}
