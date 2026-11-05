import Foundation
import GiftingStack

/// The gift pictures come from the public library host, like in a real app: downloaded once,
/// then kept by the phone (the host sends them with a one-year cache header).
enum DemoAssets {
    static let host = "https://assets.giftingstack.com"

    static func icon(_ id: String) -> String {
        "\(host)/gifts/\(id)/256.webp"
    }

    static func art(_ id: String) -> String {
        "\(host)/gifts/\(id)/512.webp"
    }
}

/// id, name, price: the small built-in list, used until (or if) the live library loads
/// (the same ten as `FALLBACK` in packages/sdk-js/demo/shared.ts).
private let demoGiftRows: [(String, String, Int)] = [
    ("pink-tulip", "Pink Tulip", 10),
    ("heart-latte", "Heart Latte", 20),
    ("bear-boba", "Bear Boba", 45),
    ("cool-star", "Cool Star", 90),
    ("magic-hat", "Magic Hat", 250),
    ("rainbow-gem", "Rainbow Gem", 600),
    ("treasure-chest", "Treasure Chest", 1_500),
    ("golden-griffin", "Golden Griffin", 4_000),
    ("phoenix", "Phoenix", 9_000),
    ("sun-dragon", "Sun Dragon", 20_000),
]

/// The fallback gifts as the API would return them.
let demoGifts: [Gift] = demoGiftRows.enumerated().map { index, entry in
    Gift(
        id: entry.0,
        name: entry.1,
        description: nil,
        price: entry.2,
        iconUrl: DemoAssets.icon(entry.0),
        animationUrl: DemoAssets.art(entry.0),
        sortOrder: index
    )
}

/// About ninety gifts from the live library (`library.json`), chosen like the web demo
/// (packages/sdk-js/demo/shared.ts `loadGifts`), so the expanded sheet has plenty to scroll.
enum DemoLibrary {
    static let url = "https://assets.giftingstack.com/library.json"

    /// Twelve chosen gifts first.
    static let pick = [
        "pink-tulip", "heart-latte", "bear-boba", "cool-star", "magic-hat", "rainbow-gem",
        "treasure-chest", "golden-griffin", "phoenix", "sun-dragon", "heart-turkey", "star-whale",
    ]

    struct Entry: Decodable {
        let id: String
        let name: String
        let suggestedPrice: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case suggestedPrice = "suggested_price"
        }
    }

    struct File: Decodable {
        let gifts: [Entry]
    }

    /// The live catalog, or nil (offline, bad answer): the app keeps `demoGifts`.
    static func load() async -> [Gift]? {
        guard let target = URL(string: url) else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: target)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            let file = try JSONDecoder().decode(File.self, from: data)
            let gifts = select(file.gifts)
            return gifts.isEmpty ? nil : gifts
        } catch {
            return nil
        }
    }

    /// The twelve chosen gifts, then 78 others spread from cheap to grand. The 108 country
    /// hearts share one price: only one of them is kept.
    static func select(_ all: [Entry]) -> [Gift] {
        let others = all.enumerated()
            .filter { item in
                let id = item.element.id
                return !pick.contains(id) && (!id.hasPrefix("heart-") || id == "heart-turkey")
            }
            .sorted { a, b in
                // Stable like the web's sort: equal prices keep the library's order.
                a.element.suggestedPrice != b.element.suggestedPrice
                    ? a.element.suggestedPrice < b.element.suggestedPrice
                    : a.offset < b.offset
            }
            .map { $0.element }
        let want = 78
        let step = Double(others.count) / Double(want)
        var ids = pick
        for i in 0..<min(want, others.count) {
            ids.append(others[Int((Double(i) * step).rounded(.down))].id)
        }
        var gifts: [Gift] = []
        for (index, id) in ids.enumerated() {
            guard let entry = all.first(where: { $0.id == id }) else {
                continue
            }
            gifts.append(Gift(
                id: id,
                name: entry.name,
                description: nil,
                price: entry.suggestedPrice,
                iconUrl: DemoAssets.icon(id),
                animationUrl: DemoAssets.art(id),
                sortOrder: index
            ))
        }
        return gifts
    }
}
