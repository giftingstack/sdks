#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Put one of these over your screen, once, and call `play` on its controller whenever a gift is
/// sent or received. It draws the effect by the gift's price and the "ayla sent X" notice with a
/// combo counter. It never takes touches (spec section 7).
@MainActor
public struct GiftEffectLayer: View {
    @ObservedObject private var controller: GiftEffectController
    private let thresholds: TierThresholds?
    private let quality: EffectQuality
    private let reducedMotion: Bool?
    private let origin: CGPoint
    private let pictureWaitMs: Int
    private let noticeBottom: CGFloat
    private let theme: GiftingTheme
    private let pictureScale: Double?
    private let remoteRecipes: Bool
    private let recipesVersion: String?
    private let recipesUrl: String?
    private let onEffectEnd: ((GiftEffectEvent, EffectTier) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// - Parameters:
    ///   - reducedMotion: nil (default) follows the system Reduce Motion setting, live.
    ///   - origin: where gifts start, as fractions of the layer. Default bottom centre (0.5, 0.86).
    ///   - pictureWaitMs: longest wait for a gift's picture before its effect starts anyway.
    ///   - noticeBottom: distance of the notice from the bottom edge, in points (above a tray).
    ///   - thresholds: nil (default) uses the recipe set's (100 / 10,000, or the remote ones).
    ///   - pictureScale: multiplier for the gift picture; nil (default) is automatic, about 1 on a
    ///     phone and up to 2 in a big layer, like the web layer.
    ///   - remoteRecipes: fetch tuned effect numbers (spec 13, cached, at most every 6 h). `false`
    ///     means no network at all. `recipesVersion` pins a document, `recipesUrl` self-hosts it.
    public init(
        controller: GiftEffectController,
        thresholds: TierThresholds? = nil,
        quality: EffectQuality = .high,
        reducedMotion: Bool? = nil,
        origin: CGPoint = CGPoint(x: 0.5, y: 0.86),
        pictureWaitMs: Int = 300,
        noticeBottom: CGFloat = 150,
        theme: GiftingTheme = GiftingTheme(),
        pictureScale: Double? = nil,
        remoteRecipes: Bool = true,
        recipesVersion: String? = nil,
        recipesUrl: String? = nil,
        onEffectEnd: ((GiftEffectEvent, EffectTier) -> Void)? = nil
    ) {
        self.controller = controller
        self.thresholds = thresholds
        self.quality = quality
        self.reducedMotion = reducedMotion
        self.origin = origin
        self.pictureWaitMs = pictureWaitMs
        self.noticeBottom = noticeBottom
        self.theme = theme
        self.pictureScale = pictureScale
        self.remoteRecipes = remoteRecipes
        self.recipesVersion = recipesVersion
        self.recipesUrl = recipesUrl
        self.onEffectEnd = onEffectEnd
    }

    private var effectiveReducedMotion: Bool {
        reducedMotion ?? systemReduceMotion
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                // The reference draws effects only once the layer has a size (spec open question 9).
                if size.width > 0 && size.height > 0 {
                    ForEach(controller.effects) { effect in
                        EffectItemView(
                            effect: effect,
                            size: size,
                            origin: CGPoint(x: origin.x * size.width, y: origin.y * size.height),
                            pictureWaitMs: pictureWaitMs,
                            pictureScale: pictureScale,
                            theme: theme,
                            controller: controller
                        )
                    }
                }
                // Up to three lines, oldest first, so the newest is at the bottom.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(controller.noticeLines) { line in
                        NoticeView(data: line.data, visible: line.visible, theme: theme)
                    }
                }
                .frame(maxWidth: max(0, size.width * 0.92), alignment: .leading)
                .padding(.leading, 12)
                .padding(.bottom, noticeBottom)
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .onAppear {
            applyOptions()
            controller.startRemoteRecipes(enabled: remoteRecipes, version: recipesVersion, url: recipesUrl)
        }
        .onChange(of: quality) { _ in
            applyOptions()
        }
        .onChange(of: thresholds) { _ in
            applyOptions()
        }
        .onChange(of: effectiveReducedMotion) { _ in
            applyOptions()
        }
    }

    private func applyOptions() {
        controller.quality = quality
        controller.thresholds = thresholds
        controller.reducedMotion = effectiveReducedMotion
        if let onEffectEnd = onEffectEnd {
            controller.onEffectEnd = onEffectEnd
        }
    }
}

// MARK: - One effect

/// Plays one gift from start to finish and reports `started` and `finished` to the controller.
@MainActor
struct EffectItemView: View {
    @StateObject private var runner: EffectRunner
    private let theme: GiftingTheme

