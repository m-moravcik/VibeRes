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
    }

    /// Writes one line per level through `sink` and returns the levels that landed.
    private func written(_ sink: LogSink) -> [String] {
        sink.write(.error, category: "t", "e")
        sink.write(.info, category: "t", "i")
        sink.write(.debug, category: "t", "d")
        sink.flush()
        return sink.lastLines(10).map { String($0.split(separator: " ").last ?? "") }
    }

    @Test("Off by default, standard level, and the sink stays off")
    func defaults() {
        reset()
        defer { reset() }
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let sink = LogSink(file: LogFile(url: url))
        let prefs = Preferences(logSink: sink)
        #expect(prefs.debugLogEnabled == false)
        #expect(prefs.debugLogLevel == .info)
        #expect(written(sink).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("The toggle and the level drive the sink it was given")
    func drivesSink() {
        reset()
        defer { reset() }
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        let sink = LogSink(file: LogFile(url: url))
        let prefs = Preferences(logSink: sink)
        prefs.debugLogEnabled = true
        #expect(written(sink) == ["e", "i"])
        prefs.debugLogLevel = .debug
        #expect(written(sink) == ["e", "i", "e", "i", "d"])
        prefs.debugLogEnabled = false
        #expect(written(sink).count == 5)
    }

    @Test("A stored opt-in reaches the sink at launch")
    func storedOptIn() {
        reset()
        defer { reset() }
        let (url, cleanup) = scratchLog()
        defer { cleanup() }
        UserDefaults.standard.set(true, forKey: Preferences.debugLogEnabledKey)
        UserDefaults.standard.set(LogLevel.error.rawValue, forKey: Preferences.debugLogLevelKey)
        let sink = LogSink(file: LogFile(url: url))
        _ = Preferences(logSink: sink)
        #expect(written(sink) == ["e"])
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

    @Test("The app hosting the tests never hands out the real log file")
    func hostedAppHasNoSink() {
        #expect(VibeResApp.debugLogSink == nil)
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
                .init(label: "Built-in display (APP A0A1)", isMain: true,
                      width: 1512, height: 982, refreshHz: 120, isHiDPI: true),
                .init(label: "External display 2 (GSM 5B71)", isMain: false,
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
        #expect(text.contains("- Built-in display (APP A0A1), main: 1512 x 982 @ 120 Hz, HiDPI"))
        #expect(text.contains("- External display 2 (GSM 5B71): 2560 x 1440"))
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
        #expect(!text.contains("Drive"))
        #expect(text.contains("~/Library/x"))
        #expect(text.contains("INFO capture /Volumes/-/shot.png"))
    }

    @Test("A display's own name never reaches the report")
    func noDisplayName() {
        let info = DisplayInfo(id: 0xFFFF_FF01, name: "Jane's iPad", isMain: true,
                               modes: [], currentMode: nil, groups: [])
        var r = report(logLines: [])
        r.displays = [Diagnostics.summarise(info)]
        let text = r.render()
        #expect(!text.contains("Jane"))
        #expect(!text.contains("iPad"))
        #expect(text.contains("- \(DisplayLabel.label(for: info.id)), main: 0 x 0"))
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

    @Test("Old lines from a log that is now off are labelled with the newest timestamp")
    func offWithOldLines() {
        let lines = [
            "2026-01-01T09:00:00Z INFO display x",
            "2026-01-02T10:30:00Z ERROR apply y",
        ]
        let text = report(logLines: lines, logEnabled: false).render()
        let label = "Debug log is off now. Lines below are from when it was on (last: 2026-01-02T10:30:00Z)."
        #expect(text.contains(label + "\n" + lines[0] + "\n" + lines[1]))
        #expect(!text.contains("(debug log is off;"))
        #expect(!report(logLines: lines, logEnabled: true).render().contains("Debug log is off now"))
    }

    @Test("The real hardware model is a non-empty identifier, not a serial")
    func hardwareModel() {
        let model = Diagnostics.hardwareModel()
        #expect(!model.isEmpty && model != "unknown")
    }
}

@Suite("Display label")
struct DisplayLabelTests {
    @Test("EDID manufacturer IDs decode to their 3-letter PNP code")
    func pnp() {
        #expect(DisplayLabel.pnpID(0x1E6D) == "GSM")
        #expect(DisplayLabel.pnpID(0x0610) == "APP")
        #expect(DisplayLabel.pnpID(0x4C2D) == "SAM")
    }

    @Test("Values that are not a manufacturer ID decode to nil")
    func invalidPNP() {
        #expect(DisplayLabel.pnpID(0) == nil)
        #expect(DisplayLabel.pnpID(0x8610) == nil)
        #expect(DisplayLabel.pnpID(0x756E_6B6E) == nil)
        #expect(DisplayLabel.pnpID(0xFFFF_FFFF) == nil)
        #expect(DisplayLabel.pnpID(0x0400) == nil)
        #expect(DisplayLabel.pnpID(0x1B << 10 | 1 << 5 | 1) == nil)
    }

    @Test("Built-in and external labels carry the EDID codes, or stand alone without them")
    func labels() {
        #expect(DisplayLabel.label(id: 1, isBuiltIn: true, vendor: 0x0610, model: 0xA0A1)
                == "Built-in display (APP A0A1)")
        #expect(DisplayLabel.label(id: 2, isBuiltIn: false, vendor: 0x1E6D, model: 0x5B71)
                == "External display 2 (GSM 5B71)")
        #expect(DisplayLabel.label(id: 3, isBuiltIn: false, vendor: 0x1E6D, model: 0x12)
                == "External display 3 (GSM 0012)")
        #expect(DisplayLabel.label(id: 4, isBuiltIn: false, vendor: 0x756E_6B6E, model: 0x717)
                == "External display 4")
    }
}
