import Foundation

// Remote recipes (spec section 13): effect numbers from a hosted copy of `recipes.json`. Pure:
// parse, clamp and merge only. Ported from `packages/sdk-js/src/core/remote-recipes.ts`. The
// network and the cache live in `RemoteRecipesLoader`.

/// Untyped JSON, so a remote document can be read field by field (a bool never counts as a
/// number: `JSONDecoder` keeps them apart).
public enum RemoteJSON: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RemoteJSON])
    case object([String: RemoteJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([RemoteJSON].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: RemoteJSON].self))
        }
    }

    /// The decoded document, or nil when the bytes are not JSON.
    public static func parse(_ data: Data) -> RemoteJSON? {
        try? JSONDecoder().decode(RemoteJSON.self, from: data)
    }

    public var objectValue: [String: RemoteJSON]? {
        if case .object(let o) = self {
            return o
        }
        return nil
    }
}

/// The three recipes of one quality.
public struct RecipeTable: Sendable, Equatable {
    public var small: EffectRecipe
    public var medium: EffectRecipe
    public var large: EffectRecipe

    public init(small: EffectRecipe, medium: EffectRecipe, large: EffectRecipe) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    public subscript(_ tier: EffectTier) -> EffectRecipe {
        get {
            switch tier {
            case .small:
                return small
            case .medium:
                return medium
            case .large:
                return large
            }
        }
        set {
            switch tier {
            case .small:
                small = newValue
            case .medium:
                medium = newValue
            case .large:
                large = newValue
            }
        }
    }
}

/// The numbers a remote document may change. Caps, queue size and sender name are not here.
public struct RecipeSet: Sendable, Equatable {
    public var thresholds: TierThresholds
    public var comboWindowMs: Int
    public var high: RecipeTable
    public var low: RecipeTable

    public init(thresholds: TierThresholds, comboWindowMs: Int, high: RecipeTable, low: RecipeTable) {
        self.thresholds = thresholds
        self.comboWindowMs = comboWindowMs
        self.high = high
        self.low = low
    }

    public func table(_ quality: EffectQuality) -> RecipeTable {
        quality == .high ? high : low
    }

    public func recipe(_ tier: EffectTier, quality: EffectQuality) -> EffectRecipe {
        table(quality)[tier]
    }

    /// The values built into the SDK (`recipes.json`).
    public static func embedded() -> RecipeSet {
        func makeTable(_ quality: EffectQuality) -> RecipeTable {
            RecipeTable(
                small: recipeFor(.small, quality: quality),
                medium: recipeFor(.medium, quality: quality),
                large: recipeFor(.large, quality: quality)
            )
        }
        return RecipeSet(
            thresholds: TierThresholds(),
            comboWindowMs: GiftingSpec.comboWindowMs,
            high: makeTable(.high),
            low: makeTable(.low)
        )
    }
}

/// A parsed remote document: a full set (missing or bad fields hold the embedded value).
public struct RemoteRecipeSet: Sendable, Equatable {
    /// The document's own `specVersion` (same major as the SDK).
    public var specVersion: String
    public var recipeSet: RecipeSet

    public init(specVersion: String, recipeSet: RecipeSet) {
        self.specVersion = specVersion
        self.recipeSet = recipeSet
    }
}

/// Allowed range of one remote number (spec 13.3).
public struct RemoteRecipeLimit: Sendable, Equatable {
    public let min: Double
    public let max: Double
    public let integer: Bool
}

/// What the app passed itself. Not clamped: the app owns its own numbers.
public struct AppRecipeOverrides: Sendable, Equatable {
    public var mediumFrom: Int?
    public var largeFrom: Int?
    public var comboWindowMs: Int?

    public init(mediumFrom: Int? = nil, largeFrom: Int? = nil, comboWindowMs: Int? = nil) {
        self.mediumFrom = mediumFrom
        self.largeFrom = largeFrom
        self.comboWindowMs = comboWindowMs
    }
}

