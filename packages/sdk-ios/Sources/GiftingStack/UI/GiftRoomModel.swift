#if canImport(SwiftUI)
import Combine
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Keeps a screen in a gift room (SPEC 18): every gift sent into the room by someone else plays
/// in `effects`. A `RoomClient` with the real socket (`URLSessionRoomSocket`, protocol pings)
/// that publishes its state. The socket closes when the app goes to the background (an
/// `inactive` app, for example with Control Center open, keeps it) and reconnects, with resume,
/// when the app comes back. Send into the room with `GiftTrayModel(..., roomId:)`.
///
/// ```swift
/// @StateObject var effects = GiftEffectController()
/// @StateObject var room = GiftRoomModel(room: "live_123", getToken: getToken, client: client)
/// ...
/// content
///     .onAppear { room.effects = effects; room.join() }
///     .onDisappear { room.pause() }
/// ```
@MainActor
public final class GiftRoomModel: ObservableObject {
    @Published public private(set) var state: RoomState

    /// Approximate viewer count, nil before the first `welcome`.
    public var viewers: Int? { state.viewers }

    /// The room's battle round (SPEC 18.6), nil when there is none. Published: a view updates on
    /// every `scores` frame. Headless: draw your own bar from `battleView()`.
    @Published public private(set) var battle: RoomBattle?

    /// The session underneath. Its filter settings (`skipOwn`, `minTier`, ...) and
    /// `resolveName` may be changed at any time.
    public let controller: RoomClient

    /// The effect layer room gifts play in. Held weakly.
    public var effects: GiftEffectController? {
        get { effectsBox.value }
        set { effectsBox.value = newValue }
    }

    /// Every gift that passed the filters, after it was given to `effects`.
    public var onEvent: ((RoomGiftEvent) -> Void)?
    /// `welcome.gap`: gifts may have been missed while away. Nothing to fetch; for logs.
    public var onGap: (() -> Void)?
    /// Battle scores changed: a new snapshot, or nil when the round was removed.
    public var onBattle: ((RoomBattle?) -> Void)?
    /// Default true: close in the background, reconnect in the foreground.
    public let pauseInBackground: Bool

    private let client: (any GiftingAPI)?
    private let effectsBox: RoomWeakEffects
    private var catalog: [Gift]?
    private var catalogRequested = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// The background closed the socket (not the app's own `pause()`).
    private var pausedByBackground = false
    private var unsubscribe: (() -> Void)?

    /// - Parameters:
    ///   - room: room id, `^[A-Za-z0-9_.:-]{1,64}$` (your stream, audio room or chat id).
    ///   - getToken: the same token function you give `GiftingClient`. Your server mints the
    ///     token with `rooms` (allowed room ids or `prefix*`) and `name` (the name viewers see).
    ///   - client: loads the catalog once so room gifts show the big picture, not only the icon.
    ///   - user: the signed-in user, for own-skip. nil: the token's `u` claim.
    ///   - skipOwn: default true: your own gifts already played on tap.
    ///   - maxReplayAgeMs: default 10,000: older gifts (after a reconnect) are dropped.
    ///   - minTier: only gifts of this tier or bigger. Default `.small` (all).
    ///   - resolveName: display name of a sender whose token has no `name`; also the name of the
    ///     receiver in a battle gift notice.
    ///   - sideColors: the border colours of the two battle sides in the gift notice (SPEC 7.4): pass
    ///     the same pair as `GiftBattleBar(sideColors:)`. nil: the theme's accent and coin colour.
    ///   - url: default `wss://rt.giftingstack.com`.
    ///   - allowInsecure: lets a plain `ws://` url to a host that is not on this device through (default
    ///     false: only `wss://` and localhost, 127.0.0.1, ::1, 10.0.2.2). Another `ws://` url stops the app
    ///     with a `precondition` failure when the model is created (SPEC 3.1).
    ///   - socket: for tests. Default: `urlSessionRoomSocketFactory(allowInsecure:)`.
    ///   - clock: for tests. Default: the system clock.
    public init(
        room: String,
        getToken: @escaping GiftingTokenProvider,
        client: (any GiftingAPI)? = nil,
        effects: GiftEffectController? = nil,
        user: String? = nil,
        skipOwn: Bool = true,
        maxReplayAgeMs: Int = defaultRoomMaxReplayAgeMs,
        minTier: EffectTier = .small,
        thresholds: TierThresholds = TierThresholds(),
        resolveName: ((String) -> String?)? = nil,
        sideColors: [String]? = nil,
        url: String? = nil,
        pauseInBackground: Bool = true,
        onEvent: ((RoomGiftEvent) -> Void)? = nil,
        onGap: (() -> Void)? = nil,
        onBattle: ((RoomBattle?) -> Void)? = nil,
        socket: RoomSocketFactory? = nil,
        clock: (any GiftClock)? = nil,
        allowInsecure: Bool = false
    ) {
        let box = RoomWeakEffects()
        box.value = effects
        self.effectsBox = box
        self.client = client
        self.onEvent = onEvent
        self.onGap = onGap
        self.onBattle = onBattle
        self.pauseInBackground = pauseInBackground
        let factory: RoomSocketFactory
        if let socket = socket {
            factory = socket
        } else {
            factory = urlSessionRoomSocketFactory(allowInsecure: allowInsecure)
        }
        let controller = RoomClient(
            room: room,
            getToken: getToken,
            socket: factory,
            url: url,
            user: user,
            skipOwn: skipOwn,
            maxReplayAgeMs: maxReplayAgeMs,
            minTier: minTier,
            thresholds: thresholds,
            resolveName: resolveName,
            sideColors: sideColors,
            // URLSessionRoomSocket sends protocol pings: no `ping` text.
            heartbeatMs: 0,
            refreshJitterMs: roomRefreshJitterMs,
            clock: clock,
            allowInsecure: allowInsecure
        )
        self.controller = controller
        self.state = controller.state
        controller.getCatalog = { [weak self] in
            self?.catalog
        }
        controller.onEvent = { [weak self] event in
            self?.received(event)
        }
        controller.onGap = { [weak self] in
            self?.onGap?()
        }
        controller.onBattle = { [weak self] next in
            self?.battle = next
            self?.onBattle?(next)
        }
        unsubscribe = controller.subscribe { [weak self] next in
            self?.state = next
        }
    }

