import Foundation

/// The link behind Settings -> Debug -> Report a problem: a new GitHub issue
/// from the bug report form, with the diagnostics already in their field.
///
/// The app sends nothing itself. The diagnostics travel to GitHub in the
/// link the browser opens, so they also sit in the browser history, but
/// nothing is posted until the user reads the form and submits it
/// (VISION.md: diagnostics leave the Mac only when the user sends them, for
/// example as a prefilled bug report the user reads before submitting).
enum BugReport {
    static let newIssue = URL(string: "https://github.com/m-moravcik/VibeRes/issues/new")!
    /// `.github/ISSUE_TEMPLATE/bug_report.yml`, and the id of its diagnostics
    /// field, which GitHub fills from a query item of the same name.
    static let template = "bug_report.yml"
    static let diagnosticsField = "diagnostics"
    /// GitHub refuses a link much over 8 KB, so stay under it.
    static let maxLinkLength = 8_000

    struct Link: Equatable {
        let url: URL
        /// False when the diagnostics did not fit even without log lines: the
        /// link opens the empty form, and the caller hands over the report
        /// another way.
        let carriesDiagnostics: Bool
    }

    /// The longest report that fits: the oldest log lines go first, and the
    /// report says how many were left out.
    static func link(for report: Diagnostics.Report, maxLength: Int = maxLinkLength) -> Link {
        let lines = report.logLines
        for omitted in 0...lines.count {
            var trimmed = report
            trimmed.logLines = Array(lines.dropFirst(omitted))
            trimmed.omittedLogLines = omitted
            let url = url(diagnostics: trimmed.render())
            if url.absoluteString.count <= maxLength {
                return Link(url: url, carriesDiagnostics: true)
            }
        }
        return Link(url: url(diagnostics: nil), carriesDiagnostics: false)
    }

    static func url(diagnostics: String?) -> URL {
        var items = [("template", template)]
        if let diagnostics { items.append((diagnosticsField, diagnostics)) }
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)!
        // Encoded by hand: URLComponents leaves "+" and "&" in a value as
        // they are, and a form decoder reads "+" as a space.
        components.percentEncodedQuery = items
            .map { "\($0.0)=\(encode($0.1))" }
            .joined(separator: "&")
        return components.url!
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
