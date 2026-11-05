#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI

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
    /// unless you passed `open: false`; the host's Gift button is `tray.toggle()`.
    @Published public private(set) var isOpen: Bool

    /// The pure state holder underneath. Its settings (`client`, `receiver`, `playOn`,
    /// `reference`, `roomId`, `onSent`, `onError`) may be changed at any time.
    public let controller: GiftTrayController

    /// The effect layer that shows each local send. Held weakly.
    public var effects: GiftEffectController? {
        get { effectsBox.value }
        set { effectsBox.value = newValue }
    }

    private let effectsBox: WeakEffects
    private var unsubscribe: (() -> Void)?
    private let openState: TrayOpenState
    private var unsubscribeOpen: (() -> Void)?

    public init(
        client: any GiftingAPI,
        receiver: String,
        effects: GiftEffectController? = nil,
        playOn: PlayOn = .tap,
        reference: String? = nil,
        roomId: String? = nil,
        onSent: ((GiftTransaction) -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil,
        open: Bool = true,
        onOpenChange: ((Bool) -> Void)? = nil
    ) {
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
            onSent: onSent,
            onError: onError,
            prefetch: { url in
                GiftImageCache.shared.prefetch(url)
            }
        )
        self.controller = controller
        self.state = controller.state
        let openState = TrayOpenState(open: open, onChange: onOpenChange)
        self.openState = openState
        self.isOpen = open
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

    /// Shows the tray (the sheet comes back at its `initialSnap`). Returns the new state.
    @discardableResult
    public func open() -> Bool {
        openState.open()
    }

    /// Hides the tray. Returns the new state.
    @discardableResult
    public func close() -> Bool {
        openState.close()
    }

    /// Open if closed, close if open: the host's Gift button is `tray.toggle()`. Returns the new state.
    @discardableResult
    public func toggle() -> Bool {
        openState.toggle()
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
        let controller = self.controller
        Task {
            await controller.send(gift)
        }
    }

    /// Reloads and waits until it settled.
    public func refreshAndWait() async {
        await controller.refresh()
    }

    /// Sends and waits until the send settled (the reconcile `getMe` may still be running).
    public func sendAndWait(_ gift: Gift) async {
        await controller.send(gift)
    }
}

@MainActor
private final class WeakEffects {
    weak var value: GiftEffectController?
}
#endif
