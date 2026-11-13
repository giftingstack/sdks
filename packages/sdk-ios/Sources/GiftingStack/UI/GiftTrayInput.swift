#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

extension View {
    /// Binds the app's text field to a tray (spec 20): the keyboard swap of a message bar. Put it on the
    /// `TextField` (it applies `.focused(focused)` itself, so do not add that again) and draw
    /// `GiftButton(tray: tray)` next to the field:
    ///
    /// ```swift
    /// @FocusState private var typing: Bool
    /// ...
    /// TextField("Message", text: $text)
    ///     .giftTrayInput(tray, focused: $typing)
    /// GiftButton(tray: tray)
    /// ```
    ///
    /// While bound, the tray starts closed (unless the model was given `open:`), `tray.toggle()` takes the focus
    /// away and then opens the tray in the keyboard's place, or closes it and then focuses the field again; the
    /// field getting focus (a tap on it) closes an open tray. `GiftTray(tray:)` uses the last keyboard height seen
    /// as its default height. The binding ends when the field leaves the screen.
    public func giftTrayInput(_ tray: GiftTrayModel, focused: FocusState<Bool>.Binding) -> some View {
        modifier(GiftTrayInputModifier(tray: tray, focused: focused))
    }
}

struct GiftTrayInputModifier: ViewModifier {
    let tray: GiftTrayModel
    let focused: FocusState<Bool>.Binding
    @State private var token: Int?

    func body(content: Content) -> some View {
        content
            .focused(focused)
            .onAppear {
                let binding = focused
                token = tray.bindInput { value in
                    binding.wrappedValue = value
                }
                if binding.wrappedValue {
                    tray.inputFocused()
                }
            }
            .onDisappear {
                if let token = token {
                    tray.unbindInput(token)
                }
                token = nil
            }
            .onChange(of: focused.wrappedValue) { isFocused in
                if isFocused {
                    tray.inputFocused()
                }
            }
    }
}
#endif
