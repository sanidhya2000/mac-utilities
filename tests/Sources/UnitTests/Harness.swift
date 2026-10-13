import Foundation

/// Minimal test harness: enough to express grouped assertions and exit
/// non-zero on failure, without depending on Xcode.
final class Harness {
    private var currentSuite = ""
    private var passed = 0
    private var failures: [String] = []
    private var suitesRun: Set<String> = []

    func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        suitesRun.insert(name)
        print("\n\(name)")
        do {
            try body()
        } catch {
            fail("threw: \(error)")
        }
    }

    func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passed += 1
            print("  ✓ \(label)")
        } else {
            let extra = detail()
            fail(label + (extra.isEmpty ? "" : " — \(extra)"))
        }
    }

    func equal<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
        check(label, actual == expected, "got \(actual), expected \(expected)")
    }

    func close(_ label: String, _ actual: Double, _ expected: Double, _ tolerance: Double) {
        check(label, abs(actual - expected) <= tolerance,
              "got \(actual), expected \(expected) ± \(tolerance)")
    }

    func lessThan(_ label: String, _ actual: Double, _ limit: Double) {
        check(label, actual < limit, "got \(actual), expected < \(limit)")
    }

    private func fail(_ message: String) {
        let entry = "\(currentSuite): \(message)"
        failures.append(entry)
        print("  ✗ \(message)")
    }

    /// Prints a summary and exits with a status the shell can act on.
    func finish() -> Never {
        print("\n" + String(repeating: "─", count: 60))
        print("\(suitesRun.count) suites · \(passed) passed · \(failures.count) failed")
        if !failures.isEmpty {
            print("\nFAILURES:")
            for failure in failures { print("  • \(failure)") }
            exit(1)
        }
        print("\nall green")
        exit(0)
    }
}
