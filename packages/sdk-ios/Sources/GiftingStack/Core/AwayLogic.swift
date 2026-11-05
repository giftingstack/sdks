import Foundation

// "While you were away" (spec section 15): the replay plan for the effect layer and the
// controller behind the summary card. Ported from `packages/sdk-js/src/core/away.ts`. No drawing;
// the clock and the timers are injected.

/// Gift groups replayed at most.
public let defaultAwayMaxEffects = 5
/// The replay must have ended by then (ms after the card appears).
public let defaultAwayBudgetMs = 8_000
/// Start gap after a small effect.
public let awayGapAfterSmallMs = 450
/// Start gap after a medium effect (keeps medium at <= 2 at once).
public let awayGapAfterMediumMs = 1_100
/// The large effect starts this long after every earlier effect has ended.
public let awayLargePauseMs = 300
/// The card stays at least this long, and this long after the last effect ends.
public let awayCardMinMs = 4_000
public let awayCardTailMs = 1_500
/// `foreground()` checks again at most this often.
public let awayForegroundThrottleMs = 60_000

/// How long one effect runs (spec 7.3): `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`
/// with `tail = holdMs + flyOutMs`. Small 1600, medium 2100, large 3850 (3050 at low quality).
public func effectDurationMs(_ recipe: EffectRecipe) -> Int {
    let tail = recipe.holdMs + recipe.flyOutMs
    let coinsTail = recipe.coins > 0 ? tail + 800 : 0
    return recipe.flyInMs + max(900, max(tail, coinsTail))
}

/// Words of `awaySenderLabel`. `{a}`, `{b}` and `{n}` mark where the values go.
public struct AwaySenderLabels: Sendable, Equatable, Hashable {
    /// A deleted sender. Default `"Someone"`.
    public var someone: String
    /// Two people. Default `"{a} and {b}"`.
    public var pair: String
    /// One named person and one more. Default `"{a} and 1 other"`.
    public var oneOther: String
    /// One named person and `{n}` more. Default `"{a} and {n} others"`.
    public var others: String

    public init(
        someone: String = "Someone",
        pair: String = "{a} and {b}",
        oneOther: String = "{a} and 1 other",
        others: String = "{a} and {n} others"
    ) {
        self.someone = someone
        self.pair = pair
        self.oneOther = oneOther
        self.others = others
    }
}

/// `text` with the FIRST `target` replaced (JavaScript's `String.prototype.replace` with a string).
func replacingFirst(_ text: String, _ target: String, with value: String) -> String {
    guard let range = text.range(of: target) else {
        return text
    }
    return text.replacingCharacters(in: range, with: value)
}

/// Who sent a group, for the effect's notice (spec 15.2). `names` are display names in the
/// server's order (a deleted sender already turned into `labels.someone`), `senderCount` the
/// number of distinct people.
public func awaySenderLabel(_ names: [String], senderCount: Int, labels: AwaySenderLabels = AwaySenderLabels()) -> String {
    let a = names.first ?? labels.someone
    if senderCount <= 1 {
        return a
    }
    if senderCount == 2 && names.count >= 2 {
        return replacingFirst(replacingFirst(labels.pair, "{a}", with: a), "{b}", with: names[1])
    }
    let n = senderCount - 1
    if n == 1 {
        return replacingFirst(labels.oneOther, "{a}", with: a)
    }
    return replacingFirst(replacingFirst(labels.others, "{a}", with: a), "{n}", with: String(n))
}

/// Settings of `planAwayReplay`.
public struct AwayReplayOptions {
    public var maxEffects: Int
    public var budgetMs: Int
    /// nil: the default thresholds (100 / 10,000).
    public var thresholds: TierThresholds?
    public var quality: EffectQuality
    /// Or no effect layer: the plan is empty and only the card shows.
    public var reducedMotion: Bool
    /// Display name of a sender id. nil: the id itself. Deleted senders are always `labels.someone`.
    public var resolveName: ((String) -> String)?
    public var labels: AwaySenderLabels

