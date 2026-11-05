import Foundation

// What the SwiftUI sheet measures and how it turns that into a `SheetLayout` (spec 9.1 content
// floors), plus the grid's scroll momentum. Pure, so it is unit-tested; `TraySheet.swift` (the
// fixture-tested port) is unchanged.

/// The sheet's measurements, in points. The UI builds one per render and applies it when it
/// changes, using only the new value (a SwiftUI `onChange` action can still see the previous
/// render's properties, which once fed an old gift count into the layout).
struct SheetMeasure: Equatable, Sendable {
    /// The gap between the header and the grid.
    static let bodyGap: Double = 12
    /// With no measured row (empty catalog) the sheet is shown after this long anyway (web: 700 ms).
    static let emptyFallbackMs = 700

    var containerHeight: Double
    /// Handle and header.
    var topBlockHeight: Double
    /// Selected gift and Send, with the bottom padding.
    var footerHeight: Double
    /// One grid row: a cell plus its 4 + 4 padding.
    var rowHeight: Double
    var giftCount: Int
    var columns: Int
    var snaps: SheetSnaps?

    var rows: Int {
        let perRow = max(1, columns)
        return giftCount <= 0 ? 0 : (giftCount + perRow - 1) / perRow
    }

    /// Header, footer and (with gifts) a row are measured. Until then the container counts as 0,
    /// so the sheet never shows heights computed from half a layout (as on Android).
    var floorsReady: Bool {
        topBlockHeight > 0 && footerHeight > 0 && (rows == 0 || rowHeight > 0)
    }

    var peekMinHeight: Double {
        topBlockHeight + SheetMeasure.bodyGap + footerHeight
    }

    var layout: SheetLayout {
        let peekMin = peekMinHeight
        return SheetLayout(
            containerHeight: floorsReady ? containerHeight : 0,
            snaps: snaps,
            peekMinHeight: peekMin,
            defaultMinHeight: peekMin + Double(min(2, rows)) * rowHeight,
            contentHeight: peekMin + Double(rows) * rowHeight
        )
    }

    /// Height of the grid's window: the body laid out at `expanded` minus the header block, the
    /// gap and the footer drawn over the body's bottom.
    func gridViewport(expanded: Double) -> Double {
        max(0, expanded - topBlockHeight - SheetMeasure.bodyGap - footerHeight)
    }

    /// How far the grid can scroll when the body is laid out at `expanded`.
    func maxGridScroll(expanded: Double) -> Double {
        max(0, Double(rows) * rowHeight - gridViewport(expanded: expanded))
    }
}

/// The grid's momentum after a flick: the velocity decays by 0.998 per millisecond (UIKit's
/// normal deceleration). Run frame by frame, so the scroll position is always what is on screen.
struct SheetGridMomentum: Sendable {
    static let decayPerMs: Double = 0.998
    /// Below this speed (points per second) the grid stops.
    static let minVelocity: Double = 20

    /// Points per second, positive = the scroll position grows (content moves up).
    var velocity: Double

    init(velocity: Double) {
        self.velocity = velocity.isFinite ? velocity : 0
    }

    var finished: Bool {
        abs(velocity) < SheetGridMomentum.minVelocity
    }

    /// The whole distance left if nothing stops it (reduced motion jumps there).
    var totalDistance: Double {
        velocity / -log(SheetGridMomentum.decayPerMs) / 1000
    }

    /// Advances `dtMs` milliseconds; returns the distance travelled in that time.
    mutating func step(dtMs: Double) -> Double {
        let dt = max(0, dtMs)
        let decay = pow(SheetGridMomentum.decayPerMs, dt)
        let distance = velocity * (1 - decay) / -log(SheetGridMomentum.decayPerMs) / 1000
        velocity *= decay
        return distance
    }
}
