#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The SwiftUI state holder for a tray: a `GiftTrayController` (spec section 8) that publishes
/// its state. Pictures are prefetched into `GiftImageCache`, local sends play on `effects`.
///
/// ```swift
/// @StateObject var effects = GiftEffectController()
/// @StateObject var tray = GiftTrayModel(client: client, receiver: "mert")
/// ...
/// GiftTray(gifts: tray.gifts, balance: tray.balance, onSend: { tray.send($0) })
///     .onAppear { tray.effects = effects; tray.start() }
///     .onDisappear { tray.stop() }
/// ```
@MainActor
public final class GiftTrayModel: ObservableObject {
    @Published public private(set) var state: GiftTrayState

    /// Whether the tray is open (spec 9.4). `GiftTray(tray: tray)` shows itself only while this is true. Starts true
    /// unless you passed `open: false`, or a text field is bound with `.giftTrayInput` (then it starts closed unless
    /// you passed `open: true`); the host's Gift button is `tray.toggle()` or `GiftButton(tray: tray)`.
    @Published public private(set) var isOpen: Bool

    /// A text field is bound with `.giftTrayInput(tray, focused:)` (spec 20): `toggle()` swaps the keyboard and the
    /// tray, the field's focus closes the tray, and `GiftTray(tray:)` takes the keyboard's place.
    @Published public private(set) var inputBound = false

    /// The last keyboard height seen (points, at least `keyboardMinHeight`), nil before any. It is kept when the
    /// keyboard goes down: the tray takes the keyboard's place (spec 20.3).
    @Published public private(set) var keyboardHeight: Double?

    /// The pure state holder underneath. Its settings (`client`, `receiver`, `playOn`,
    /// `reference`, `roomId`, `onSent`, `onError`) may be changed at any time.
    public let controller: GiftTrayController

    /// The sides of a battle the viewer can send to (spec 21). Two or more: `GiftTray(tray:)` shows its "Send to"
    /// row and every send goes to `receiver`. Empty (default): the tray is as before (`controller.receiver`). A new
    /// list (for example the next round's sides) keeps the pick when it is still in it, else resolves again.
    @Published public var receivers: [TrayReceiver] {
        didSet {
            receiversChanged(from: oldValue)
        }
    }

    /// The side the person (or `selectReceiver`) picked, nil before any pick. `receiver` is what counts.
    @Published public private(set) var selectedReceiver: String?

    /// The receiver of this tray's last successful send.
    @Published public private(set) var lastReceiver: String?

    /// The receiver the next gift goes to changed (a tap in the "Send to" row, `selectReceiver`, or a new list).
    public var onReceiverChange: ((String) -> Void)?

    /// Who the next gift goes to (spec 21.2): the picked side if it is in `receivers`, else the side of the last
    /// successful send, else `controller.receiver` if it is one of them, else the first side. Without `receivers`:
    /// `controller.receiver`.
    public var receiver: String {
        resolveReceiver(
            ids: receivers.map { $0.id },
            selected: selectedReceiver,
            last: lastReceiver,
            fallback: controller.receiver
        ) ?? controller.receiver
    }

    /// The effect layer that shows each local send. Held weakly.
    public var effects: GiftEffectController? {
        get { effectsBox.value }
        set { effectsBox.value = newValue }
    }

    private let effectsBox: WeakEffects
    private var unsubscribe: (() -> Void)?
    private let openState: TrayOpenState
    private var unsubscribeOpen: (() -> Void)?
    /// `open:` was passed to the initialiser: a bound text field does not change the first state.
    private let openGiven: Bool
    /// `open()`, `close()` or `toggle()` was called: a later binding does not close the tray.
    private var openTouched = false
    /// Moves the bound field's focus (`false` = blur, the keyboard goes down). nil while no field is bound.
    private var setInputFocus: ((Bool) -> Void)?
    private var inputToken = 0
    private var keyboardObserver: KeyboardHeightObserver?

