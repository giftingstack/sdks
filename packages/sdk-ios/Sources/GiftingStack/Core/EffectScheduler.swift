import Foundation

/// One gift the scheduler put on screen (or queued).
public struct ScheduledEffect: Sendable, Equatable, Identifiable {
    public let id: Int
    public let event: GiftEffectEvent
    public let recipe: EffectRecipe
    /// Combo count for the notice, fixed when the gift was played.
    public let count: Int

    public init(id: Int, event: GiftEffectEvent, recipe: EffectRecipe, count: Int) {
        self.id = id
        self.event = event
        self.recipe = recipe
        self.count = count
    }
}

/// What the "ayla sent Rose x3" notice shows.
public struct NoticeData: Sendable, Equatable, Hashable {
    /// Changes when a different sender or gift starts a new notice.
    public let id: Int
    public let senderName: String
    public let giftName: String
    public let image: String?
    /// Gifts in a row, 1 for a single gift.
    public let count: Int
    public let big: Bool
    /// Only in a battle (SPEC 7.4): who got the gift and the side's colour.
    public let receiver: GiftEffectReceiver?

    public init(
        id: Int,
        senderName: String,
        giftName: String,
        image: String?,
        count: Int,
        big: Bool,
        receiver: GiftEffectReceiver? = nil
    ) {
        self.id = id
        self.senderName = senderName
        self.giftName = giftName
        self.image = image
        self.count = count
        self.big = big
        self.receiver = receiver
    }
}

/// What the UI implements to draw the scheduler's decisions. Every method has an empty default.
/// (The spec calls them enter, exit, end, notice, noticeHide and clear; the Swift names differ so
/// they never collide with an effect controller's own `clear()`.)
@MainActor
public protocol EffectSchedulerListener: AnyObject {
    /// An effect enters the screen. Draw it; call `started(id)` once its picture is ready.
    func effectDidEnter(_ effect: ScheduledEffect)
    /// An effect leaves the screen (finished or cancelled). Remove it.
    func effectDidExit(_ effect: ScheduledEffect)
    /// An effect played to its end. Not called for cancelled or cleared effects.
    func effectDidEnd(_ effect: ScheduledEffect)
    /// Show this notice now and call `noticeExpired()` after `durationMs`, replacing any timer.
    func noticeDidShow(_ notice: NoticeData, durationMs: Int)
    /// Hide the notice and drop its timer.
    func noticeDidHide()
    /// Every effect is gone at once (`clear`).
    func effectsDidClear()
}

extension EffectSchedulerListener {
    public func effectDidEnter(_ effect: ScheduledEffect) {}
    public func effectDidExit(_ effect: ScheduledEffect) {}
    public func effectDidEnd(_ effect: ScheduledEffect) {}
    public func noticeDidShow(_ notice: NoticeData, durationMs: Int) {}
    public func noticeDidHide() {}
    public func effectsDidClear() {}
}

/// Decides which gift effects are on screen, which wait and what the notice says (spec section 6).
/// No drawing, no timers: the UI reports `started` and `finished`. Ported line by line from
/// `packages/sdk-js/src/core/effects.ts`.
@MainActor
public final class EffectScheduler {
    public weak var listener: EffectSchedulerListener?
    /// The app's thresholds; nil takes them from the recipe set (remote, else embedded). Read at
    /// every `play`; they win over a remote set (spec 13.4).
    public var thresholds: TierThresholds?
    /// A remote recipe set (spec section 13), read at every `play`. nil: the embedded set. The
    /// recipe is fixed at `play`, so effects on screen or waiting keep theirs.
    public var recipes: RecipeSet?
    /// Read at every `play`.
    public var quality: EffectQuality = .high
    /// Only the notice shows, no effect. Read at every `play`.
    public var reducedMotion = false

