import Foundation

// The tray as a draggable bottom sheet, without a UI (spec section 9.1). Ported line by line from
// `packages/sdk-js/src/core/sheet.ts`. The sheet is laid out once at its tallest (`expanded`) and
// moved down by `offset`; the visible height is `heights.expanded - offset`. Lengths are points.

/// The snap states, from the most closed to the most open (`SHEET_SNAPS`).
public enum SheetSnap: String, Sendable, Hashable, CaseIterable {
    case peek
    case `default`
    case expanded
}

/// Snap heights as fractions of the container. nil (or not finite) means "use the default".
public struct SheetSnaps: Sendable, Equatable {
    public var peek: Double?
    public var `default`: Double?
    public var expanded: Double?

    public init(peek: Double? = nil, default defaultFraction: Double? = nil, expanded: Double? = nil) {
        self.peek = peek
        self.default = defaultFraction
        self.expanded = expanded
    }

    public subscript(_ snap: SheetSnap) -> Double? {
        switch snap {
        case .peek:
            return peek
        case .default:
            return self.default
        case .expanded:
            return expanded
        }
    }
}

/// What the UI measured. Missing values are not given.
public struct SheetLayout: Sendable, Equatable {
    public var containerHeight: Double
    public var snaps: SheetSnaps?
    /// Handle, header and the footer (selected gift, Send).
    public var peekMinHeight: Double?
    /// Peek plus up to two rows of gifts.
    public var defaultMinHeight: Double?
    /// Peek plus every row of gifts; caps `expanded` (never below default).
    public var contentHeight: Double?

    public init(
        containerHeight: Double,
        snaps: SheetSnaps? = nil,
        peekMinHeight: Double? = nil,
        defaultMinHeight: Double? = nil,
        contentHeight: Double? = nil
    ) {
        self.containerHeight = containerHeight
        self.snaps = snaps
        self.peekMinHeight = peekMinHeight
        self.defaultMinHeight = defaultMinHeight
        self.contentHeight = contentHeight
    }
}

public struct SheetHeights: Sendable, Equatable {
    public var peek: Double
    public var `default`: Double
    public var expanded: Double

    public init(peek: Double, default defaultHeight: Double, expanded: Double) {
        self.peek = peek
        self.default = defaultHeight
        self.expanded = expanded
    }

    public subscript(_ snap: SheetSnap) -> Double {
        switch snap {
        case .peek:
            return peek
        case .default:
            return self.default
        case .expanded:
            return expanded
        }
    }
}

/// Round half up, as the reference's `Math.round` does for the non-negative values used here.
func sheetRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}

private func sheetPositive(_ value: Double?) -> Double {
    guard let v = value, v.isFinite, v > 0 else {
        return 0
    }
    return v
}

/// The three snap heights. Always `0 <= peek <= default <= expanded <= containerHeight`.
public func resolveSheetHeights(_ layout: SheetLayout) -> SheetHeights {
    let h = sheetPositive(layout.containerHeight)
    func fraction(_ s: SheetSnap) -> Double {
        if let f = layout.snaps?[s], f.isFinite {
            return min(1, max(0, f))
        }
        return TraySheetController.defaultFractions[s] ?? 0
    }
    let peek = max(sheetRound(fraction(.peek) * h), sheetPositive(layout.peekMinHeight))
    let def = max(max(sheetRound(fraction(.default) * h), sheetPositive(layout.defaultMinHeight)), peek)
    var expanded = sheetRound(fraction(.expanded) * h)
    let content = sheetPositive(layout.contentHeight)
    if content > 0 {
        expanded = min(expanded, content)
    }
    expanded = max(expanded, def)
    return SheetHeights(peek: min(peek, h), default: min(def, h), expanded: min(expanded, h))
}

