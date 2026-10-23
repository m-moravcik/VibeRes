import Foundation
import Testing
@testable import VibeRes

/// A scratch log location per test, removed afterwards.
private func scratchLog() -> (url: URL, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VibeResLogTests-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("logs/VibeRes.log")
    return (url, { try? FileManager.default.removeItem(at: dir) })
}

private func permissions(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
}

@Suite("Debug log file")
struct LogFileTests {
    @Test("Lines carry timestamp, level, category and message; file is 0600 in a 0700 folder")
    func formatAndPermissions() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let file = LogFile(url: url)
        file.append(level: .info, category: "display", message: "two displays")
        file.flush()

        let lines = file.lastLines(10)
        #expect(lines.count == 1)
        #expect(lines[0].hasSuffix(" INFO display two displays"))
        #expect(lines[0].first?.isNumber == true)
        #expect(permissions(url) == 0o600)
        #expect(permissions(url.deletingLastPathComponent()) == 0o700)
    }

    @Test("A newline in a message cannot forge a second record")
    func newlineFlattened() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let file = LogFile(url: url)
        file.append(level: .error, category: "apply", message: "one\nFAKE line")
        #expect(file.lastLines(10).count == 1)
    }

    @Test("Rolls to .1 past the cap and keeps both files readable in order")
    func rotation() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let file = LogFile(url: url, maxBytes: 400)
        for i in 0..<30 { file.append(level: .info, category: "t", message: "line \(i)") }
        file.flush()

        let rolled = url.appendingPathExtension("1")
        #expect(FileManager.default.fileExists(atPath: rolled.path))
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size <= 400)
        #expect(permissions(rolled) == 0o600)

        // The tail reaches across the roll, newest last, nothing duplicated.
        let tail = file.lastLines(30)
        #expect(tail.last?.hasSuffix("line 29") == true)
        let numbers = tail.compactMap { $0.split(separator: " ").last.flatMap { Int($0) } }
        #expect(numbers == Array(numbers.sorted()))
        #expect(Set(numbers).count == numbers.count)
    }

    @Test("lastLines asks for fewer than exist, and an absent log is empty")
    func lastLinesBounds() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let file = LogFile(url: url)
        #expect(file.lastLines(5).isEmpty)
        for i in 0..<8 { file.append(level: .info, category: "t", message: "n\(i)") }
        let tail = file.lastLines(3)
        #expect(tail.count == 3)
        #expect(tail[0].hasSuffix("n5") && tail[2].hasSuffix("n7"))
    }

    @Test("ensureExists creates an empty private file")
    func ensureExists() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let file = LogFile(url: url)
        file.ensureExists()
        #expect(permissions(url) == 0o600)
        #expect(file.lastLines(5).isEmpty)
    }
}

@Suite("Debug log sink")
struct LogSinkTests {
    private func lines(at verbosity: LogLevel, enabled: Bool = true) -> [String] {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let sink = LogSink(file: LogFile(url: url))
        sink.configure(enabled: enabled, verbosity: verbosity)
        sink.write(.error, category: "t", "e")
        sink.write(.info, category: "t", "i")
        sink.write(.debug, category: "t", "d")
        sink.flush()
        return sink.lastLines(10).map { String($0.split(separator: " ").last ?? "") }
    }

    @Test("Verbosity admits its own level and the quieter ones")
    func filtering() {
        #expect(lines(at: .error) == ["e"])
        #expect(lines(at: .info) == ["e", "i"])
        #expect(lines(at: .debug) == ["e", "i", "d"])
    }

