import Foundation
import Testing
@testable import VibeRes

@Suite("DisplayMatcher coding")
struct DisplayMatcherTests {
    @Test("Round-trips an .edid matcher unchanged through JSON")
    func edidRoundTrip() throws {
        let m = DisplayMatcher.edid(vendor: 1507, model: 12921, serial: 1482)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(DisplayMatcher.self, from: data)
        #expect(decoded == m)
    }

    @Test("Round-trips an .anyExternal matcher")
    func anyExternalRoundTrip() throws {
        let m = DisplayMatcher.anyExternal
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(DisplayMatcher.self, from: data)
        #expect(decoded == m)
    }

    @Test("Round-trips a .builtIn matcher")
    func builtInRoundTrip() throws {
        let m = DisplayMatcher.builtIn(vendor: 1552, model: 41057, serial: 4251086178)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(DisplayMatcher.self, from: data)
        #expect(decoded == m)
    }

    @Test("Legacy Profile.Entry JSON without matcher decodes as .edid")
    func legacyDecodesAsEdid() throws {
        // Pre-DisplayMatcher era — entries had loose displayVendor/Model/Serial fields.
        let legacyJSON = """
        {
            "displayVendor": 1507,
            "displayModel": 12921,
            "displaySerial": 1482,
            "displayName": "Q3279WG5B",
            "pointWidth": 2560,
            "pointHeight": 1440,
            "refreshHz": 75,
            "isHiDPI": false
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let entry = try JSONDecoder().decode(Profile.Entry.self, from: data)

        switch entry.matcher {
        case let .edid(v, m, s):
            #expect(v == 1507)
            #expect(m == 12921)
            #expect(s == 1482)
        default:
            Issue.record("expected legacy entry to decode as .edid")
        }
        #expect(entry.pointWidth == 2560)
        #expect(entry.refreshHz == 75)
    }

    @Test("Profile.humanSummary describes mixed matcher types")
    func humanSummary() {
        let p = Profile(name: "Travel", entries: [
            Profile.Entry(
                matcher: .builtIn(vendor: 1, model: 2, serial: 3),
                displayName: "Built-in", pointWidth: 1280, pointHeight: 800,
                refreshHz: 60, isHiDPI: true
            ),
            Profile.Entry(
                matcher: .anyExternal,
                displayName: "External", pointWidth: 1920, pointHeight: 1080,
                refreshHz: 60, isHiDPI: false
            ),
        ])
        #expect(p.humanSummary == "Built-in + any external")
    }

    @Test("New Profile.Entry encodes matcher discriminator")
    func newEntryEncodesMatcher() throws {
        let entry = Profile.Entry(
            matcher: .anyExternal,
            displayName: "Any external",
            pointWidth: 1920, pointHeight: 1080,
            refreshHz: 60, isHiDPI: false
        )
        let data = try JSONEncoder().encode(entry)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"anyExternal\""))
        // And it round-trips:
        let decoded = try JSONDecoder().decode(Profile.Entry.self, from: data)
        #expect(decoded.matcher == .anyExternal)
    }
}