    public init(
        maxEffects: Int = defaultAwayMaxEffects,
        budgetMs: Int = defaultAwayBudgetMs,
        thresholds: TierThresholds? = nil,
        quality: EffectQuality = .high,
        reducedMotion: Bool = false,
        resolveName: ((String) -> String)? = nil,
        labels: AwaySenderLabels = AwaySenderLabels()
    ) {
        self.maxEffects = maxEffects
        self.budgetMs = budgetMs
        self.thresholds = thresholds
        self.quality = quality
        self.reducedMotion = reducedMotion
        self.resolveName = resolveName
        self.labels = labels
    }
}

/// One planned play.
public struct AwayReplayItem: Sendable, Equatable {
    /// Start, in ms after the card appeared.
    public var atMs: Int
    public var durationMs: Int
    public var tier: EffectTier
    public var group: AwayGroup
    /// What to pass to the effect layer's `play`.
    public var event: GiftEffectEvent
}

/// The replay of a summary.
public struct AwayReplayPlan: Sendable, Equatable {
    /// In start order.
    public var items: [AwayReplayItem]
    /// When the last effect ends (0 for an empty plan).
    public var endMs: Int

    public init(items: [AwayReplayItem], endMs: Int) {
        self.items = items
        self.endMs = endMs
    }
}

/// A group with its tier, for the planner.
private struct TieredGroup {
    let group: AwayGroup
    let tier: EffectTier
}

/// Plans the replay of an away summary as one short sequence, biggest last (spec 15.3).
public func planAwayReplay(_ groups: [AwayGroup], options: AwayReplayOptions = AwayReplayOptions()) -> AwayReplayPlan {
    if options.reducedMotion {
        return AwayReplayPlan(items: [], endMs: 0)
    }
    let quality = options.quality
    let budget = options.budgetMs
    let limit = max(0, options.maxEffects)
    let thresholds = options.thresholds ?? TierThresholds()
    let labels = options.labels

    var tiered: [TieredGroup] = []
    for group in groups.prefix(limit) {
        tiered.append(TieredGroup(group: group, tier: tierFor(group.gift.price, thresholds: thresholds)))
    }
    let large = tiered.first { $0.tier == .large }
    let notLarge = Array(tiered.filter { $0.tier != .large }.enumerated())
    let rest = notLarge.sorted { a, b in
        if a.element.group.units != b.element.group.units {
            return a.element.group.units < b.element.group.units
        }
        let idA = a.element.group.gift.id
        let idB = b.element.group.gift.id
        if idA != idB {
            // Plain code-unit comparison, like JavaScript's `<` on strings.
            return idA.utf16.lexicographicallyPrecedes(idB.utf16)
        }
        return a.offset < b.offset
    }.map { $0.element }

    func makeItem(_ group: AwayGroup, _ tier: EffectTier, _ atMs: Int, _ durationMs: Int) -> AwayReplayItem {
        var names: [String] = []
        for sender in group.senders {
            if let user = sender.user {
                names.append(options.resolveName?(user) ?? user)
            } else {
                names.append(labels.someone)
            }
        }
        let event = GiftEffectEvent(
            gift: GiftEffectEvent.GiftInfo(
                id: group.gift.id,
                name: group.gift.name,
                price: group.gift.price,
                image: group.gift.animationUrl ?? group.gift.iconUrl,
                icon: group.gift.iconUrl
            ),
            sender: awaySenderLabel(names, senderCount: group.senderCount, labels: labels),
            quantity: group.count
        )
        return AwayReplayItem(atMs: atMs, durationMs: durationMs, tier: tier, group: group, event: event)
    }

    func layout(_ small: [TieredGroup], _ big: TieredGroup?) -> AwayReplayPlan {
        var items: [AwayReplayItem] = []
        var at = 0
        var end = 0
        for t in small {
            let duration = effectDurationMs(recipeFor(t.tier, quality: quality))
            items.append(makeItem(t.group, t.tier, at, duration))
            end = max(end, at + duration)
            at += t.tier == .small ? awayGapAfterSmallMs : awayGapAfterMediumMs
        }
        if let big = big {
            let start = items.isEmpty ? 0 : end + awayLargePauseMs
            let duration = effectDurationMs(recipeFor(.large, quality: quality))
            items.append(makeItem(big.group, .large, start, duration))
            end = start + duration
        }
        return AwayReplayPlan(items: items, endMs: end)
    }

    var small = rest
    var big = large
    var plan = layout(small, big)
    while plan.endMs > budget && !plan.items.isEmpty {
        if !small.isEmpty {
            small.removeFirst()
        } else {
            big = nil
        }
        plan = layout(small, big)
    }
    return plan
}

