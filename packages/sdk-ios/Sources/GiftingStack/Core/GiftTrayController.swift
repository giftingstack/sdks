import Foundation

/// The part of an effect layer the tray needs. `GiftEffectController` implements it.
@MainActor
public protocol EffectPlayer: AnyObject {
    func play(_ event: GiftEffectEvent) -> Int
    func cancel(_ id: Int)
}

/// When the tray plays the effect of a local send.
public enum PlayOn: String, Sendable, Hashable {
    /// Default: at the tap (feels instant), taken back if the send fails.
    case tap
    /// After the server accepted the send (a round trip later, never shown for a failed send).
    case success
}

public struct GiftTrayState: Sendable, Equatable {
    public var gifts: [Gift] = []
    public var balance: Int = 0
    /// The signed-in user, as named by the token.
    public var user: String?
    /// True until the first `refresh()` settles. Never becomes true again.
    public var loading: Bool = true
    /// The last problem: loading failed, or the last send failed. Cleared by the next success.
    public var error: GiftingError?
    /// The server said the token is a test token (`me.livemode == false`): show "Test mode".
    public var testMode: Bool = false

    public init(
        gifts: [Gift] = [],
        balance: Int = 0,
        user: String? = nil,
        loading: Bool = true,
        error: GiftingError? = nil,
        testMode: Bool = false
    ) {
        self.gifts = gifts
        self.balance = balance
        self.user = user
        self.loading = loading
        self.error = error
        self.testMode = testMode
    }
}

/// Everything a gift tray does besides drawing (spec section 8): loads the catalog and the
/// balance, sends gifts with an optimistic balance and plays their effects. Ported line by line
/// from `packages/sdk-js/src/core/tray.ts`. SwiftUI apps use `GiftTrayModel`, which wraps it.
///
/// Settings are plain properties, read again at every use, so they may change at any time.
@MainActor
public final class GiftTrayController {
    public var client: any GiftingAPI
    /// Who gets the gifts: the owner of the post or profile on screen.
    public var receiver: String
    /// Returns the effect layer that shows each gift, if there is one right now.
    public var effects: (() -> (any EffectPlayer)?)?
    public var playOn: PlayOn
    /// Your own context id, for example the post id. Saved with each gift.
    public var reference: String?
    /// Room on screen (SPEC 17.1): every send names it, so the room's viewers see the gift.
    public var roomId: String?
    /// In a battle, the side a receiver is on (`room.receiverFor`, SPEC 18.4): the user's own gift then says
    /// who got it, like the room's gifts of the others. nil outside a battle.
    public var receiverOf: ((String) -> GiftEffectReceiver?)?
    public var onSent: ((GiftTransaction) -> Void)?
    public var onError: ((GiftingError) -> Void)?
    /// Starts downloading a picture. Called for every `iconUrl` once the catalog loads (not the big pictures, SPEC 8 step 2).
    public var prefetch: ((String) -> Void)?

    public private(set) var state = GiftTrayState() {
        didSet {
            for entry in observers {
                entry.callback(state)
            }
        }
    }

    private var observers: [(token: Int, callback: (GiftTrayState) -> Void)] = []
    private var nextObserverToken = 0
    /// Sends that have not finished yet.
    private var pending = 0
    private var alive = true

    public init(
        client: any GiftingAPI,
        receiver: String,
        effects: (() -> (any EffectPlayer)?)? = nil,
        playOn: PlayOn = .tap,
        reference: String? = nil,
        roomId: String? = nil,
        receiverOf: ((String) -> GiftEffectReceiver?)? = nil,
        onSent: ((GiftTransaction) -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil,
        prefetch: ((String) -> Void)? = nil
    ) {
        self.client = client
        self.receiver = receiver
        self.effects = effects
        self.playOn = playOn
        self.reference = reference
        self.roomId = roomId
        self.receiverOf = receiverOf
        self.onSent = onSent
        self.onError = onError
        self.prefetch = prefetch
    }

    /// Calls `observer` after every state change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ observer: @escaping (GiftTrayState) -> Void) -> () -> Void {
        let token = nextObserverToken
        nextObserverToken += 1
        observers.append((token: token, callback: observer))
        return { [weak self] in
            self?.observers.removeAll { $0.token == token }
        }
    }

    /// The screen is (back) on.
    public func attach() {
        alive = true
    }

    /// The screen is gone: answers that arrive later change nothing.
    public func dispose() {
        alive = false
    }

    /// Reloads the catalog and the balance, for example after the person buys coins.
    public func refresh() async {
        let client = self.client
        do {
            let (list, me) = try await loadCatalogAndMe(client)
            if alive {
                // Download the small icons now, in the server's order (SPEC 8 step 2). The big picture of the
                // selected gift is the tray's job; the others load when they first play.
                for gift in list {
                    if let url = gift.iconUrl {
                        prefetch?(url)
                    }
                }
                var next = state
                next.gifts = GiftTrayController.sortedBySortOrder(list)
                next.balance = me.balance
                next.user = me.user
                next.error = nil
                next.testMode = me.livemode == false
                state = next
            }
        } catch {
            if alive {
                state.error = asGiftingError(error)
            }
        }
        if alive {
            state.loading = false
        }
    }

