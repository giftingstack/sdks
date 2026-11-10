import Foundation

// The tray's surroundings (spec section 9.4): the dim behind a bottom sheet (`scrim`) and the
// open/closed state the host's Gift button toggles. Pure: no UI, no clock. Port of
// `packages/sdk-js/src/core/scrim.ts` and `packages/sdk-flutter/lib/src/core/scrim.dart`.

/// What a tap on the scrim does. `.lower` lowers the sheet to peek first; `.dismiss` asks to close.
public enum ScrimTap: String, Sendable, Hashable {
    case lower
    case dismiss
}

/// The scrim fades in and out over this long (ms); at once with Reduce Motion. (`SCRIM_FADE_MS`)
public let scrimFadeDurationMs = 200

/// The scrim is black at this opacity. (`SCRIM_OPACITY`)
public let scrimOpacity = 0.4

/// The dim is drawn: asked for, open, in place, and the sheet is above peek (peek keeps the page in
/// sight). `snap` is the sheet's settled state, or the target of a running snap; `placed` is true
/// once the sheet is measured and drawn where it belongs.
public func scrimVisible(scrim: Bool, open: Bool, snap: SheetSnap, placed: Bool) -> Bool {
    scrim && open && placed && snap != .peek
}

/// The scrim takes touches: asked for, open and in place, in EVERY state including peek (a tap on the
/// empty space closes a peeking tray, 2026-11-09). The dim stays hidden at peek (`scrimVisible`); only
/// its touches are taken.
public func scrimTakesTouches(scrim: Bool, open: Bool, placed: Bool) -> Bool {
    scrim && open && placed
}

/// Fade duration in ms: `scrimFadeDurationMs`, or 0 with Reduce Motion.
public func scrimFadeMs(reducedMotion: Bool) -> Int {
    reducedMotion ? 0 : scrimFadeDurationMs
}

/// What a tap on the scrim leads to.
public enum ScrimTapOutcome: String, Sendable, Hashable {
    /// No scrim, or the tray is closed.
    case ignored
    /// Move the sheet to peek.
    case lower
    /// Close the tray (when it holds its own open state) and call `onDismiss`.
    case dismiss
}

/// A tap on the scrim. `.lower` (default) lowers any state above peek and dismisses from peek;
/// `.dismiss` dismisses from every state.
public func scrimTapOutcome(
    scrim: Bool,
    scrimTap: ScrimTap = .lower,
    open: Bool,
    snap: SheetSnap
) -> ScrimTapOutcome {
    if !scrim || !open {
        return .ignored
    }
    if scrimTap == .lower, snap != .peek {
        return .lower
    }
    return .dismiss
}

/// The open/closed state behind `open()`, `close()` and `toggle()`: the host's Gift button is
/// `tray.toggle()`. Every method returns the new state. A call that changes nothing returns the
/// state and notifies nobody. A change updates the state, then notifies subscribers, then calls
/// `onChange`. Use it on one thread (the main thread in the UI).
public final class TrayOpenState {
    /// Called after the state changed.
    public var onChange: ((Bool) -> Void)?

    private var current: Bool
    private var listeners: [(token: Int, callback: () -> Void)] = []
    private var nextToken = 0

    /// `open` is the initial state (default true: a tray that exists is shown).
    public init(open: Bool = true, onChange: ((Bool) -> Void)? = nil) {
        self.current = open
        self.onChange = onChange
    }

    public var isOpen: Bool {
        current
    }

    /// Opens. Returns the new state.
    @discardableResult
    public func open() -> Bool {
        set(true)
    }

    /// Closes. Returns the new state.
    @discardableResult
    public func close() -> Bool {
        set(false)
    }

    /// Open if closed, close if open. Returns the new state.
    @discardableResult
    public func toggle() -> Bool {
        set(!current)
    }

    /// Calls `listener` after every change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ listener: @escaping () -> Void) -> () -> Void {
        let token = nextToken
        nextToken += 1
        listeners.append((token: token, callback: listener))
        return { [weak self] in
            self?.listeners.removeAll { $0.token == token }
        }
    }

    private func set(_ next: Bool) -> Bool {
        if next == current {
            return current
        }
        current = next
        for listener in listeners {
            listener.callback()
        }
        onChange?(next)
        return next
    }
}