/// How long the card stays: `max(4000, plan end + 1500)` ms.
public func awayCardDurationMs(_ plan: AwayReplayPlan) -> Int {
    max(awayCardMinMs, plan.endMs + awayCardTailMs)
}

// MARK: - Controller (spec 15.4)

public enum AwayStatus: String, Sendable, Hashable {
    case idle
    case loading
    case empty
    case ready
    case playing
    case done
}

/// When the summary counts as seen.
public enum AwayAckOn: String, Sendable, Hashable {
    /// Default: when the card appears (at-least-once display).
    case shown
    /// When the card goes (replay over, tap or close).
    case finished
    /// Only when the app calls `ack()`.
    case manual
}

public struct AwayState: Sendable, Equatable {
    public var status: AwayStatus
    /// The summary being shown (ready, playing, done), else nil.
    public var summary: AwaySummary?
    /// The replay, planned when the card appears (playing, done), else nil.
    public var plan: AwayReplayPlan?

    public init(status: AwayStatus = .idle, summary: AwaySummary? = nil, plan: AwayReplayPlan? = nil) {
        self.status = status
        self.summary = summary
        self.plan = plan
    }
}

/// Drives one summary card: `check()` loads, the UI shows the card and calls `start()`, the
/// controller plays the replay and dismisses the card after `awayCardDurationMs`, or earlier on
/// `dismiss()`. idle -> loading -> empty | ready -> playing -> done; a failed load goes back to
/// idle silently. `check()` runs only from a resting state (idle, empty, done).
///
/// Settings are plain properties, read again at every use, so they may change at any time.
@MainActor
public final class AwayController {
    public var client: any GiftAwayAPI
    /// The effect layer, read at each play. nil (or returning nil): card only.
    public var effects: (() -> (any EffectPlayer)?)?
    /// Read when the card appears.
    public var reducedMotion: (() -> Bool)?
    public var ackOn: AwayAckOn
    /// Sent as `max_groups` when given.
    public var maxGroups: Int?
    public var maxEffects: Int
    public var budgetMs: Int
    public var thresholds: TierThresholds?
    public var quality: EffectQuality
    public var resolveName: ((String) -> String)?
    public var labels: AwaySenderLabels
    public var throttleMs: Int
    public var onShow: ((AwaySummary) -> Void)?
    public var onDone: (() -> Void)?
    /// Failures never show; they come here.
    public var onError: ((GiftingError) -> Void)?

    public private(set) var state = AwayState() {
        didSet {
            for entry in observers {
                entry.callback(state)
            }
        }
    }

    private let clock: any GiftClock
    private var observers: [(token: Int, callback: (AwayState) -> Void)] = []
    private var nextObserverToken = 0
    private var timers: [Int] = []
    private var alive = true
    /// Whether the summary on screen was acknowledged (or its one attempt was made).
    private var acked = false
    /// A cursor whose acknowledgement failed: retried once, at the next check.
    private var retryCursor: String?
    private var lastCheckAt: Int?

    public init(
        client: any GiftAwayAPI,
        effects: (() -> (any EffectPlayer)?)? = nil,
        reducedMotion: (() -> Bool)? = nil,
        ackOn: AwayAckOn = .shown,
        maxGroups: Int? = nil,
        maxEffects: Int = defaultAwayMaxEffects,
        budgetMs: Int = defaultAwayBudgetMs,
        thresholds: TierThresholds? = nil,
        quality: EffectQuality = .high,
        resolveName: ((String) -> String)? = nil,
        labels: AwaySenderLabels = AwaySenderLabels(),
        throttleMs: Int = awayForegroundThrottleMs,
        clock: (any GiftClock)? = nil,
        onShow: ((AwaySummary) -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil
    ) {
        self.client = client
        self.effects = effects
        self.reducedMotion = reducedMotion
        self.ackOn = ackOn
        self.maxGroups = maxGroups
        self.maxEffects = maxEffects
        self.budgetMs = budgetMs
        self.thresholds = thresholds
        self.quality = quality
        self.resolveName = resolveName
        self.labels = labels
        self.throttleMs = throttleMs
        self.clock = clock ?? SystemGiftClock()
        self.onShow = onShow
        self.onDone = onDone
        self.onError = onError
    }

    /// Calls `observer` after every state change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ observer: @escaping (AwayState) -> Void) -> () -> Void {
        let token = nextObserverToken
        nextObserverToken += 1
        observers.append((token: token, callback: observer))
        return { [weak self] in
            self?.observers.removeAll { $0.token == token }
        }
    }

