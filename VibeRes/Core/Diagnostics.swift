import CoreGraphics
import Foundation

/// The plain-text report behind Settings → Debug → Copy diagnostics. Untranslated
/// on purpose: it is read by the maintainer, not shown in the app. Redacted by
/// construction (no serial numbers are ever read, displays are summarised by name
/// and mode) and scrubbed again at the end for home and volume paths.
enum Diagnostics {
    static let logLineCount = 50

    struct DisplaySummary: Equatable {
        let name: String
        let isBuiltIn: Bool
        let isMain: Bool
        let width: Int
        let height: Int
        let refreshHz: Int?
        let isHiDPI: Bool
    }

    struct Report {
        var appVersion: String
        var build: String
        var osVersion: String
        var hardwareModel: String
        var architecture: String
        var settings: [(name: String, value: String)]
        var displays: [DisplaySummary]
        var profileCount: Int
        var logLines: [String]
        /// Whether the debug log file is on, to tell "no lines because it is off"
        /// from "no lines because nothing happened".
        var logEnabled: Bool
    }

    /// Display names are model names ("LG UltraFine"), not personal; a name that
    /// embeds a path-like user string is caught by `scrub`.
    static func summarise(_ info: DisplayInfo) -> DisplaySummary {
        DisplaySummary(
            name: info.name,
            isBuiltIn: CGDisplayIsBuiltin(info.id) != 0,
            isMain: info.isMain,
            width: info.currentMode?.width ?? 0,
            height: info.currentMode?.height ?? 0,
            refreshHz: info.currentMode?.refreshHz,
            isHiDPI: info.currentMode?.isHiDPI ?? false
        )
    }

    /// Reads the live state. Main actor because the preferences and stores are.
    @MainActor
    static func collect(
        preferences: Preferences, displays: [DisplayInfo], profileCount: Int, log: LogSink = .shared
    ) -> Report {
        func onOff(_ value: Bool) -> String { value ? "on" : "off" }
        let info = Bundle.main.infoDictionary
        return Report(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModel(),
            architecture: architecture,
            settings: [
                ("Simple mode", onOff(preferences.simpleMode)),
                ("Confirm resolution changes", onOff(preferences.confirmDisplayChanges)),
                ("Auto-apply matching profile", onOff(preferences.autoApplyOnDisplayChange)),
                ("Live preview on hover", onOff(preferences.livePreviewEnabled)),
                ("Launch at login", onOff(preferences.launchAtLoginIntent ?? false)),
                ("Debug log", preferences.debugLogEnabled ? preferences.debugLogLevel.label.lowercased() : "off"),
            ],
            displays: displays.map(summarise),
            profileCount: profileCount,
            logLines: log.lastLines(logLineCount),
            logEnabled: preferences.debugLogEnabled
        )
    }

    /// `hw.model` ("MacBookPro18,3", "Mac15,6"): the model identifier, not the serial.
    static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static var architecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #else
        "Intel (x86_64)"
        #endif
    }

    /// Replaces `/Users/<name>` and `/Volumes/<name>`: the log should not carry
    /// them, this is the second line of defence for account and volume names.
    static func scrub(_ text: String) -> String {
        text.replacing(/\/Users\/[^\/\s]+/, with: "~")
            .replacing(/\/Volumes\/[^\/\n]+/, with: "/Volumes/-")
    }
}

extension Diagnostics.Report {
    func render() -> String {
        var out = ["VibeRes diagnostics", ""]
        out.append("App: \(appVersion) (\(build))")
        out.append("macOS: \(osVersion)")
        out.append("Hardware: \(hardwareModel), \(architecture)")
        out.append("")
        out.append("Settings")
        for setting in settings { out.append("- \(setting.name): \(setting.value)") }
        out.append("")
        out.append("Displays (\(displays.count))")
        for d in displays {
            let kind = d.isBuiltIn ? "built-in" : "external"
            let hz = d.refreshHz.map { " @ \($0) Hz" } ?? ""
            let hidpi = d.isHiDPI ? ", HiDPI" : ""
            let main = d.isMain ? ", main" : ""
            out.append("- \(d.name) (\(kind)\(main)): \(d.width) x \(d.height)\(hz)\(hidpi)")
        }
        out.append("")
        out.append("Profiles: \(profileCount)")
        out.append("")
        out.append("Last \(Diagnostics.logLineCount) log lines")
        if logLines.isEmpty {
            out.append(logEnabled
                ? "(none yet)"
                : "(debug log is off; turn on Settings > Debug > Write debug log to file, reproduce the problem and copy again)")
        } else {
            out.append(contentsOf: logLines)
        }
        return Diagnostics.scrub(out.joined(separator: "\n")) + "\n"
    }
}
