import Foundation

/// A size in logical points.
///
/// A named pair rather than `(Int, Int)`, because an anonymous tuple has no
/// field names and every reader downstream pays for that: the outcome summary
/// used to be written in terms of `$0.0` and `$0.1`, which made it the one
/// function in `ProfileStore` that read worse than everything around it.
///
/// Deliberately *not* used for `Profile.Entry`, whose `pointWidth` and
/// `pointHeight` are the on-disk JSON shape and stay as they are.
struct PointSize: Equatable, Hashable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Digits and a multiplication sign, no units and no words, so it can be
    /// dropped into a sentence in any language.
    var formatted: String { "\(width)×\(height)" }
}
