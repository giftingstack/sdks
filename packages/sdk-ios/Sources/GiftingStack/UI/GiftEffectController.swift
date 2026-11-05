#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Drives a `GiftEffectLayer`: call `play` whenever a gift is sent or received. It owns the
/// `EffectScheduler` (queue, caps, combo, notice text) and publishes what the layer draws.
/// Create one per screen (for example as a `@StateObject`) and pass it to the layer.
@MainActor
public final class GiftEffectController: ObservableObject, EffectPlayer {
    /// Effects on screen, in the order they entered.
    @Published public private(set) var effects: [ScheduledEffect] = []
    /// The notice stack, oldest first (the last line is drawn at the bottom). A line that is
    /// sliding out has `visible == false` until it is removed.
    @Published public private(set) var noticeLines: [NoticeLine] = []

    /// Called when an effect played to its end (not for cancelled or cleared ones).
    public var onEffectEnd: ((GiftEffectEvent, EffectTier) -> Void)?

    public let scheduler: EffectScheduler
    private let bridge: SchedulerBridge
    private var noticeStack = NoticeStackModel()
    /// Per line: its expiry timer, then (after it fired) its removal timer.
    private var noticeTimers: [Int: Task<Void, Never>] = [:]
    private static let slideOutNanos: UInt64 = 300_000_000
    private var recipesLoader: RemoteRecipesLoader?
    private var recipesStarted = false

    /// - Parameter comboWindowMs: same gift from the same person within this time is a combo.
    ///   nil (default): 2500 ms, or the remote recipe set's value (spec 13.4).
    public init(comboWindowMs: Int? = nil) {
        scheduler = EffectScheduler(comboWindowMs: comboWindowMs)
        bridge = SchedulerBridge()
        bridge.owner = self
        scheduler.listener = bridge
        #if canImport(UIKit) && !os(watchOS)
        scheduler.reducedMotion = UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// `low` for slow phones: fewer sparks, no coin rain, no rays. Read at every `play`.
    public var quality: EffectQuality {
        get { scheduler.quality }
        set { scheduler.quality = newValue }
    }

    /// From which price a gift is medium or large. Read at every `play`. nil (default): the
    /// recipe set's thresholds (100 and 10,000, or the remote document's).
    public var thresholds: TierThresholds? {
        get { scheduler.thresholds }
        set { scheduler.thresholds = newValue }
    }

    /// Only the notice shows, no effect. The layer keeps this in step with the system's
    /// Reduce Motion setting unless you pass `reducedMotion` to it.
    public var reducedMotion: Bool {
        get { scheduler.reducedMotion }
        set { scheduler.reducedMotion = newValue }
    }

    /// Shows a gift. Large gifts wait their turn; small and medium ones play at once.
    /// Returns an id for `cancel`. Ids start at 1 and are never reused.
    @discardableResult
    public func play(_ event: GiftEffectEvent) -> Int {
        if let loader = recipesLoader {
            // The newest remote set for this gift; effects already playing keep theirs.
            scheduler.recipes = loader.current()?.recipeSet
        }
        return scheduler.play(event)
    }

    /// Starts remote recipes once per controller (spec 13.5): the cached copy at once, a
    /// background refresh when one is due. `enabled == false`, or a `version` that cannot be
    /// pinned, means no network and the embedded numbers. `GiftEffectLayer` calls this when it
    /// appears.
    public func startRemoteRecipes(enabled: Bool = true, version: String? = nil, url: String? = nil) {
        if recipesStarted {
            return
        }
        recipesStarted = true
        recipesLoader = RemoteRecipesLoader.start(remoteRecipes: enabled, recipesVersion: version, recipesUrl: url)
    }

    /// Takes back a gift that was shown too early, for example because its send failed.
    public func cancel(_ id: Int) {
        scheduler.cancel(id)
    }

    /// Stops everything and forgets the queue and the combo run.
    public func clear() {
        scheduler.clear()
    }

    // MARK: - Called by the effect views

    func effectStarted(_ id: Int) {
        scheduler.started(id)
    }

    func effectFinished(_ id: Int) {
        scheduler.finished(id)
    }

    // MARK: - Scheduler listener

    fileprivate func handleEnter(_ effect: ScheduledEffect) {
        effects.append(effect)
    }

    fileprivate func handleExit(_ effect: ScheduledEffect) {
        effects.removeAll { $0.id == effect.id }
    }

    fileprivate func handleEnd(_ effect: ScheduledEffect) {
        onEffectEnd?(effect.event, effect.recipe.tier)
    }

    fileprivate func handleNotice(_ data: NoticeData, durationMs: Int) {
        if case .added(let dropped) = noticeStack.show(data), let dropped = dropped {
            noticeTimers[dropped]?.cancel()
            noticeTimers[dropped] = nil
        }
        noticeLines = noticeStack.lines
        // This line's own expiry. The scheduler is not told: a line that is gone is just new.
        let id = data.id
        noticeTimers[id]?.cancel()
        let nanos = UInt64(max(0, durationMs)) * 1_000_000
        noticeTimers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled {
                return
            }
            self?.expireNotice(id)
        }
    }

    private func expireNotice(_ id: Int) {
        guard noticeStack.expire(id: id) else {
            return
        }
        noticeLines = noticeStack.lines
        scheduleRemoval(id)
    }

    private func scheduleRemoval(_ id: Int) {
        noticeTimers[id]?.cancel()
        noticeTimers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: GiftEffectController.slideOutNanos)
            if Task.isCancelled {
                return
            }
            self?.removeNotice(id)
        }
    }

    private func removeNotice(_ id: Int) {
        noticeTimers[id] = nil
        if noticeStack.removeHidden(id: id) {
            noticeLines = noticeStack.lines
        }
    }

    /// The core's hide (cancel of the notice owner, inside clear): only the newest line goes.
    fileprivate func handleNoticeHide() {
        if let id = noticeStack.hideNewest() {
            noticeLines = noticeStack.lines
            scheduleRemoval(id)
        }
    }

    fileprivate func handleClear() {
        effects = []
        for timer in noticeTimers.values {
            timer.cancel()
        }
        noticeTimers = [:]
        noticeStack.clear()
        noticeLines = []
    }
}

/// Keeps the listener methods off the controller's public surface.
@MainActor
private final class SchedulerBridge: EffectSchedulerListener {
    weak var owner: GiftEffectController?

    func effectDidEnter(_ effect: ScheduledEffect) {
        owner?.handleEnter(effect)
    }

    func effectDidExit(_ effect: ScheduledEffect) {
        owner?.handleExit(effect)
    }

    func effectDidEnd(_ effect: ScheduledEffect) {
        owner?.handleEnd(effect)
    }

    func noticeDidShow(_ notice: NoticeData, durationMs: Int) {
        owner?.handleNotice(notice, durationMs: durationMs)
    }

    func noticeDidHide() {
        owner?.handleNoticeHide()
    }

    func effectsDidClear() {
        owner?.handleClear()
    }
}
#endif
