import CoreGraphics
import Foundation
import Testing
@testable import VibeRes

/// `mainDisplay` is the 0.9.0 arrangement field. Pre-0.9 profile JSON has no
/// such key, and hand-written JSON may add one — both must round-trip.
@Suite("Profile.mainDisplay coding")
struct ProfileMainDisplayTests {
    @Test("Legacy JSON without mainDisplay decodes to nil")
    func legacyDecodesNil() throws {
        let json = Data("""
        {"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Desk","createdAt":0,
         "entries":[{"matcher":{"kind":"anyExternal"},"displayName":"LG",
                     "pointWidth":2560,"pointHeight":1440,"isHiDPI":false}]}
        """.utf8)
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        #expect(profile.mainDisplay == nil)
    }

    @Test("mainDisplay survives an encode/decode round trip")
    func roundTrip() throws {
        let profile = Profile(
            name: "Desk",
            entries: [Profile.Entry(
                matcher: .anyExternal, displayName: "LG",
                pointWidth: 2560, pointHeight: 1440, refreshHz: 60, isHiDPI: false
            )],
            mainDisplay: .edid(vendor: 1, model: 2, serial: 3)
        )
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        #expect(back.mainDisplay == .edid(vendor: 1, model: 2, serial: 3))
    }

    @Test("Default init leaves mainDisplay nil")
    func defaultNil() {
        let profile = Profile(name: "Desk", entries: [])
        #expect(profile.mainDisplay == nil)
    }
}
