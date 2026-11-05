import Foundation

// The timeline of one effect as pure math (spec 7.3), so it builds and is tested without a
// screen. The SwiftUI layer evaluates `EffectTimeline.frame(at:)` once per display frame and
// only applies translation, scale and opacity from it.

public struct EffectPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct EffectSpark: Sendable, Equatable {
    /// Travel from the stage point at the end of the burst.
    public var dx: Double
    public var dy: Double
    /// Diameter in points.
    public var size: Double
    /// `accent` colour (every third spark), else `glow`.
    public var accent: Bool
}

public struct EffectCoin: Sendable, Equatable {
    /// Left edge in points.
    public var x: Double
    /// Diameter in points.
    public var size: Double
    /// Fraction of the rain duration the coin waits.
    public var start: Double
    /// Fraction of the rain duration it takes to fall.
    public var fall: Double
}

/// Random layout of one effect, fixed when it is created (never changes, even on resize).
public struct EffectLayout: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var origin: EffectPoint
    public var stage: EffectPoint
    public var sparks: [EffectSpark]
    public var coins: [EffectCoin]

    /// - Parameters:
    ///   - origin: start point in layer coordinates (`origin fraction * size`).
    ///   - random: uniform in [0, 1). Injectable for tests.
    public init(
        recipe: EffectRecipe,
        width: Double,
        height: Double,
        origin: EffectPoint,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.width = width
        self.height = height
        self.origin = origin
        switch recipe.stage {
        case .center:
            stage = EffectPoint(x: width / 2, y: height * 0.38)
        case .floatUp:
            stage = EffectPoint(x: origin.x + (random() - 0.5) * 0.2 * width, y: origin.y - 0.32 * height)
        }
        var sparks: [EffectSpark] = []
        let n = recipe.sparks
        for i in 0..<max(0, n) {
            let angle = Double(i) / Double(max(1, n)) * Double.pi * 2 + random() * 0.6
            let distance = recipe.sparkSpread * (0.4 + random() * 0.8)
            sparks.append(EffectSpark(
                dx: cos(angle) * distance,
                dy: sin(angle) * distance,
                size: 5 + random() * 6,
                accent: i % 3 == 0
            ))
        }
        self.sparks = sparks
        var coins: [EffectCoin] = []
        for _ in 0..<max(0, recipe.coins) {
            coins.append(EffectCoin(
                x: random() * width,
                size: 10 + random() * 8,
                start: random() * 0.35,
                fall: 0.45 + random() * 0.2
            ))
        }
        self.coins = coins
    }
}

/// Everything that moves in one frame of an effect.
public struct EffectFrame: Sendable, Equatable {
    /// Centre of the 100 pt picture box, in layer coordinates.
    public var pictureCenter: EffectPoint
    public var pictureScale: Double
    public var pictureOpacity: Double
    /// Opacity of the full-screen black (0 when the recipe has no dim).
    public var dimOpacity: Double
    /// Burst progress after ease-out cubic, 0...1.
    public var burst: Double
    /// Coin rain progress (linear), 0...1.
    public var rain: Double
    /// Rays and glow fade, 0...1.
    public var raysFade: Double
    /// Rotation of the wide and the thin ray set, in degrees.
    public var wideTurnDegrees: Double
    public var thinTurnDegrees: Double
    /// Scale of the glow discs.
    public var glowScale: Double
}

public enum EffectTimeline {
    /// Picture box size at scale 1, in points.
    public static let pictureSize: Double = 100
    public static let burstMs: Double = 900
    public static let coinTailMs: Double = 800
    public static let dimInMs: Double = 300
    public static let dimMax: Double = 0.62

    /// How much bigger than the phone layout the picture is drawn in a big layer (the web's
    /// `pictureScale`). A phone layer (about 390 x 700) gives about 1; the picture grows with the
    /// layer's area up to 2, never beyond 90 % of the short side at its biggest. `manual`
    /// replaces the automatic value (the room limit still applies).
    public static func pictureScale(width: Double, height: Double, peakScale: Double, manual: Double? = nil) -> Double {
        let room = (0.9 * min(width, height)) / (pictureSize * max(peakScale, 0.0001))
        let wanted = manual ?? min(2, max(1, (width * height).squareRoot() / 530))
        return min(wanted, max(room, 0.5))
    }

    /// The recipe as drawn in a layer of this size: picture and spark spread grow by
    /// `pictureScale`; times and counts stay the same.
    public static func scaledRecipe(_ recipe: EffectRecipe, width: Double, height: Double, manual: Double? = nil) -> EffectRecipe {
        let k = pictureScale(width: width, height: height, peakScale: recipe.peakScale, manual: manual)
        if k == 1 {
            return recipe
        }
        var out = recipe
        out.peakScale = recipe.peakScale * k
        out.sparkSpread = recipe.sparkSpread * k
        return out
    }

    /// `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`: small 1600, medium 2100,
    /// large 3850 (high) or 3050 (low).
    public static func totalMs(_ recipe: EffectRecipe) -> Double {
        let tail = Double(recipe.holdMs + recipe.flyOutMs)
        let coinsEnd = recipe.coins > 0 ? tail + coinTailMs : 0
        return Double(recipe.flyInMs) + max(burstMs, max(tail, coinsEnd))
    }