    private let combo: ComboTracker
    /// The combo window the app gave; when nil the recipe set's window applies at each `play`.
    private let appComboWindowMs: Int?
    private static let embeddedSet = RecipeSet.embedded()
    private let now: () -> Double
    private var nextId = 1
    private var runningSmall = 0
    private var runningMedium = 0
    private var runningLarge = 0
    private var queue: [ScheduledEffect] = []
    /// Effects on screen, in the order they entered.
    private var onScreen: [ScheduledEffect] = []
    /// Notice ids remembered at once, one per (sender, gift) pair; the oldest is dropped beyond this.
    public static let maxNoticeKeys = 32
    /// (sender, gift) pair -> notice id, oldest first.
    private var noticeIds: [(key: String, id: Int)] = []
    private var lastNoticeKey = ""
    private var noticeCounter = 0
    /// The play() id that wrote the notice; 0 before any.
    public private(set) var noticeOwner = 0
    /// The last notice written. It stays after the notice hides.
    public private(set) var noticeData: NoticeData?
    public private(set) var noticeVisible = false

    /// `now` returns milliseconds (default: a monotonic clock). `comboWindowMs` nil (default)
    /// follows the recipe set (2500 when embedded).
    public init(
        comboWindowMs: Int? = nil,
        now: @escaping () -> Double = { ComboTracker.monotonicNowMs() }
    ) {
        self.appComboWindowMs = comboWindowMs
        self.combo = ComboTracker(windowMs: comboWindowMs ?? GiftingSpec.comboWindowMs)
        self.now = now
    }

    /// Effects on screen, in the order they entered.
    public var active: [ScheduledEffect] {
        onScreen
    }

    /// Large effects waiting their turn, oldest first.
    public var queued: [ScheduledEffect] {
        queue
    }

    /// Shows a gift. Large gifts wait their turn; small and medium ones play at once, or show
    /// only the notice when too many are on screen. Returns an id for `cancel`.
    @discardableResult
    public func play(_ event: GiftEffectEvent) -> Int {
        // Merge order: embedded < remote < app (spec 13.4).
        let set = mergeRecipeSet(
            embedded: EffectScheduler.embeddedSet,
            remote: recipes,
            app: AppRecipeOverrides(
                mediumFrom: thresholds?.mediumFrom,
                largeFrom: thresholds?.largeFrom,
                comboWindowMs: appComboWindowMs
            )
        )
        combo.windowMs = set.comboWindowMs
        let tier = tierFor(event.gift.price, thresholds: set.thresholds)
        let recipe = recipeFor(tier, quality: quality, set: set)
        let sender = event.sender ?? GiftingSpec.defaultSenderName
        let quantity = event.quantity ?? 1
        let id = nextId
        nextId += 1
        // A combo counts per receiver too: gifts to two hosts of a battle are two runs.
        let rkey = EffectScheduler.receiverKey(event.receiver)
        let run = combo.hit(sender: sender, giftId: rkey == nil ? event.gift.id : "\(event.gift.id)\u{0}\(rkey!)", now: now())
        let count = quantity > 1 ? quantity : run
        let item = ScheduledEffect(id: id, event: event, recipe: recipe, count: count)
        // Without an effect the notice shows now; with one, it shows when the effect starts.
        if reducedMotion {
            showNotice(item)
            return id
        }
        if tier == .large {
            if running(.large) >= GiftingSpec.maxConcurrentEffects(.large) {
                if queue.count >= GiftingSpec.maxQueuedLarge {
                    queue.removeFirst()
                }
                queue.append(item)
            } else {
                start(item)
            }
        } else if running(tier) < GiftingSpec.maxConcurrentEffects(tier) {
            start(item)
        } else {
            showNotice(item) // too many on screen: notice only
        }
        return id
    }

    /// The effect's picture is ready (or the wait ran out): it really starts, with its notice.
    public func started(_ id: Int) {
        if let item = onScreen.first(where: { $0.id == id }) {
            showNotice(item)
        }
    }