    /// Sends a gift. The coins leave the balance at once; a failure gives them back.
    public func send(_ gift: Gift) async {
        let client = self.client
        let receiver = self.receiver
        let reference = self.reference
        // An empty room id names no room (the reference sends it only when given).
        let roomId = (self.roomId?.isEmpty ?? true) ? nil : self.roomId
        let effects = self.effects
        let user = state.user
        let early = playOn == .tap
        pending += 1
        // Take the coins at once so the number moves with every tap.
        state.balance = state.balance - gift.price

        var shownId: Int?
        if early {
            shownId = effects?()?.play(GiftEffectEvent(gift: gift, sender: user ?? "You", quantity: 1, receiver: receiverOf?(receiver)))
        }
        do {
            let tx = try await client.sendGift(SendGiftInput(receiver: receiver, giftId: gift.id, reference: reference, roomId: roomId))
            if alive {
                state.error = nil
                if !early {
                    _ = effects?()?.play(GiftEffectEvent(gift: gift, sender: user ?? tx.sender, quantity: tx.quantity, receiver: receiverOf?(receiver)))
                }
                onSent?(tx)
            }
        } catch {
            let e = asGiftingError(error)
            // The gift was shown before the server answered: take it back.
            if let id = shownId {
                effects?()?.cancel(id)
            }
            if alive {
                var next = state
                next.balance = next.balance + gift.price
                next.error = e
                state = next
            }
            onError?(e)
        }
        pending -= 1
        if pending == 0 {
            Task { [weak self] in
                await self?.reconcile(client)
            }
        }
    }

    /// After a burst of taps the server's number is the truth.
    private func reconcile(_ client: any GiftingAPI) async {
        do {
            let me = try await client.getMe()
            if alive && pending == 0 {
                state.balance = me.balance
            }
        } catch {
            // The optimistic number stays; the next send or refresh corrects it.
        }
    }

    /// `getGifts()` and `getMe()` at the same time, in that order; the first failure fails both
    /// (like `Promise.all`).
    private func loadCatalogAndMe(_ client: any GiftingAPI) async throws -> ([Gift], Me) {
        let join = CatalogJoin()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<([Gift], Me), Error>) in
            join.continuation = continuation
            Task { @MainActor in
                do {
                    join.gifts = try await client.getGifts()
                    join.settleIfDone()
                } catch {
                    join.fail(error)
                }
            }
            Task { @MainActor in
                do {
                    join.me = try await client.getMe()
                    join.settleIfDone()
                } catch {
                    join.fail(error)
                }
            }
        }
    }

    /// Stable sort by `sortOrder`, ascending.
    static func sortedBySortOrder(_ gifts: [Gift]) -> [Gift] {
        let indexed = Array(gifts.enumerated())
        let sorted = indexed.sorted { a, b in
            if a.element.sortOrder != b.element.sortOrder {
                return a.element.sortOrder < b.element.sortOrder
            }
            return a.offset < b.offset
        }
        return sorted.map { $0.element }
    }
}

/// Collects the two answers of `refresh()` and resumes its continuation exactly once.
@MainActor
private final class CatalogJoin {
    var continuation: CheckedContinuation<([Gift], Me), Error>?
    var gifts: [Gift]?
    var me: Me?

    func settleIfDone() {
        guard let gifts = gifts, let me = me, let continuation = continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: (gifts, me))
    }

    func fail(_ error: Error) {
        guard let continuation = continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

// MARK: - Send button (spec 8.1)

public enum SendButtonLabel: String, Sendable, Hashable {
    case send
    case getCoins
    case notEnough
}

public enum SendButtonAction: String, Sendable, Hashable {
    case send
    case topUp
    /// The spec's `"none"` (named so it never reads as `Optional.none`).
    case noAction = "none"
}

public struct SendButtonState: Sendable, Equatable {
    /// The gift the tray shows as selected, or nil for an empty tray.
    public var selectedId: String?
    /// The selected gift costs more than the balance.
    public var broke: Bool
    public var label: SendButtonLabel
    public var pressable: Bool
    /// What a press does.
    public var action: SendButtonAction
}

/// The tray's Send button. The selected gift is the one with `selectedId`, else the first one.
/// Too expensive: "Get coins" (opens the store) when `canTopUp`, else "Not enough coins" (off).
public func sendButtonState(
    gifts: [Gift],
    selectedId: String?,
    balance: Int,
    disabled: Bool = false,
    canTopUp: Bool = false
) -> SendButtonState {
    let selected = gifts.first(where: { $0.id == selectedId }) ?? gifts.first
    let broke = selected.map { $0.price > balance } ?? false
    let canSend = selected != nil && !disabled && !broke
    let label: SendButtonLabel = broke ? (canTopUp ? .getCoins : .notEnough) : .send
    let pressable = canSend || (broke && canTopUp && !disabled)
    let action: SendButtonAction = !pressable ? .noAction : (broke ? .topUp : .send)
    return SendButtonState(
        selectedId: selected?.id,
        broke: broke,
        label: label,
        pressable: pressable,
        action: action
    )
}

/// Numbers as the reference shows them: en-US grouping (`1,234`) whatever the device locale.
public func formatCoins(_ value: Int) -> String {
    let digits = String(value.magnitude)
    var out = ""
    for (index, ch) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 {
            out.append(",")
        }
        out.append(ch)
    }
    return value < 0 ? "-" + out : out
}