    public static func frame(at t: Double, recipe: EffectRecipe, layout: EffectLayout) -> EffectFrame {
        let flyIn = Double(recipe.flyInMs)
        let hold = Double(recipe.holdMs)
        let flyOut = Double(recipe.flyOutMs)
        let tail = hold + flyOut

        let fly = Easing.backOut(clamp01(flyIn > 0 ? t / flyIn : 1), overshoot: 1.3)
        let leave = Easing.quadIn(clamp01(flyOut > 0 ? (t - flyIn - hold) / flyOut : (t >= flyIn + hold ? 1 : 0)))
        let burst = Easing.cubicOut(clamp01((t - flyIn) / burstMs))
        let rain = recipe.coins > 0 ? clamp01((t - flyIn) / (tail + coinTailMs)) : 0
        let spinTotal = flyIn + tail
        let spin = recipe.rays ? clamp01(spinTotal > 0 ? t / spinTotal : 1) : 0

        let o = layout.origin
        let s = layout.stage
        let x = lerp(o.x, s.x, fly)
        let y = lerp(o.y, s.y, fly) + lerp(0, -0.07 * layout.height, leave)
        let growth = lerp(0.3, recipe.peakScale, fly)
        let shrink = lerp(1, 0.55, leave)
        let appear = piecewise(fly, [0, 0.06, 1], [0, 1, 1])
        let vanish = 1 - leave

        var dim: Double = 0
        if recipe.dim {
            if t < flyIn + hold {
                dim = dimMax * clamp01(t / dimInMs)
            } else {
                // Linear back to 0 over flyOutMs, from wherever the dim is (always 1 by then).
                let fadeIn = clamp01(t / dimInMs)
                let fadeOut = flyOut > 0 ? clamp01((t - flyIn - hold) / flyOut) : 1
                dim = dimMax * fadeIn * (1 - fadeOut)
            }
        }

        return EffectFrame(
            pictureCenter: EffectPoint(x: x, y: y),
            pictureScale: growth * shrink,
            pictureOpacity: max(0, min(1, appear * vanish)),
            dimOpacity: dim,
            burst: burst,
            rain: rain,
            raysFade: piecewise(spin, [0, 0.1, 0.85, 1], [0, 1, 1, 0]),
            wideTurnDegrees: lerp(0, 60, spin),
            thinTurnDegrees: lerp(15, -35, spin),
            glowScale: lerp(0.4, 1, fly)
        )
    }

    /// Spark opacity for a burst progress: 0 to 1 at 12 %, then to 0 at 100 %.
    public static func sparkOpacity(_ burst: Double) -> Double {
        piecewise(burst, [0, 0.12, 1], [0, 1, 0])
    }

    /// Spark scale for a burst progress: 1 to 0.2.
    public static func sparkScale(_ burst: Double) -> Double {
        lerp(1, 0.2, burst)
    }

    /// Coin opacity: 0 until its start, 1 by start + 0.02.
    public static func coinOpacity(_ coin: EffectCoin, rain: Double) -> Double {
        if rain <= coin.start {
            return 0
        }
        return clamp01((rain - coin.start) / 0.02)
    }

    /// Coin top edge: falls from y = -24 by `height + 48` between p = start and
    /// p = min(1, start + fall), clamped.
    public static func coinTop(_ coin: EffectCoin, rain: Double, height: Double) -> Double {
        let end = min(1, coin.start + coin.fall)
        let p = end > coin.start ? clamp01((rain - coin.start) / (end - coin.start)) : (rain >= end ? 1 : 0)
        return -24 + p * (height + 48)
    }

    static func clamp01(_ v: Double) -> Double {
        if v.isNaN {
            return 0
        }
        return max(0, min(1, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Linear interpolation through the points, extended (not clamped) beyond the ends, like
    /// React Native's `interpolate` default.
    static func piecewise(_ v: Double, _ input: [Double], _ output: [Double]) -> Double {
        guard input.count >= 2, input.count == output.count else {
            return output.first ?? 0
        }
        var i = 1
        while i < input.count - 1 && v > input[i] {
            i += 1
        }
        let x0 = input[i - 1]
        let x1 = input[i]
        let y0 = output[i - 1]
        let y1 = output[i]
        if x1 == x0 {
            return y1
        }
        return y0 + (y1 - y0) * (v - x0) / (x1 - x0)
    }
}

/// React Native's easing functions, as used by the reference effects.
public enum Easing {
    /// `Easing.out(Easing.back(s))`: overshoots past 1 before settling.
    public static func backOut(_ t: Double, overshoot s: Double) -> Double {
        let u = 1 - t
        return 1 - u * u * ((s + 1) * u - s)
    }

    /// `Easing.out(Easing.cubic)`.
    public static func cubicOut(_ t: Double) -> Double {
        let u = 1 - t
        return 1 - u * u * u
    }

    /// `Easing.in(Easing.quad)`.
    public static func quadIn(_ t: Double) -> Double {
        t * t
    }
}