public enum RemoteRecipes {
    /// Default address of the hosted document. Hosting it is a separate deploy step.
    public static let defaultUrl = "https://assets.giftingstack.com/recipes.json"

    /// The limits table of spec 13.3 (code name `REMOTE_RECIPE_LIMITS`), in the spec's order.
    public static let limits: [(key: String, limit: RemoteRecipeLimit)] = [
        (key: "peakScale", limit: RemoteRecipeLimit(min: 0.5, max: 4, integer: false)),
        (key: "flyInMs", limit: RemoteRecipeLimit(min: 0, max: 10_000, integer: true)),
        (key: "holdMs", limit: RemoteRecipeLimit(min: 0, max: 10_000, integer: true)),
        (key: "flyOutMs", limit: RemoteRecipeLimit(min: 0, max: 10_000, integer: true)),
        (key: "sparks", limit: RemoteRecipeLimit(min: 0, max: 120, integer: true)),
        (key: "sparkSpread", limit: RemoteRecipeLimit(min: 0, max: 400, integer: true)),
        (key: "coins", limit: RemoteRecipeLimit(min: 0, max: 120, integer: true)),
        (key: "noticeMs", limit: RemoteRecipeLimit(min: 500, max: 8_000, integer: true)),
        (key: "mediumFrom", limit: RemoteRecipeLimit(min: 1, max: 1_000_000, integer: true)),
        (key: "largeFrom", limit: RemoteRecipeLimit(min: 2, max: 10_000_000, integer: true)),
        (key: "comboWindowMs", limit: RemoteRecipeLimit(min: 500, max: 10_000, integer: true)),
    ]

    public static func limit(_ key: String) -> RemoteRecipeLimit {
        for entry in limits where entry.key == key {
            return entry.limit
        }
        // Every caller passes a key of the table; this keeps the value unchanged otherwise.
        return RemoteRecipeLimit(min: -Double.greatestFiniteMagnitude, max: Double.greatestFiniteMagnitude, integer: false)
    }

    /// A finite number, clamped and (integer fields) rounded half up; otherwise the fallback.
    static func clampField(_ key: String, _ value: RemoteJSON?, _ fallback: Double) -> Double {
        guard case .number(let n)? = value, n.isFinite else {
            return fallback
        }
        let l = limit(key)
        let clamped = Swift.min(l.max, Swift.max(l.min, n))
        return l.integer ? (clamped + 0.5).rounded(.down) : clamped
    }

    static func clampInt(_ key: String, _ value: RemoteJSON?, _ fallback: Int) -> Int {
        Int(clampField(key, value, Double(fallback)))
    }

    static func parseRecipe(_ tier: EffectTier, _ raw: RemoteJSON?, base: EffectRecipe) -> EffectRecipe {
        var out = base
        out.tier = tier
        guard let o = raw?.objectValue else {
            return out
        }
        out.peakScale = clampField("peakScale", o["peakScale"], base.peakScale)
        out.flyInMs = clampInt("flyInMs", o["flyInMs"], base.flyInMs)
        out.holdMs = clampInt("holdMs", o["holdMs"], base.holdMs)
        out.flyOutMs = clampInt("flyOutMs", o["flyOutMs"], base.flyOutMs)
        out.sparks = clampInt("sparks", o["sparks"], base.sparks)
        out.sparkSpread = clampField("sparkSpread", o["sparkSpread"], base.sparkSpread)
        out.coins = clampInt("coins", o["coins"], base.coins)
        out.noticeMs = clampInt("noticeMs", o["noticeMs"], base.noticeMs)
        if case .bool(let v)? = o["dim"] {
            out.dim = v
        }
        if case .bool(let v)? = o["rays"] {
            out.rays = v
        }
        if case .bool(let v)? = o["noticeBig"] {
            out.noticeBig = v
        }
        if case .string(let s)? = o["stage"], let stage = EffectStage(rawValue: s) {
            out.stage = stage
        }
        return out
    }

