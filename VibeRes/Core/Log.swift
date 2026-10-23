import Foundation
import os.log

/// How much the opt-in debug log file records. Ordered by noise: a level admits
/// itself and everything quieter.
enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case error = 0
    case info = 1
    case debug = 2

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .error: "ERROR"
        case .info: "INFO"
        case .debug: "DEBUG"
        }
    }
}

/// One logging facade for the app and the CLI (Core is compiled into both, so it
/// is Foundation-only). Every call goes to `os.Logger`, always; when the user has
/// opted in to the debug log file it also lands there, at the chosen verbosity.
///
/// Call sites read `Log.display.info("...")`. The message is public by contract:
/// it ends up in a file the user may attach to a GitHub issue, so it carries
/// counts, ids, display names and outcomes, never serial numbers or paths. Text
/// that is personal (profile names, anything user-typed) goes in `detail`, which
/// reaches `os.Logger` as `.private` and never reaches the file or the diagnostics.
struct AppLog: Sendable {
    static let subsystem = "sk.moravcik.VibeRes"

    let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: Self.subsystem, category: category)
    }

    /// Noisy detail, off in the file unless the user picked the debug verbosity.
    func debug(_ message: @autoclosure () -> String, detail: @autoclosure () -> String? = nil) {
        emit(.debug, message(), detail())
    }

    /// State changes worth reading in a bug report.
    func info(_ message: @autoclosure () -> String, detail: @autoclosure () -> String? = nil) {
        emit(.info, message(), detail())
    }

    /// Failures: a rejected mode, a failed transaction, a read-back that differs.
    func error(_ message: @autoclosure () -> String, detail: @autoclosure () -> String? = nil) {
        emit(.error, message(), detail())
    }

    private func emit(_ level: LogLevel, _ message: String, _ detail: String?) {
        // `notice`, not `info`, for our info level: os `info` lives in memory only
        // and is gone before anyone looks, while `notice` is persisted - which is
        // what the maintainer's log collection relies on.
        let osLevel: OSLogType = switch level {
        case .debug: .debug
        case .info: .default
        case .error: .error
        }
        if let detail {
            logger.log(level: osLevel, "\(message, privacy: .public) \(detail, privacy: .private)")
        } else {
            logger.log(level: osLevel, "\(message, privacy: .public)")
        }
        LogSink.shared.write(level, category: category, message)
    }
}

enum Log {
    static let display = AppLog(category: "display")
    static let apply = AppLog(category: "apply")
    static let autoApply = AppLog(category: "autoApply")
    static let profiles = AppLog(category: "profiles")
    static let updates = AppLog(category: "updates")
    static let capture = AppLog(category: "capture")
    static let app = AppLog(category: "app")
}

/// Decides whether a line reaches the debug log file and owns the file. Off until
/// `configure` turns it on, so the CLI and every test run write nothing.
final class LogSink: @unchecked Sendable {
    static let shared = LogSink(file: LogFile(url: LogFile.defaultURL))

    private let file: LogFile
    private let lock = NSLock()
    private var enabled = false
    private var verbosity = LogLevel.info

    init(file: LogFile) {
        self.file = file
    }

    var fileURL: URL { file.url }

    func configure(enabled: Bool, verbosity: LogLevel) {
        lock.lock()
        self.enabled = enabled
        self.verbosity = verbosity
        lock.unlock()
    }

    func write(_ level: LogLevel, category: String, _ message: String) {
        lock.lock()
        let admitted = enabled && level <= verbosity
        lock.unlock()
        guard admitted else { return }
        file.append(level: level, category: category, message: message)
    }

    /// Blocks until queued lines are on disk. For tests and "Open log file".
    func flush() {
        file.flush()
    }

    func lastLines(_ count: Int) -> [String] {
        file.lastLines(count)
    }

    /// The log file's URL, created empty if nothing has been written yet.
    func existingFileURL() -> URL {
        file.ensureExists()
        return file.url
    }
}

/// `~/Library/Logs/VibeRes/VibeRes.log`: `<ISO8601> <LEVEL> <category> <message>`,
/// 0600 in a 0700 folder, rolled to `VibeRes.log.1` by rename once it passes the
/// cap, so the disk cost is bounded at about twice the cap. Same shape as the
/// sibling apps' logs.
final class LogFile: @unchecked Sendable {
    static let defaultMaxBytes = 512 * 1024
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VibeRes/VibeRes.log")

    let url: URL
    private let maxBytes: Int
    private let now: @Sendable () -> Date
    /// Serial and utility priority: a log write never blocks the main thread
    /// and lines keep their order.
    private let queue = DispatchQueue(label: "sk.moravcik.VibeRes.logfile", qos: .utility)

    init(url: URL, maxBytes: Int = LogFile.defaultMaxBytes, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.maxBytes = maxBytes
        self.now = now
    }

    func append(level: LogLevel, category: String, message: String) {
        // One line per entry: a stray newline would forge a second log record.
        let flat = message.replacingOccurrences(of: "\n", with: " ")
        let stamp = now()
        queue.async { [self] in
            let line = "\(stamp.formatted(.iso8601)) \(level.label) \(category) \(flat)\n"
            write(line)
        }
    }

    func flush() {
        queue.sync {}
    }

    private func createIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }

    /// Makes sure there is a file to open, so "Open log file" works right after
    /// the opt-in, before the first line has been written.
    func ensureExists() {
        queue.sync { createIfNeeded() }
    }

    private var rolledURL: URL { url.appendingPathExtension("1") }

    private func write(_ line: String) {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0, size + line.utf8.count > maxBytes {
            // rename(2) replaces an existing destination atomically.
            if rename(url.path, rolledURL.path) != 0 {
                FileHandle.standardError.write(Data("VibeRes log roll failed (errno \(errno))\n".utf8))
            }
        }
        createIfNeeded()
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// The last `count` lines, reaching into the rolled file when the current one
    /// is shorter. Empty when there is no log.
    func lastLines(_ count: Int) -> [String] {
        flush()
        func lines(_ url: URL) -> [String] {
            guard let data = try? Data(contentsOf: url) else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        }
        var result = lines(url)
        if result.count < count {
            result = lines(rolledURL) + result
        }
        return Array(result.suffix(count))
    }
}