    /// The battle side `user` is on now (SPEC 18.4): pass it to the tray as `receiverOf: room.receiverFor` so
    /// your own gift says who got it too. nil outside a round.
    public func receiverFor(_ user: String) -> GiftEffectReceiver? {
        controller.receiverFor(user)
    }

    /// `battleView` of the current round at the server's time now, nil without a round. Call it
    /// again on a timer while the round is open to count down (it reads the clock).
    public func battleView() -> BattleView? {
        controller.battleView()
    }

    /// Joins the room (or reconnects after `pause()`), loads the catalog once and starts
    /// following the app's background/foreground changes. Safe to call again.
    public func join() {
        observeLifecycle()
        loadCatalog()
        pausedByBackground = false
        if controller.state.status == .idle {
            controller.start()
        } else {
            controller.resume()
        }
    }

    /// Closes the socket but keeps the resume point; `join()` reconnects. For a screen that
    /// went off (`onDisappear`).
    public func pause() {
        pausedByBackground = false
        controller.pause()
    }

    /// Leaves for good (closes the socket, stops following the app lifecycle). Safe to call twice.
    public func leave() {
        stopObservingLifecycle()
        controller.leave()
    }

    /// The network is back (or the user asked): skip a pending backoff wait, or start again after
    /// the room stopped with the reason `retries_exhausted` or the code 4011 (SPEC 18.3).
    public func reconnectNow() {
        controller.reconnectNow()
    }

    // MARK: - App lifecycle

    /// The app went to the background: close, keep the resume point.
    public func appDidEnterBackground() {
        let s = controller.state.status
        if s == .connecting || s == .open || s == .reconnecting {
            pausedByBackground = true
            controller.pause()
        }
    }

    /// The app is back: reconnect with resume when the background closed the socket.
    public func appWillEnterForeground() {
        if pausedByBackground {
            pausedByBackground = false
            controller.resume()
        }
        controller.reconnectNow()
    }

    /// For apps that drive the lifecycle from SwiftUI (`.onChange(of: scenePhase)`) with
    /// `pauseInBackground: false`: `.background` pauses, `.active` resumes, `.inactive` keeps
    /// the socket.
    public func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            appDidEnterBackground()
        case .active:
            appWillEnterForeground()
        default:
            break
        }
    }

    private func observeLifecycle() {
        if !pauseInBackground || !lifecycleObservers.isEmpty {
            return
        }
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                let model = self
                Task { @MainActor in
                    model?.appDidEnterBackground()
                }
            }
        )
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                let model = self
                Task { @MainActor in
                    model?.appWillEnterForeground()
                }
            }
        )
        #endif
    }

    private func stopObservingLifecycle() {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers = []
    }

    // MARK: - Events

    private func loadCatalog() {
        guard let client = client, !catalogRequested else {
            return
        }
        catalogRequested = true
        Task { [weak self] in
            do {
                let gifts = try await client.getGifts()
                self?.catalog = gifts
            } catch {
                // Only the icon then: the event carries it.
            }
        }
    }

    private func received(_ event: RoomGiftEvent) {
        effects?.play(event.effectEvent)
        onEvent?(event)
    }
}

@MainActor
private final class RoomWeakEffects {
    weak var value: GiftEffectController?
}
#endif