    static func parseThresholds(_ raw: RemoteJSON?, base: TierThresholds) -> TierThresholds {
        guard let o = raw?.objectValue else {
            return base
        }
        let mediumFrom = clampInt("mediumFrom", o["mediumFrom"], base.mediumFrom)
        let largeFrom = clampInt("largeFrom", o["largeFrom"], base.largeFrom)
        // The pair must stay ordered; otherwise neither value is used.
        return largeFrom > mediumFrom ? TierThresholds(mediumFrom: mediumFrom, largeFrom: largeFrom) : base
    }

    /// The major part of an `x.y.z` version (ASCII digits only, no suffix), or nil.
    static func major(_ version: String) -> Int? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        for part in parts {
            if part.isEmpty || !part.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return nil
            }
        }
        return Int(parts[0])
    }
}

/// Reads a remote recipes document. nil: the whole document is ignored (not an object, or a
/// `specVersion` that is not `x.y.z` of the SDK's major). Every bad field keeps its embedded
/// value; numbers are clamped (`RemoteRecipes.limits`). Caps, queue size, sender name, stage
/// kinds and unknown keys are never taken.
public func parseRemoteRecipes(_ json: RemoteJSON, embedded: RecipeSet = RecipeSet.embedded()) -> RemoteRecipeSet? {
    guard let doc = json.objectValue else {
        return nil
    }
    guard case .string(let version)? = doc["specVersion"],
          let docMajor = RemoteRecipes.major(version),
          let sdkMajor = RemoteRecipes.major(GiftingSpec.specVersion),
          docMajor == sdkMajor else {
        return nil
    }
    let rawRecipes = doc["recipes"]?.objectValue ?? [:]
    func makeTable(_ quality: EffectQuality) -> RecipeTable {
        let rawQuality = rawRecipes[quality.rawValue]?.objectValue ?? [:]
        let base = embedded.table(quality)
        return RecipeTable(
            small: RemoteRecipes.parseRecipe(.small, rawQuality["small"], base: base.small),
            medium: RemoteRecipes.parseRecipe(.medium, rawQuality["medium"], base: base.medium),
            large: RemoteRecipes.parseRecipe(.large, rawQuality["large"], base: base.large)
        )
    }
    let set = RecipeSet(
        thresholds: RemoteRecipes.parseThresholds(doc["thresholds"], base: embedded.thresholds),
        comboWindowMs: RemoteRecipes.clampInt("comboWindowMs", doc["comboWindowMs"], embedded.comboWindowMs),
        high: makeTable(.high),
        low: makeTable(.low)
    )
    return RemoteRecipeSet(specVersion: version, recipeSet: set)
}

/// The set effects use. Merge order (spec 13.4): embedded < remote < app.
public func mergeRecipeSet(
    embedded: RecipeSet,
    remote: RecipeSet?,
    app: AppRecipeOverrides = AppRecipeOverrides()
) -> RecipeSet {
    var out = remote ?? embedded
    if let medium = app.mediumFrom {
        out.thresholds.mediumFrom = medium
    }
    if let large = app.largeFrom {
        out.thresholds.largeFrom = large
    }
    if let window = app.comboWindowMs {
        out.comboWindowMs = window
    }
    return out
}

/// The address to fetch. `version` pins a document: the LAST `.json` becomes `.<version>.json`.
/// nil (no network) when the version is not 1-64 characters of `A-Z a-z 0-9 . _ -`, or the URL
/// has no `.json` to pin.
public func remoteRecipesUrl(_ url: String? = nil, version: String? = nil) -> String? {
    let base = url ?? RemoteRecipes.defaultUrl
    guard let version = version else {
        return base
    }
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    guard version.count >= 1, version.count <= 64, version.allSatisfy({ allowed.contains($0) }) else {
        return nil
    }
    guard let at = base.range(of: ".json", options: .backwards) else {
        return nil
    }
    return String(base[..<at.lowerBound]) + "." + version + String(base[at.lowerBound...])
}
