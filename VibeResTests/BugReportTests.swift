import Foundation
import Testing
@testable import VibeRes

/// Settings -> Debug -> Report a problem: a link to GitHub's bug report form
/// with the diagnostics in their field. GitHub fills an issue form field from
/// the query item named after the field's id, next to `template=<file>`
/// (GitHub docs, "Creating an issue from a URL query"), and refuses links much
/// over 8 KB. The oracle for the content is the report's own rendering,
/// recovered by decoding the link as a browser would.
@Suite("Bug report link")
struct BugReportTests {
    private func report(logLines: [String]) -> Diagnostics.Report {
        Diagnostics.Report(
            appVersion: "1.2.3", build: "45", osVersion: "Version 26.0 (Build 25A1)",
            hardwareModel: "Mac15,6", architecture: "Apple Silicon (arm64)",
            settings: [("Simple mode", "on")],
            displays: [.init(label: "Built-in display (APP A0A1)", isMain: true,
                             width: 1512, height: 982, refreshHz: 120, isHiDPI: true)],
            profileCount: 3, logLines: logLines, logEnabled: true)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("A short report goes into the form's diagnostics field whole")
    func shortReportWhole() {
        // "+" and "&" would be read as a space and a new field if left raw.
        let r = report(logLines: ["2026-01-01T00:00:00Z INFO apply 2560x1440 + VRR & HDR"])
        let link = BugReport.link(for: r)

        #expect(link.carriesDiagnostics)
        #expect(link.url.host == "github.com")
        #expect(link.url.path == "/m-moravcik/VibeRes/issues/new")
        let fields = query(link.url)
        #expect(fields["template"] == "bug_report.yml")
        #expect(fields["diagnostics"] == r.render())
        #expect(link.url.query?.contains("+") == false)
        #expect(!r.render().contains("did not fit"))
    }

    @Test("A long log keeps its newest lines and says how many older ones were left out")
    func longLogTrimsOldest() throws {
        let lines = (0..<50).map { "2026-01-01T00:00:\(String(format: "%02d", $0))Z INFO line \($0) " + String(repeating: "x", count: 200) }
        let link = BugReport.link(for: report(logLines: lines))

        #expect(link.carriesDiagnostics)
        #expect(link.url.absoluteString.count <= BugReport.maxLinkLength)
        let text = try #require(query(link.url)["diagnostics"])
        #expect(text.contains("INFO line 49 "))
        #expect(!text.contains("INFO line 0 "))
        let keptLines = lines.filter { text.contains($0) }
        let kept = keptLines.count
        #expect(kept > 0 && kept < 50)
        #expect(keptLines == Array(lines.suffix(kept)))
        #expect(text.contains("Last \(kept) log lines (\(50 - kept) older ones did not fit the link"))

        var oneMore = report(logLines: Array(lines.suffix(kept + 1)))
        oneMore.omittedLogLines = 50 - kept - 1
        let longer = BugReport.url(diagnostics: oneMore.render())
        #expect(longer.absoluteString.count > BugReport.maxLinkLength)
    }

    @Test("When even the report without log lines is too long, the form opens empty")
    func tooLongOpensEmptyForm() {
        let link = BugReport.link(for: report(logLines: ["INFO a"]), maxLength: 120)
        #expect(!link.carriesDiagnostics)
        #expect(query(link.url) == ["template": "bug_report.yml"])
    }

    @Test("A report with every log line left out does not claim the log is empty")
    func allLinesOmitted() {
        var r = report(logLines: [])
        r.omittedLogLines = 50
        let text = r.render()
        #expect(text.contains("Last 0 log lines (50 older ones did not fit the link"))
        #expect(!text.contains("(none yet)"))
    }
}