    /// The effect's animation ran to its end.
    public func finished(_ id: Int) {
        guard let item = onScreen.first(where: { $0.id == id }) else {
            return
        }
        release(item)
        listener?.effectDidEnd(item)
    }

    /// Takes back a gift that was shown too early, for example because its send failed.
    public func cancel(_ id: Int) {
        queue.removeAll { $0.id == id }
        if let item = onScreen.first(where: { $0.id == id }) {
            release(item)
        }
        if noticeOwner == id {
            hideNotice()
        }
    }

    /// Stops everything, forgets the queue and the combo run.
    public func clear() {
        queue = []
        onScreen = []
        runningSmall = 0
        runningMedium = 0
        runningLarge = 0
        listener?.effectsDidClear()
        hideNotice()
        noticeIds = []
        combo.reset()
    }

    /// The notice's time is up.
    public func noticeExpired() {
        noticeVisible = false
        noticeIds = []
        lastNoticeKey = ""
        listener?.noticeDidHide()
    }

    // MARK: - Private

    private func running(_ tier: EffectTier) -> Int {
        switch tier {
        case .small:
            return runningSmall
        case .medium:
            return runningMedium
        case .large:
            return runningLarge
        }
    }

    private func setRunning(_ tier: EffectTier, _ value: Int) {
        switch tier {
        case .small:
            runningSmall = value
        case .medium:
            runningMedium = value
        case .large:
            runningLarge = value
        }
    }

    private func start(_ item: ScheduledEffect) {
        setRunning(item.recipe.tier, running(item.recipe.tier) + 1)
        onScreen.append(item)
        listener?.effectDidEnter(item)
    }

    /// Takes an effect off the screen and lets the next large one in.
    private func release(_ item: ScheduledEffect) {
        let tier = item.recipe.tier
        onScreen.removeAll { $0.id == item.id }
        setRunning(tier, max(0, running(tier) - 1))
        listener?.effectDidExit(item)
        if tier == .large, !queue.isEmpty {
            let next = queue.removeFirst()
            start(next)
        }
    }

    /// What tells two receivers apart for the combo and the notice key: the side and the name (two hosts
    /// with one display name still sit on different sides). nil without a receiver.
    private static func receiverKey(_ receiver: GiftEffectReceiver?) -> String? {
        guard let receiver = receiver else {
            return nil
        }
        return "\(receiver.side.map(String.init) ?? ""):\(receiver.name)"
    }

    private func showNotice(_ item: ScheduledEffect) {
        let event = item.event
        let sender = event.sender ?? GiftingSpec.defaultSenderName
        let receiver = event.receiver
        // The receiver is part of the key: a combo to one host and one to the other are two notices.
        let rkey = EffectScheduler.receiverKey(receiver)
        let key = rkey == nil ? "\(sender)|\(event.gift.id)" : "\(sender)|\(event.gift.id)|\(rkey!)"
        noticeOwner = item.id
        // Every pair keeps its own id while it is remembered, so a combo returns to its own line
        // even when other people sent gifts in between.
        let id: Int
        if let index = noticeIds.firstIndex(where: { $0.key == key }) {
            id = noticeIds[index].id
            noticeIds.remove(at: index)
        } else {
            noticeCounter += 1
            id = noticeCounter
        }
        noticeIds.append((key: key, id: id))
        if noticeIds.count > EffectScheduler.maxNoticeKeys {
            noticeIds.removeFirst()
        }
        lastNoticeKey = key
        let data = NoticeData(
            id: id,
            senderName: sender,
            giftName: event.gift.name,
            image: event.gift.icon ?? event.gift.image,
            count: item.count,
            big: item.recipe.noticeBig,
            receiver: receiver
        )
        noticeData = data
        noticeVisible = true
        listener?.noticeDidShow(data, durationMs: item.recipe.noticeMs)
    }

    private func hideNotice() {
        noticeVisible = false
        noticeIds.removeAll { $0.key == lastNoticeKey }
        lastNoticeKey = ""
        listener?.noticeDidHide()
    }
}