public struct TraySheetState: Sendable, Equatable {
    /// The settled state, or the one the sheet moves to. Unchanged during a drag.
    public var snap: SheetSnap
    /// How far the sheet is moved down from fully open. 0 = expanded.
    public var offset: Double
    /// `heights.expanded - offset`: the sheet's top edge from the container's bottom.
    public var visibleHeight: Double
    public var dragging: Bool
    public var heights: SheetHeights
    /// The grid scrolls by itself only when the sheet is fully open and not dragged.
    public var gridScrollable: Bool
}

/// Who takes a drag that starts on the gift grid.
public enum SheetScrollOwner: String, Sendable, Hashable {
    case sheet
    case grid
}

/// The pure sheet logic (spec 9.1). Not tied to an actor; the SwiftUI tray uses it on the main
/// thread only.
public final class TraySheetController {
    /// A release at least this fast (points per second) moves one state in the flick's direction.
    public static let flickVelocity: Double = 600
    /// Default snap fractions: 0 = fit the content.
    public static let defaultFractions = SheetSnaps(peek: 0, default: 0, expanded: 0.9)

    private var heights: SheetHeights
    private var snap: SheetSnap
    private var offset: Double
    private var dragging = false
    /// The unclamped drag position, so the sheet stays under the finger after an over-drag.
    private var raw: Double = 0
    public private(set) var state: TraySheetState
    private var onSnapChange: ((SheetSnap) -> Void)?
    private var observers: [(token: Int, callback: (TraySheetState) -> Void)] = []
    private var nextToken = 0

    public init(
        initialSnap: SheetSnap = .default,
        layout: SheetLayout? = nil,
        onSnapChange: ((SheetSnap) -> Void)? = nil
    ) {
        let resolved = resolveSheetHeights(layout ?? SheetLayout(containerHeight: 0))
        let startOffset = resolved.expanded - resolved[initialSnap]
        self.heights = resolved
        self.snap = initialSnap
        self.onSnapChange = onSnapChange
        self.offset = startOffset
        self.state = TraySheetState(
            snap: initialSnap,
            offset: startOffset,
            visibleHeight: resolved.expanded - startOffset,
            dragging: false,
            heights: resolved,
            gridScrollable: startOffset == 0
        )
    }

    public func setOnSnapChange(_ callback: ((SheetSnap) -> Void)?) {
        onSnapChange = callback
    }

