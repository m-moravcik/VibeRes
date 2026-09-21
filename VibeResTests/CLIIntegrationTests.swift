import Foundation
import Testing
@testable import VibeRes

/// Runs the real `viberes` binary.
///
/// The CLI had been covered only by CI shelling out `viberes help` and one bad
/// spec, so the two defects that lived in it — a blank name printing `saved
/// profile` over an empty catalog, and a duplicate name being resolved by
/// whichever profile happened to come first — were invisible to the suite.
/// `ProfileStore.resolve` is unit-tested separately; this asserts that the
/// binary actually wires it up and exits with the right code.
///
/// Every run gets `VIBERES_PROFILE_DIR` pointed at a temporary directory, so
/// none of this touches the catalog the person using this machine has.
@Suite("viberes CLI")
struct CLIIntegrationTests {
    /// The binary sits beside the test host in the build products directory —
    /// the VibeRes scheme builds `viberes-cli` for the test action so it is
    /// there rather than at a guessed derived-data path.
    private static var binaryURL: URL? {
        let products = Bundle.main.bundleURL.deletingLastPathComponent()
        let candidate = products.appending(path: "viberes")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func run(_ arguments: [String], profileDirectory: URL) throws -> Run {
        let binary = try #require(Self.binaryURL, "viberes was not built beside the test bundle")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment[ProfileStore.directoryEnvironmentKey] = profileDirectory.path
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting: a pipe that fills up deadlocks the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Run(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResCLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a catalog directly, for the shapes the CLI refuses to create.
    private func writeCatalog(_ profiles: [Profile], to directory: URL) throws {
        try JSONEncoder().encode(profiles)
            .write(to: directory.appendingPathComponent("profiles.json"))
    }

    private func profile(_ name: String) -> Profile {
        Profile(name: name, entries: [
            Profile.Entry(
                matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                displayName: "Built-in",
                pointWidth: 1800, pointHeight: 1169,
                refreshHz: 120, isHiDPI: true
            ),
        ])
    }

    // MARK: Basics

    @Test("help exits zero and names every subcommand")
    func helpListsCommands() throws {
        let dir = try temporaryDirectory()
        let result = try run(["help"], profileDirectory: dir)
        #expect(result.status == 0)
        for command in ["list", "modes", "current", "set", "profile apply", "profile rename"] {
            #expect(result.stdout.contains(command), "help does not mention \(command)")
        }
    }

    @Test("An unknown command fails with a message on stderr, not stdout")
    func unknownCommandFails() throws {
        let dir = try temporaryDirectory()
        let result = try run(["frobnicate"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("unknown command"))
        #expect(result.stdout.isEmpty, "errors belong on stderr so pipelines stay clean")
    }

    @Test("An unparseable mode spec is refused before anything is applied")
    func badSpecRefused() throws {
        let dir = try temporaryDirectory()
        let result = try run(["set", "Built-in", "garbage-spec"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("could not parse"))
    }

    // MARK: The store is honoured

    @Test("The profile directory override is honoured, so tests never touch the real catalog")
    func honoursDirectoryOverride() throws {
        let dir = try temporaryDirectory()
        try writeCatalog([profile("Work")], to: dir)
        let result = try run(["profile", "list"], profileDirectory: dir)
        #expect(result.status == 0)
        #expect(result.stdout.contains("Work"))
    }

    @Test("An empty catalog says so rather than printing nothing")
    func emptyCatalog() throws {
        let dir = try temporaryDirectory()
        let result = try run(["profile", "list"], profileDirectory: dir)
        #expect(result.status == 0)
        #expect(result.stdout.contains("(no profiles)"))
    }

    // MARK: Refusals are reported

    @Test("A blank profile name is refused instead of reported as saved")
    func blankNameRefused() throws {
        // The regression: `add` dropped the profile and `captureCurrent`
        // returned `.saved` anyway, so this printed `saved profile "   "` and
        // stored nothing.
        let dir = try temporaryDirectory()
        let result = try run(["profile", "save", "   "], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("cannot be blank"))
        #expect(!result.stdout.contains("saved profile"))

        let listing = try run(["profile", "list"], profileDirectory: dir)
        #expect(listing.stdout.contains("(no profiles)"))
    }

    @Test("A duplicate profile name is refused")
    func duplicateNameRefused() throws {
        let dir = try temporaryDirectory()
        try writeCatalog([profile("Work")], to: dir)
        let result = try run(["profile", "save", "Work"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("already exists"))
    }

    @Test("Renaming onto an existing name is refused, and says nothing about renaming")
    func renameOntoExistingRefused() throws {
        let dir = try temporaryDirectory()
        try writeCatalog([profile("Work"), profile("Presentation")], to: dir)
        let result = try run(["profile", "rename", "Presentation", "Work"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("already exists"))
        #expect(!result.stdout.contains("renamed"))
    }

    // MARK: Lookup

    @Test("A profile resolves by name, case-insensitively")
    func resolvesByNameIgnoringCase() throws {
        let dir = try temporaryDirectory()
        try writeCatalog([profile("Work")], to: dir)
        let result = try run(["profile", "show", "wOrK"], profileDirectory: dir)
        #expect(result.status == 0)
        #expect(result.stdout.contains("Work"))
    }

    @Test("A profile resolves by the id that `profile list` prints")
    func resolvesByID() throws {
        let dir = try temporaryDirectory()
        let saved = profile("Work")
        try writeCatalog([saved], to: dir)
        let result = try run(["profile", "show", saved.id.uuidString], profileDirectory: dir)
        #expect(result.status == 0)
        #expect(result.stdout.contains("Work"))
    }

    @Test("An unknown profile is a failure, not an empty success")
    func unknownProfileFails() throws {
        let dir = try temporaryDirectory()
        let result = try run(["profile", "show", "Nope"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("no profile named"))
    }

    @Test("Duplicate names in an older catalog are reported, never picked between")
    func duplicateNamesAreAmbiguous() throws {
        // The CLI refuses to create this, but a catalog written by 0.9.0 can
        // already hold it — and picking the first match would make
        // `profile apply Work` a coin flip.
        let dir = try temporaryDirectory()
        try writeCatalog([profile("Work"), profile("Work")], to: dir)
        let result = try run(["profile", "show", "Work"], profileDirectory: dir)
        #expect(result.status == 1)
        #expect(result.stderr.contains("2 profiles are named"))
        #expect(result.stderr.contains("address it by id"))
    }
}
