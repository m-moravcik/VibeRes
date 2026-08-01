import Foundation
import Testing
@testable import VibeRes

/// Which builds are allowed to update themselves.
///
/// This is the security boundary of the whole updater: something that downloads
/// and executes a binary without checking who signed it is remote code
/// execution. It is also the part the reference implementation gets wrong — its
/// Homebrew check tests whether the running bundle's path contains
/// `/Caskroom/`, which is never true, because a cask *moves* the app to
/// /Applications and leaves the symlink pointing the other way. Verified against
/// a real install:
///
///     /opt/homebrew/Caskroom/1password/8.12.12/1Password.app -> /Applications/1Password.app
///
/// So the comparison has to start from the Caskroom side. These tests pin that
/// down, and they are why the decision is a pure function rather than something
/// reading Bundle.main inside a factory.
@Suite("Updater gate")
struct UpdaterGateTests {
    private let installed = URL(fileURLWithPath: "/Applications/VibeRes.app")

    @Test("A signed app in /Applications may update itself")
    func signedAppIsAllowed() {
        #expect(UpdaterGate.decide(
            bundleURL: installed,
            isDeveloperIDSigned: true,
            caskroomBundleURLs: []
        ) == .enabled)
    }

    @Test("An unsigned build never updates itself, whatever else is true")
    func unsignedIsRefusedFirst() {
        // Checked before anything else so a debug build cannot self-update, and
        // so an unsigned build near a Caskroom is not told to run brew for
        // something Homebrew never installed.
        #expect(UpdaterGate.decide(
            bundleURL: installed,
            isDeveloperIDSigned: false,
            caskroomBundleURLs: [installed]
        ) == .disabled(reason: .notSigned))
    }

    @Test("A cask install defers to Homebrew, matched from the Caskroom side")
    func homebrewInstallDefers() {
        // The Caskroom entry resolves to the same path as the running bundle;
        // path containment on the bundle itself would never fire.
        #expect(UpdaterGate.decide(
            bundleURL: installed,
            isDeveloperIDSigned: true,
            caskroomBundleURLs: [
                URL(fileURLWithPath: "/Applications/SomethingElse.app"),
                installed,
            ]
        ) == .disabled(reason: .managedByHomebrew))
    }

    @Test("A build that is not an .app bundle cannot update itself")
    func looseBinaryIsRefused() {
        #expect(UpdaterGate.decide(
            bundleURL: URL(fileURLWithPath: "/tmp/build/Release/VibeRes"),
            isDeveloperIDSigned: true,
            caskroomBundleURLs: []
        ) == .disabled(reason: .notABundle))
    }

    @Test("An unrelated Caskroom entry does not disable updates")
    func otherCasksAreIrrelevant() {
        #expect(UpdaterGate.decide(
            bundleURL: installed,
            isDeveloperIDSigned: true,
            caskroomBundleURLs: [URL(fileURLWithPath: "/Applications/1Password.app")]
        ) == .enabled)
    }

    @Test("Every disabled reason explains itself to the user")
    func reasonsAreUserFacing() {
        for reason in [UpdaterGate.Reason.notSigned, .managedByHomebrew, .notABundle] {
            #expect(!reason.userFacingDescription.isEmpty)
        }
        // The Homebrew case must name the command, or the advice is useless.
        #expect(UpdaterGate.Reason.managedByHomebrew.userFacingDescription.contains("brew upgrade"))
    }
}