    init(
        effect: ScheduledEffect,
        size: CGSize,
        origin: CGPoint,
        pictureWaitMs: Int,
        pictureScale: Double?,
        theme: GiftingTheme,
        controller: GiftEffectController
    ) {
        _runner = StateObject(wrappedValue: EffectRunner(
            effect: effect,
            size: size,
            origin: origin,
            pictureWaitMs: pictureWaitMs,
            pictureScale: pictureScale,
            controller: controller
        ))
        self.theme = theme
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let start = runner.startDate {
                TimelineView(.animation) { context in
                    let t = max(0, context.date.timeIntervalSince(start) * 1000)
                    EffectFrameView(
                        frame: EffectTimeline.frame(at: t, recipe: runner.drawRecipe, layout: runner.layout),
                        recipe: runner.drawRecipe,
                        layout: runner.layout,
                        image: runner.image,
                        theme: theme
                    )
                }
            } else {
                // Until it starts the effect draws nothing visible (spec 7.2).
                Color.clear
            }
        }
        .onAppear {
            runner.begin()
        }
    }
}

/// Draws one frame. Back to front: dim, rays, glow, sparks, coins, picture.
@MainActor
struct EffectFrameView: View {
    let frame: EffectFrame
    let recipe: EffectRecipe
    let layout: EffectLayout
    let image: CGImage?
    let theme: GiftingTheme

    var body: some View {
        let box = CGFloat(EffectTimeline.pictureSize)
        ZStack(alignment: .topLeading) {
            if recipe.dim {
                Color.black
                    .opacity(frame.dimOpacity)
                    .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
            }
            if recipe.rays || recipe.sparks > 0 || recipe.coins > 0 {
                ParticleCanvas(frame: frame, recipe: recipe, layout: layout, theme: theme)
                    .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
            }
            picture
                .frame(width: box, height: box)
                .scaleEffect(CGFloat(frame.pictureScale))
                .opacity(frame.pictureOpacity)
                .offset(
                    x: CGFloat(frame.pictureCenter.x) - box / 2,
                    y: CGFloat(frame.pictureCenter.y) - box / 2
                )
        }
        .frame(width: CGFloat(layout.width), height: CGFloat(layout.height), alignment: .topLeading)
    }

    @ViewBuilder
    private var picture: some View {
        if let image = image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Without a picture the reference draws a coin-coloured disc.
            Circle().fill(theme.coin)
        }
    }
}

/// Rays, glow, sparks and coins in one Canvas.
@MainActor
struct ParticleCanvas: View {
    let frame: EffectFrame
    let recipe: EffectRecipe
    let layout: EffectLayout
    let theme: GiftingTheme

    var body: some View {
        let frame = self.frame
        let recipe = self.recipe
        let layout = self.layout
        let colors = ParticleColors(glow: theme.glow, accent: theme.accent, coin: theme.coin)
        Canvas { context, _ in
            ParticleCanvas.draw(in: &context, frame: frame, recipe: recipe, layout: layout, colors: colors)
        }
    }

    nonisolated static func draw(
        in context: inout GraphicsContext,
        frame: EffectFrame,
        recipe: EffectRecipe,
        layout: EffectLayout,
        colors: ParticleColors
    ) {
        let stage = CGPoint(x: layout.stage.x, y: layout.stage.y)

        if recipe.rays && frame.raysFade > 0 {
            let r = min(layout.width, layout.height) * 1.6
            let sets: [(turn: Double, halfWidth: Double, opacity: Double)] = [
                (turn: frame.wideTurnDegrees, halfWidth: r * 0.075, opacity: 0.34),
                (turn: frame.thinTurnDegrees, halfWidth: r * 0.028, opacity: 0.42),
            ]
            for set in sets {
                var rays = context
                rays.opacity = set.opacity * frame.raysFade
                for i in 0..<12 {
                    let degrees = Double(i) * 30 + set.turn
                    let path = rayPath(center: stage, length: r / 2, halfWidth: set.halfWidth, degrees: degrees)
                    rays.fill(path, with: .color(colors.glow))
                }
            }
            // A soft round glow: discs that are brighter towards the middle.
            var glow = context
            glow.opacity = 0.16 * frame.raysFade
            for k in [1.0, 0.78, 0.58, 0.4, 0.24] {
                let d: Double = 340 * k * frame.glowScale
                let rect = CGRect(x: layout.stage.x - d / 2, y: layout.stage.y - d / 2, width: d, height: d)
                glow.fill(Path(ellipseIn: rect), with: .color(colors.glow))
            }
        }

        if !layout.sparks.isEmpty && frame.burst > 0 {
            var sparks = context
            sparks.opacity = max(0, min(1, EffectTimeline.sparkOpacity(frame.burst)))
            let scale = EffectTimeline.sparkScale(frame.burst)
            for spark in layout.sparks {
                let d: Double = spark.size * scale
                let cx: Double = layout.stage.x + spark.dx * frame.burst
                let cy: Double = layout.stage.y + spark.dy * frame.burst
                let rect = CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
                sparks.fill(Path(ellipseIn: rect), with: .color(spark.accent ? colors.accent : colors.glow))
            }
        }

        if !layout.coins.isEmpty && frame.rain > 0 {
            for coin in layout.coins {
                let alpha = EffectTimeline.coinOpacity(coin, rain: frame.rain)
                if alpha <= 0 {
                    continue
                }
                var one = context
                one.opacity = alpha
                let top = EffectTimeline.coinTop(coin, rain: frame.rain, height: layout.height)
                let rect = CGRect(x: coin.x, y: top, width: coin.size, height: coin.size)
                one.fill(Path(ellipseIn: rect), with: .color(colors.coin))
            }
        }
    }