    /// Calls `observer` after every state change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ observer: @escaping (TraySheetState) -> Void) -> () -> Void {
        let token = nextToken
        nextToken += 1
        observers.append((token: token, callback: observer))
        return { [weak self] in
            self?.observers.removeAll { $0.token == token }
        }
    }

    /// The offset at which `snap` is fully shown.
    public func offsetOf(_ snap: SheetSnap) -> Double {
        heights.expanded - heights[snap]
    }

    /// New measurements. Keeps the state; during a drag the position is clamped again.
    public func setLayout(_ layout: SheetLayout) {
        heights = resolveSheetHeights(layout)
        offset = dragging ? clamp(raw) : offsetOf(snap)
        emit()
    }

    public func dragStart() {
        if dragging {
            return
        }
        dragging = true
        raw = offset
        emit()
    }

    /// The finger moved `dy` (positive = down). Starts a drag if none is running.
    public func drag(_ dy: Double) {
        if !dragging {
            dragStart()
        }
        raw += dy
        offset = clamp(raw)
        emit()
    }

    /// The finger lifted with `velocity` (points per second, positive = down). Without a drag
    /// nothing changes and the current state is returned.
    @discardableResult
    public func release(_ velocity: Double = 0) -> SheetSnap {
        if !dragging {
            return snap
        }
        dragging = false
        let target = pick(velocity)
        settle(target)
        return target
    }

    /// The drag was interrupted: back to the state it started from. No `onSnapChange`.
    public func cancel() {
        if !dragging {
            return
        }
        dragging = false
        offset = offsetOf(snap)
        emit()
    }

    public func snapTo(_ target: SheetSnap) {
        dragging = false
        settle(target)
    }

    /// Tap on the handle: default closes to peek; peek and expanded go to default.
    @discardableResult
    public func toggle() -> SheetSnap {
        let next: SheetSnap = snap == .default ? .peek : .default
        snapTo(next)
        return next
    }

    /// Keyboard or accessibility step: +1 opens one state, -1 closes one, clamped at the ends.
    @discardableResult
    public func step(_ direction: Int) -> SheetSnap {
        let all = SheetSnap.allCases
        let at = all.firstIndex(of: snap) ?? 0
        let index = min(all.count - 1, max(0, at + (direction >= 0 ? 1 : -1)))
        let next = all[index]
        snapTo(next)
        return next
    }

    /// A drag that starts on the grid moved `dy` first (positive = down). Decide once per gesture.
    public func scrollOwner(dy: Double, gridScrollTop: Double) -> SheetScrollOwner {
        if dragging || offset > 0 {
            return .sheet
        }
        if dy > 0 && gridScrollTop <= 0 {
            return .sheet
        }
        return .grid
    }

    // MARK: - Private

    private func clamp(_ value: Double) -> Double {
        min(offsetOf(.peek), max(0, value))
    }

    /// Flick: the nearest state beyond the position in the flick's direction, else the nearest
    /// state. Otherwise the nearest state. Ties go to the more open state.
    private func pick(_ velocity: Double) -> SheetSnap {
        let open: [SheetSnap] = [.expanded, .default, .peek]
        let o = offset
        if abs(velocity) >= TraySheetController.flickVelocity {
            let up = velocity < 0
            var best: SheetSnap?
            for s in open {
                let so = offsetOf(s)
                let skip = up ? so >= o : so <= o
                if skip {
                    continue
                }
                if let current = best {
                    let bo = offsetOf(current)
                    let better = up ? so > bo : so < bo
                    if better {
                        best = s
                    }
                } else {
                    best = s
                }
            }
            if let found = best {
                return found
            }
        }
        var nearest: SheetSnap = .expanded
        for s in open {
            if abs(offsetOf(s) - o) < abs(offsetOf(nearest) - o) {
                nearest = s
            }
        }
        return nearest
    }

    private func settle(_ target: SheetSnap) {
        let changed = target != snap
        snap = target
        offset = offsetOf(target)
        emit()
        if changed {
            onSnapChange?(target)
        }
    }

    private func build() -> TraySheetState {
        TraySheetState(
            snap: snap,
            offset: offset,
            visibleHeight: heights.expanded - offset,
            dragging: dragging,
            heights: heights,
            gridScrollable: offset == 0 && !dragging
        )
    }

    private func emit() {
        let next = build()
        if next == state {
            return
        }
        state = next
        for entry in observers {
            entry.callback(next)
        }
    }
}

/// Release velocity from the samples of the last 100 ms (the web's method, spec 9.1 UI rules).
/// SwiftUI's `DragGesture` has no velocity before iOS 17, so the tray measures it this way.
public struct SheetVelocityTracker: Sendable {
    public static let windowMs: Double = 100
    private var samples: [(t: Double, y: Double)] = []

    public init() {}

    /// `t` in milliseconds, `y` in points.
    public mutating func add(t: Double, y: Double) {
        samples.append((t: t, y: y))
        // Keep a little more than the window; older samples never matter.
        while let first = samples.first, t - first.t > SheetVelocityTracker.windowMs * 2 {
            samples.removeFirst()
        }
    }

    public mutating func reset() {
        samples = []
    }

    /// Points per second, positive = down. 0 when the finger rested for the whole window.
    public func velocity() -> Double {
        guard let last = samples.last else {
            return 0
        }
        let first = samples.first(where: { last.t - $0.t <= SheetVelocityTracker.windowMs }) ?? last
        let dt = last.t - first.t
        return dt > 0 ? (last.y - first.y) / dt * 1000 : 0
    }
}