    public init(
        client: any GiftingAPI,
        receiver: String,
        effects: GiftEffectController? = nil,
        playOn: PlayOn = .tap,
        reference: String? = nil,
        roomId: String? = nil,
        receiverOf: ((String) -> GiftEffectReceiver?)? = nil,
        onSent: ((GiftTransaction) -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil,
        open: Bool? = nil,
        onOpenChange: ((Bool) -> Void)? = nil,
        receivers: [TrayReceiver] = [],
        onReceiverChange: ((String) -> Void)? = nil
    ) {
        // The first value, not a change: no `didSet`.
        _receivers = Published(wrappedValue: receivers)
        self.onReceiverChange = onReceiverChange
        let box = WeakEffects()
        box.value = effects
        self.effectsBox = box
        let controller = GiftTrayController(
            client: client,
            receiver: receiver,
            effects: { box.value },
            playOn: playOn,
            reference: reference,
            roomId: roomId,
            receiverOf: receiverOf,
            onSent: onSent,
            onError: onError,
            prefetch: { url in
                GiftImageCache.shared.prefetch(url)
            }
        )
        self.controller = controller
        self.state = controller.state
        let openState = TrayOpenState(open: open ?? true, onChange: onOpenChange)
        self.openState = openState
        self.isOpen = open ?? true
        self.openGiven = open != nil
        unsubscribeOpen = openState.subscribe { [weak self, weak openState] in
            if let self = self, let openState = openState {
                self.isOpen = openState.isOpen
            }
        }
        unsubscribe = controller.subscribe { [weak self] next in
            guard let self = self else {
                return
            }
            self.state = next
            // `GiftTray(testMode: nil)` follows this: a test token shows the "Test mode" badge.
            GiftTrayTestModeRegistry.shared.report(ObjectIdentifier(self), testMode: next.testMode)
        }
        keyboardObserver = KeyboardHeightObserver { [weak self] height in
            self?.recordKeyboardHeight(height)
        }
    }

    deinit {
        let id = ObjectIdentifier(self)
        if Thread.isMainThread {
            GiftTrayTestModeRegistry.shared.forget(id)
        } else {
            DispatchQueue.main.async {
                GiftTrayTestModeRegistry.shared.forget(id)
            }
        }
    }

    public var gifts: [Gift] { state.gifts }
    public var balance: Int { state.balance }
    /// The token was made with a test key. `GiftTray` shows its "Test mode" badge from this by itself
    /// (its `testMode` is nil by default); you only need it to show your own marker.
    public var testMode: Bool { state.testMode }
    public var user: String? { state.user }
    public var loading: Bool { state.loading }
    public var error: GiftingError? { state.error }

    /// Shows the tray (the sheet comes back at its `initialSnap`). With a bound text field it takes the focus away
    /// first, so the keyboard and the tray are never up together. Returns the new state.
    @discardableResult
    public func open() -> Bool {
        openTouched = true
        if !openState.isOpen, let setFocus = setInputFocus {
            setFocus(false)
        }
        return openState.open()
    }

    /// Hides the tray. Never moves the focus. Returns the new state.
    @discardableResult
    public func close() -> Bool {
        openTouched = true
        return openState.close()
    }

    /// Open if closed, close if open: the host's Gift button is `tray.toggle()` (or `GiftButton(tray: tray)`).
    /// With a bound text field this is the keyboard swap of spec 20: closed, the field loses its focus and then
    /// the tray opens in the keyboard's place; open, the tray closes and then the field gets its focus back.
    /// Returns the new state.
    @discardableResult
    public func toggle() -> Bool {
        openTouched = true
        guard let setFocus = setInputFocus else {
            return openState.toggle()
        }
        return runSwapStep(inputSwapStep(open: openState.isOpen, event: .button), setFocus: setFocus)
    }

    // MARK: - The bound text field (spec 20)

    /// Binds a text field: `setFocus(false)` blurs it, `setFocus(true)` focuses it. The first binding closes a tray
    /// that was not given `open:` and was not opened or closed yet (it starts closed). Returns the token for
    /// `unbindInput`. Used by `.giftTrayInput`.
    @discardableResult
    func bindInput(setFocus: @escaping (Bool) -> Void) -> Int {
        inputToken += 1
        setInputFocus = setFocus
        if !inputBound {
            inputBound = true
        }
        if !openGiven, !openTouched, openState.isOpen {
            openTouched = true
            // The first state, not a change the host asked for: no `onOpenChange`.
            let onChange = openState.onChange
            openState.onChange = nil
            openState.close()
            openState.onChange = onChange
        }
        return inputToken
    }

    /// Ends the binding made with `token` (a later binding is kept).
    func unbindInput(_ token: Int) {
        guard token == inputToken, setInputFocus != nil else {
            return
        }
        setInputFocus = nil
        inputBound = false
    }

    /// The bound field got focus (a tap on it, or the app focused it): an open tray closes; the focus stays.
    func inputFocused() {
        guard setInputFocus != nil else {
            return
        }
        _ = runSwapStep(inputSwapStep(open: openState.isOpen, event: .inputFocus), setFocus: nil)
    }

    /// Keeps a keyboard height of at least `keyboardMinHeight` (a smaller inset is not a keyboard).
    func recordKeyboardHeight(_ height: Double) {
        guard height.isFinite, height >= keyboardMinHeight, height != keyboardHeight else {
            return
        }
        keyboardHeight = height
    }

    /// Blur BEFORE open; close BEFORE focus (spec 20.2).
    private func runSwapStep(_ step: InputSwapStep, setFocus: ((Bool) -> Void)?) -> Bool {
        if step.input == .blur {
            setFocus?(false)
        }
        switch step.tray {
        case .open:
            openState.open()
        case .close:
            openState.close()
        case .keep:
            break
        }
        if step.input == .focus {
            setFocus?(true)
        }
        return openState.isOpen
    }

    /// The screen is on: attach and load the catalog and the balance.
    public func start() {
        controller.attach()
        GiftTrayTestModeRegistry.shared.report(ObjectIdentifier(self), testMode: state.testMode)
        refresh()
    }

    /// The screen is gone: late answers change nothing.
    public func stop() {
        controller.dispose()
        GiftTrayTestModeRegistry.shared.forget(ObjectIdentifier(self))
    }

    /// Reloads the catalog and the balance (do not wait).
    public func refresh() {
        let controller = self.controller
        Task {
            await controller.refresh()
        }
    }

    /// Sends a gift (do not wait). Tap again for a combo.
    public func send(_ gift: Gift) {
        // The side is taken at the tap: a pick made while the send runs is for the next gift.
        let target = receivers.isEmpty ? nil : receiver
        let controller = self.controller
        Task { [weak self] in
            let sent = await controller.send(gift, to: target)
            self?.sendSettled(sent, target: target)
        }
    }

    /// Reloads and waits until it settled.
    public func refreshAndWait() async {
        await controller.refresh()
    }

    /// Sends and waits until the send settled (the reconcile `getMe` may still be running).
    public func sendAndWait(_ gift: Gift) async {
        let target = receivers.isEmpty ? nil : receiver
        let sent = await controller.send(gift, to: target)
        sendSettled(sent, target: target)
    }

    // MARK: - The receiver picker (spec 21)

    /// Picks the side the next gift goes to (a tap in the "Send to" row does the same). An id that is not in
    /// `receivers` is ignored. Open the tray after it for "tap a side of the battle bar":
    /// `tray.selectReceiver(id); tray.open()`.
    public func selectReceiver(_ id: String) {
        guard receivers.contains(where: { $0.id == id }) else {
            return
        }
        let before = receiver
        if selectedReceiver != id {
            selectedReceiver = id
        }
        if receiver != before {
            onReceiverChange?(receiver)
        }
    }

    /// A successful send to a side makes it the default of the next list (`last`).
    private func sendSettled(_ sent: Bool, target: String?) {
        guard sent, let target = target, lastReceiver != target else {
            return
        }
        lastReceiver = target
    }

    /// A new list: a pick that left it is dropped (so the next round starts at the side gifted last, else the
    /// first); `onReceiverChange` when the side the next gift goes to is another one now.
    private func receiversChanged(from old: [TrayReceiver]) {
        let before = resolveReceiver(
            ids: old.map { $0.id },
            selected: selectedReceiver,
            last: lastReceiver,
            fallback: controller.receiver
        ) ?? controller.receiver
        if let picked = selectedReceiver, !receivers.contains(where: { $0.id == picked }) {
            selectedReceiver = nil
        }
        let after = receiver
        if !receivers.isEmpty, after != before {
            onReceiverChange?(after)
        }
    }
}

/// Records the keyboard's height from `keyboardWillChangeFrameNotification` (iOS; nothing elsewhere). The
/// observer goes away with this object.
final class KeyboardHeightObserver {
    private var token: NSObjectProtocol?

    init(onHeight: @escaping @MainActor @Sendable (Double) -> Void) {
        #if canImport(UIKit) && !os(watchOS)
        token = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
                return
            }
            Task { @MainActor in
                // The part of the end frame that is on screen: 0 when the keyboard goes down.
                let screen = UIScreen.main.bounds
                let visible = max(0, min(frame.height, screen.maxY - frame.minY))
                onHeight(Double(visible))
            }
        }
        #endif
    }

    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
private final class WeakEffects {
    weak var value: GiftEffectController?
}
#endif