    /// A thin triangle from the centre outwards, pointing at the centre: one light ray. At 0
    /// degrees its wide end is straight above the centre (the reference's border triangle).
    nonisolated static func rayPath(center: CGPoint, length: Double, halfWidth: Double, degrees: Double) -> Path {
        let a = degrees * Double.pi / 180
        let cosA = cos(a)
        let sinA = sin(a)
        let cx = Double(center.x)
        let cy = Double(center.y)
        let points: [(Double, Double)] = [(-halfWidth, -length), (halfWidth, -length), (0, 0)]
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = cx + point.0 * cosA - point.1 * sinA
            let y = cy + point.0 * sinA + point.1 * cosA
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The three colours the particles use.
struct ParticleColors {
    let glow: Color
    let accent: Color
    let coin: Color
}

/// The state of one effect: its fixed random layout, the picture gate and the timers.
@MainActor
final class EffectRunner: ObservableObject {
    let effect: ScheduledEffect
    /// The recipe as drawn: picture and spark spread scaled for the layer size (`pictureScale`).
    let drawRecipe: EffectRecipe
    let layout: EffectLayout
    @Published private(set) var image: CGImage?
    @Published private(set) var startDate: Date?

    private weak var controller: GiftEffectController?
    private let pictureWaitMs: Int
    private var gate: PictureGate?
    private var waitTimer: Task<Void, Never>?

    init(
        effect: ScheduledEffect,
        size: CGSize,
        origin: CGPoint,
        pictureWaitMs: Int,
        pictureScale: Double?,
        controller: GiftEffectController
    ) {
        let scaled = EffectTimeline.scaledRecipe(
            effect.recipe,
            width: Double(size.width),
            height: Double(size.height),
            manual: pictureScale
        )
        self.effect = effect
        self.drawRecipe = scaled
        self.layout = EffectLayout(
            recipe: scaled,
            width: Double(size.width),
            height: Double(size.height),
            origin: EffectPoint(x: Double(origin.x), y: Double(origin.y))
        )
        self.pictureWaitMs = pictureWaitMs
        self.controller = controller
        #if canImport(ImageIO)
        if let url = effect.event.gift.image {
            self.image = GiftImageCache.shared.cached(url)
        }
        #endif
    }

    /// Called once when the effect's view appears (spec 7.2).
    func begin() {
        guard gate == nil else {
            return
        }
        let url = effect.event.gift.image
        let newGate = PictureGate(hasPicture: url != nil, pictureWaitMs: pictureWaitMs) { [weak self] in
            self?.start()
        }
        gate = newGate
        guard let wait = newGate.begin() else {
            // Started at once; still show the picture when it arrives.
            loadPicture(url, reportTo: nil)
            return
        }
        let nanos = UInt64(wait) * 1_000_000
        waitTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled {
                return
            }
            self?.gate?.waitElapsed()
        }
        if image != nil {
            newGate.pictureLoaded()
        } else {
            loadPicture(url, reportTo: newGate)
        }
    }

    private func loadPicture(_ url: String?, reportTo gate: PictureGate?) {
        guard let url = url, image == nil else {
            return
        }
        #if canImport(ImageIO)
        GiftImageCache.shared.load(url) { [weak self] loaded in
            guard let self = self else {
                return
            }
            if let loaded = loaded {
                self.image = loaded
                gate?.pictureLoaded()
            } else {
                gate?.pictureFailed()
            }
        }
        #else
        gate?.pictureFailed()
        #endif
    }

    private func start() {
        waitTimer?.cancel()
        waitTimer = nil
        startDate = Date()
        let id = effect.id
        controller?.effectStarted(id)
        // The finish timer holds the controller, not this runner, so an effect whose view went
        // away still ends and frees its slot.
        let nanos = UInt64(EffectTimeline.totalMs(effect.recipe) * 1_000_000)
        let owner = controller
        Task { [weak owner] in
            try? await Task.sleep(nanoseconds: nanos)
            owner?.effectFinished(id)
        }
    }
}
#endif