    @Test("Off writes nothing, not even a file")
    func off() {
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let sink = LogSink(file: LogFile(url: url))
        sink.write(.error, category: "t", "e")
        sink.flush()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        sink.configure(enabled: false, verbosity: .debug)
        sink.write(.error, category: "t", "e")
        sink.flush()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Debug log preferences")
@MainActor
struct DebugLogPreferencesTests {
    private func reset() {
        UserDefaults.standard.removeObject(forKey: Preferences.debugLogEnabledKey)
        UserDefaults.standard.removeObject(forKey: Preferences.debugLogLevelKey)
        LogSink.shared.configure(enabled: false, verbosity: .info)
    }

    @Test("Off by default, standard level")
    func defaults() {
        reset()
        defer { reset() }
        let prefs = Preferences()
        #expect(prefs.debugLogEnabled == false)
        #expect(prefs.debugLogLevel == .info)
    }

    @Test("Opt-in and level persist across instances")
    func persists() {
        reset()
        defer { reset() }
        let p1 = Preferences()
        p1.debugLogEnabled = true
        p1.debugLogLevel = .debug
        let p2 = Preferences()
        #expect(p2.debugLogEnabled == true)
        #expect(p2.debugLogLevel == .debug)
    }

    @Test("An unknown stored level falls back to standard")
    func unknownLevel() {
        reset()
        defer { reset() }
        UserDefaults.standard.set(99, forKey: Preferences.debugLogLevelKey)
        #expect(Preferences().debugLogLevel == .info)
    }
}

@Suite("Diagnostics report")
struct DiagnosticsTests {
    private func report(logLines: [String], logEnabled: Bool = true) -> Diagnostics.Report {
        Diagnostics.Report(
            appVersion: "1.2.3", build: "45", osVersion: "Version 26.0 (Build 25A1)",
            hardwareModel: "Mac15,6", architecture: "Apple Silicon (arm64)",
            settings: [("Simple mode", "on"), ("Debug log", "off")],
            displays: [
                .init(name: "Built-in Retina Display", isBuiltIn: true, isMain: true,
                      width: 1512, height: 982, refreshHz: 120, isHiDPI: true),
                .init(name: "LG UltraFine", isBuiltIn: false, isMain: false,
                      width: 2560, height: 1440, refreshHz: nil, isHiDPI: false),
            ],
            profileCount: 3, logLines: logLines, logEnabled: logEnabled)
    }

    @Test("Covers version, OS, hardware, settings, displays and profiles")
    func content() {
        let text = report(logLines: ["2026-01-01T00:00:00Z INFO display x"]).render()
        #expect(text.contains("App: 1.2.3 (45)"))
        #expect(text.contains("macOS: Version 26.0 (Build 25A1)"))
        #expect(text.contains("Hardware: Mac15,6, Apple Silicon (arm64)"))
        #expect(text.contains("- Simple mode: on"))
        #expect(text.contains("- Built-in Retina Display (built-in, main): 1512 x 982 @ 120 Hz, HiDPI"))
        #expect(text.contains("- LG UltraFine (external): 2560 x 1440"))
        #expect(text.contains("Profiles: 3"))
        #expect(text.contains("INFO display x"))
    }

    @Test("Home and volume paths are scrubbed, wherever they appear")
    func redaction() {
        let text = report(logLines: [
            "ERROR profiles open /Users/jane.doe/Library/x failed",
            "INFO capture /Volumes/Secret Drive/shot.png",
        ]).render()
        #expect(!text.contains("jane.doe"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("Secret"))
        #expect(text.contains("~/Library/x"))
    }

    @Test("Scrub leaves ordinary text alone")
    func scrubIdempotent() {
        let line = "apply LG UltraFine: 2560x1440 @ 60Hz"
        #expect(Diagnostics.scrub(line) == line)
        #expect(Diagnostics.scrub(Diagnostics.scrub("/Users/a/b")) == "~/b")
    }

    @Test("An empty log says why: off, or nothing yet")
    func emptyLog() {
        #expect(report(logLines: [], logEnabled: false).render().contains("debug log is off"))
        #expect(report(logLines: [], logEnabled: true).render().contains("(none yet)"))
    }

    @Test("The real hardware model is a non-empty identifier, not a serial")
    func hardwareModel() {
        let model = Diagnostics.hardwareModel()
        #expect(!model.isEmpty && model != "unknown")
    }
}
