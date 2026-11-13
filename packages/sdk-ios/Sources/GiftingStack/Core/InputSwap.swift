import Foundation

// The gift button in the app's message bar (spec section 20): the button closes the keyboard and
// opens the tray in its place; a tap on the text field closes the tray and the keyboard comes back.
// Pure: no UI, no clock; `GiftTrayModel` and `.giftTrayInput` do the blur, focus, open and close.
// Port of `packages/sdk-js/src/core/inputSwap.ts`.

/// What happened: the gift button (`toggle()`), or the bound text field got focus.
public enum InputSwapEvent: String, Sendable, Hashable {
    case button
    case inputFocus
}

/// What a swap step does to the tray.
public enum InputSwapTray: String, Sendable, Hashable {
    case open
    case close
    case keep
}

/// What a swap step does to the text field (and so the keyboard).
public enum InputSwapInput: String, Sendable, Hashable {
    case blur
    case focus
    case keep
}

/// One step of the keyboard swap. Run `input == .blur` BEFORE `tray == .open`, and
/// `tray == .close` BEFORE `input == .focus`.
public struct InputSwapStep: Sendable, Hashable {
    public var tray: InputSwapTray
    public var input: InputSwapInput

    public init(tray: InputSwapTray, input: InputSwapInput) {
        self.tray = tray
        self.input = input
    }
}

/// The tray's height in the keyboard's place before any keyboard was seen. (`KEYBOARD_PLACE_FALLBACK`)
public let keyboardPlaceFallback: Double = 300

/// A smaller inset is not a keyboard (an accessory bar, a hardware keyboard). (`KEYBOARD_MIN_HEIGHT`)
public let keyboardMinHeight: Double = 120

/// The keyboard's place never takes more than this share of the container. (`KEYBOARD_PLACE_MAX_FRACTION`)
public let keyboardPlaceMaxFraction = 0.6

/// One step of the keyboard swap (spec 20.2).
public func inputSwapStep(open: Bool, event: InputSwapEvent) -> InputSwapStep {
    switch event {
    case .button:
        return open ? InputSwapStep(tray: .close, input: .focus) : InputSwapStep(tray: .open, input: .blur)
    case .inputFocus:
        return open ? InputSwapStep(tray: .close, input: .keep) : InputSwapStep(tray: .keep, input: .keep)
    }
}

/// How tall the tray is in the keyboard's place (spec 20.2), in points. `keyboardHeight`: the last
/// keyboard height seen (nil or below `keyboardMinHeight`: the fallback 300). `containerHeight`: the
/// box the tray fills (nil or 0: unknown, no cap).
public func keyboardPlaceHeight(keyboardHeight: Double?, containerHeight: Double?) -> Int {
    var k = keyboardPlaceFallback
    if let h = keyboardHeight, h.isFinite, h >= keyboardMinHeight {
        k = h
    }
    if let c = containerHeight, c.isFinite, c > 0 {
        k = min(k, (c * keyboardPlaceMaxFraction).rounded(.down))
    }
    return Int(k.rounded())
}

/// The sheet's `default` snap as a fraction of the container for the keyboard's place, or nil while
/// the container is not measured.
public func keyboardPlaceSnap(keyboardHeight: Double?, containerHeight: Double?) -> Double? {
    guard let c = containerHeight, c.isFinite, c > 0 else {
        return nil
    }
    return Double(keyboardPlaceHeight(keyboardHeight: keyboardHeight, containerHeight: c)) / c
}
