@testable import VibeRes

extension DisplayStore {
    /// A store whose popover handling never reaches AppKit: a unit test has
    /// no business scanning `NSApp.windows` or moving a window. A test that
    /// observes the popover replaces either seam after this.
    static func forTesting() -> DisplayStore {
        let store = DisplayStore()
        store.dismissStalePopoverOverride = {}
        store.popoverIsOpenOverride = { false }
        return store
    }
}