    private func later(_ ms: Int, _ fire: @escaping () -> Void) {
        timers.append(clock.schedule(afterMs: ms, fire))
    }

    private func stopTimers() {
        let pending = timers
        timers = []
        for handle in pending {
            clock.cancel(handle)
        }
    }

    /// Ask the server what arrived. Ignored while loading, ready or playing.
    public func check() async {
        let s = state.status
        guard s == .idle || s == .empty || s == .done else {
            return
        }
        lastCheckAt = clock.nowMs
        state = AwayState(status: .loading, summary: nil, plan: nil)
        let client = self.client
        if let cursor = retryCursor {
            retryCursor = nil
            do {
                try await client.ackAway(cursor)
            } catch {
                if alive {
                    onError?(asGiftingError(error))
                }
            }
            if !alive {
                return
            }
        }
        var query = AwayQuery()
        query.maxGroups = maxGroups
        let summary: AwaySummary
        do {
            summary = try await client.getAway(query)
        } catch {
            if !alive {
                return
            }
            state.status = .idle
            onError?(asGiftingError(error))
            return
        }
        if !alive {
            return
        }
        acked = false
        if summary.totalGifts <= 0 {
            state.status = .empty
        } else {
            state = AwayState(status: .ready, summary: summary, plan: nil)
        }
    }

    /// The app came back to the foreground: `check()` unless one ran less than `throttleMs` ago.
    public func foreground() async {
        if let last = lastCheckAt, clock.nowMs - last < throttleMs {
            return
        }
        await check()
    }

    /// The card is on screen: plan and play the replay, schedule the dismissal. Only from ready.
    public func start() {
        guard state.status == .ready, let summary = state.summary else {
            return
        }
        let player = effects?()
        let options = AwayReplayOptions(
            maxEffects: maxEffects,
            budgetMs: budgetMs,
            thresholds: thresholds,
            quality: quality,
            reducedMotion: player == nil || (reducedMotion?() ?? false),
            resolveName: resolveName,
            labels: labels
        )
        let plan = planAwayReplay(summary.groups, options: options)
        state = AwayState(status: .playing, summary: summary, plan: plan)
        for item in plan.items {
            let event = item.event
            later(item.atMs) { [weak self] in
                guard let self = self, self.alive, self.state.status == .playing else {
                    return
                }
                _ = self.effects?()?.play(event)
            }
        }
        later(awayCardDurationMs(plan)) { [weak self] in
            self?.dismiss()
        }
        onShow?(summary)
        if ackOn == .shown {
            ack()
        }
    }

    /// Tap or timeout: the card goes. Plays not started yet are dropped; running ones finish (the
    /// controller never calls the layer's `cancel` or `clear`).
    public func dismiss() {
        let s = state.status
        guard s == .ready || s == .playing else {
            return
        }
        stopTimers()
        state.status = .done
        if ackOn != .manual {
            ack()
        }
        onDone?()
    }

    /// Marks the summary on screen as seen (`ackAway(summary.cursor)`). At most once per summary;
    /// a failure is retried once at the next `check()`. `ackOn: .manual` apps call this themselves.
    public func ack() {
        guard !acked, let cursor = state.summary?.cursor, !cursor.isEmpty else {
            return
        }
        acked = true
        let client = self.client
        Task { [weak self] in
            do {
                try await client.ackAway(cursor)
            } catch {
                guard let self = self else {
                    return
                }
                self.retryCursor = cursor
                if self.alive {
                    self.onError?(asGiftingError(error))
                }
            }
        }
    }

    /// The screen is gone: timers stop, answers that arrive later change nothing.
    public func dispose() {
        alive = false
        stopTimers()
    }
}
