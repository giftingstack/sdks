#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI

/// The SwiftUI state holder of a "while you were away" card: an `AwayController` (spec 15.4)
/// that publishes its state, looks up display names, and decides when the card is on screen.
///
/// ```swift
/// @StateObject var away = GiftAwayModel(client: client, effects: effects)
/// ...
/// ZStack { content; GiftAwaySummary(model: away); GiftEffectLayer(controller: effects) }
/// ```
@MainActor
public final class GiftAwayModel: ObservableObject {
    @Published public private(set) var state: AwayState
    /// The summary whose card is on screen, else nil.
    @Published public private(set) var card: AwaySummary?
    /// Grows each time a card appears or goes (drives the card's transition).
    @Published public private(set) var cardVersion = 0
    /// Display names looked up so far.
    @Published public private(set) var names: [String: GiftUserInfo] = [:]

    /// The pure controller underneath. Its settings may be changed at any time.
    public let controller: AwayController
    /// Names (and pictures) for the ids. Fallback: the id.
    public var resolveUsers: GiftResolveUsers?
    /// `check()` when the card view appears and `foreground()` when the app becomes active.
    public var autoCheck: Bool
    /// nil (default): follows the system Reduce Motion setting. Reduced motion: no replay, no
    /// slide-in.
    public var reducedMotion: Bool?
    public var labels: GiftLabels {
        didSet {
            controller.labels = AwaySenderLabels(someone: labels.someone)
        }
    }
    public var onError: ((GiftingError) -> Void)? {
        didSet {
            controller.onError = onError
        }
    }

    /// The effect layer that replays the gifts. Held weakly. nil: card only.
    public var effects: GiftEffectController? {
        get { effectsBox.value }
        set { effectsBox.value = newValue }
    }

    private let effectsBox: AwayWeakEffects
    private var presenting = false
    private var unsubscribe: (() -> Void)?

    /// - Parameters:
    ///   - ackOn: `.shown` (default), `.finished` or `.manual` (call `ack()`).
    ///   - maxEffects: gift groups replayed at most. Default 5.
    ///   - budgetMs: the replay ends by then. Default 8000.
    ///   - thresholds, quality: as the effect layer's (nil: the defaults).
    public init(
        client: any GiftAwayAPI,
        effects: GiftEffectController? = nil,
        resolveUsers: GiftResolveUsers? = nil,
        autoCheck: Bool = true,
        ackOn: AwayAckOn = .shown,
        maxEffects: Int = defaultAwayMaxEffects,
        budgetMs: Int = defaultAwayBudgetMs,
        thresholds: TierThresholds? = nil,
        quality: EffectQuality = .high,
        reducedMotion: Bool? = nil,
        labels: GiftLabels = GiftLabels(),
        onShow: ((AwaySummary) -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil
    ) {
        let box = AwayWeakEffects()
        box.value = effects
        self.effectsBox = box
        self.resolveUsers = resolveUsers
        self.autoCheck = autoCheck
        self.reducedMotion = reducedMotion
        self.labels = labels
        self.onError = onError
        let controller = AwayController(
            client: client,
            effects: { box.value },
            ackOn: ackOn,
            maxEffects: maxEffects,
            budgetMs: budgetMs,
            thresholds: thresholds,
            quality: quality,
            labels: AwaySenderLabels(someone: labels.someone),
            onShow: onShow,
            onDone: onDone,
            onError: onError
        )
        self.controller = controller
        self.state = controller.state
        controller.reducedMotion = { [weak self] in
            self?.motionOff ?? false
        }
        controller.resolveName = { [weak self] id in
            self?.names[id]?.name ?? id
        }
        unsubscribe = controller.subscribe { [weak self] next in
            self?.onState(next)
        }
    }

    /// Reduced motion now: the override, else the system setting.
    public var motionOff: Bool {
        reducedMotion ?? systemReduceMotion()
    }

    /// The display name of a sender id (nil: a deleted sender).
    public func name(of id: String?) -> String {
        guard let id = id else {
            return labels.someone
        }
        return names[id]?.name ?? id
    }

    /// Ask the server what arrived (ignored while a card is showing). Do not wait.
    public func check() {
        let controller = self.controller
        Task {
            await controller.check()
        }
    }

    /// The app came back to the foreground: check unless one ran less than a minute ago.
    public func foreground() {
        let controller = self.controller
        Task {
            await controller.foreground()
        }
    }

    /// Close the card now.
    public func dismiss() {
        controller.dismiss()
    }

    /// `ackOn: .manual`: mark the summary on screen as seen.
    public func ack() {
        controller.ack()
    }

    /// The screen is gone for good: timers stop, late answers change nothing.
    public func dispose() {
        controller.dispose()
    }

    // MARK: - State to card

    private func onState(_ next: AwayState) {
        state = next
        switch next.status {
        case .ready:
            if let summary = next.summary, !presenting {
                presenting = true
                present(summary)
            }
        case .done, .idle, .empty:
            presenting = false
            if card != nil {
                card = nil
                cardVersion += 1
            }
        case .loading, .playing:
            break
        }
    }

    /// Names first (briefly), then the card, then the replay.
    private func present(_ summary: AwaySummary) {
        var wanted: [String] = []
        for group in summary.groups {
            for sender in group.senders {
                if let id = sender.user {
                    wanted.append(id)
                }
            }
        }
        for sender in summary.topSenders {
            if let id = sender.user {
                wanted.append(id)
            }
        }
        var missing: [String] = []
        for id in wanted where names[id] == nil && !missing.contains(id) {
            missing.append(id)
        }
        let resolve = resolveUsers
        let ids = missing
        Task { [weak self] in
            if let resolve = resolve, !ids.isEmpty {
                let found = await resolveUsersWithin(ids, waitMs: 1_500, resolve: resolve, onError: self?.onError)
                if let found = found, let self = self {
                    var merged = self.names
                    for (id, info) in found {
                        merged[id] = info
                    }
                    self.names = merged
                }
            }
            // Still this summary, still ready? (The screen may have gone, or the person left.)
            guard let self = self, self.controller.state.status == .ready else {
                return
            }
            self.card = summary
            self.cardVersion += 1
            self.controller.start()
            let labels = self.labels
            let gifts = awayCountText(summary.totalGifts, one: labels.giftOne, other: labels.giftOther, truncated: summary.truncated)
            let people = awayCountText(summary.senderCount, one: labels.personOne, other: labels.personOther, truncated: summary.truncated)
            let text = fillLabel(labels.awaySummary, ["gifts": gifts, "people": people])
            announceForAccessibility(fillLabel(labels.awayAnnounce, ["summary": text]))
        }
    }
}

@MainActor
private final class AwayWeakEffects {
    weak var value: GiftEffectController?
}
#endif
