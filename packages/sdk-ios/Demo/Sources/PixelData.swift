import Foundation
import GiftingStack

/// A person of the pretend app "Pixel": display name and avatar colour (your own user table).
struct PixelPerson {
    let name: String
    let color: UInt32
}

/// The drawing of a post (`PixelArtView`).
enum PixelArtKind {
    case sunset
    case city
    case ocean
    case aurora
}

/// A post of the feed. The post id is the `reference` of the gifts sent to it.
struct PixelPost: Identifiable {
    let id: String
    let author: String
    let text: String
    let art: PixelArtKind
    let ago: String
    let likes: Int
}

/// One line of the Live tab's comment column ("Ava sent 2 x Rose to Theo", or a comment), newest first.
struct PixelRoomFeedItem: Identifiable {
    let id: String
    let sender: String
    /// "2 x Rose" (a combo line grows) or the comment's text.
    var what: String
    let to: String?
    /// The side that got the gift (the room event's `receiverId`, or your own send's receiver): the line takes
    /// that side's colour.
    var receiverId: String? = nil
    /// A comment of the live chat (the app's own, not GiftingStack's): `what` is the text.
    var comment = false
    /// A gift line only: "sender|gift|receiver", the key of a running combo (`PixelModel.addGiftLine`).
    var key: String? = nil
    /// A gift line only: how many gifts the line adds up (a combo), and when it last grew.
    var count = 1
    var at = Date()
}

/// The single mock-data module of the iOS demo; the same content as
/// packages/sdk-js/demo/shared.ts. Not part of the SDK.
enum PixelData {
    /// The signed-in demo user.
    static let me = "ava"

    /// Gifts from others arrive by themselves only when this is true (every 20-40 s). Off: the
    /// developer menu plays them, so nothing surprises a test.
    static let liveFeed = false

    /// The "Gifts received" number of the profile at launch.
    static let startReceived = 214

    static let people: [String: PixelPerson] = [
        "ava": PixelPerson(name: "Ava Carter", color: 0xE0457B),
        "mateo": PixelPerson(name: "Mateo Silva", color: 0x2F9E8F),
        "zoe": PixelPerson(name: "Zoe Lambert", color: 0x7B61FF),
        "caleb": PixelPerson(name: "Caleb Stone", color: 0xE8892B),
        "dana": PixelPerson(name: "Dana", color: 0x2A8FD6),
        "ethan": PixelPerson(name: "Ethan Park", color: 0xC2453D),
        "emma": PixelPerson(name: "Emma", color: 0xB04FD0),
        "sofia": PixelPerson(name: "Sofia Rossi", color: 0x1F9D7A),
        "ben": PixelPerson(name: "Ben", color: 0x6B7A8F),
        "aisha": PixelPerson(name: "Aisha Khan", color: 0xD6559A),
        "kai": PixelPerson(name: "Kai", color: 0x4C6EF5),
        "daphne": PixelPerson(name: "Daphne Lee", color: 0x3AA356),
        "oliver": PixelPerson(name: "Oliver", color: 0xC9822B),
        "ella": PixelPerson(name: "Ella Fox", color: 0x8E5BD9),
        "mia": PixelPerson(name: "Mia", color: 0xD9534F),
        "theo": PixelPerson(name: "Theo Martin", color: 0x3B82A0),
    ]

    /// The people who send gifts to the signed-in user (everyone but ava), in a fixed order.
    static let senders = [
        "mateo", "zoe", "caleb", "dana", "ethan", "emma", "sofia", "ben",
        "aisha", "kai", "daphne", "oliver", "ella", "mia", "theo",
    ]

    static func displayName(_ id: String) -> String {
        people[id]?.name ?? id
    }

    static func firstName(_ id: String) -> String {
        let name = displayName(id)
        return name.split(separator: " ").first.map { String($0) } ?? name
    }

    static func color(_ id: String) -> UInt32 {
        people[id]?.color ?? 0x6B7A8F
    }

    static func initial(_ id: String) -> String {
        displayName(id).first.map { String($0).uppercased() } ?? "?"
    }

    static let posts: [PixelPost] = [
        PixelPost(id: "post_42", author: "mateo", text: "Golden hour on the pier. It never gets old.", art: .sunset, ago: "2h", likes: 482),
        PixelPost(id: "post_43", author: "zoe", text: "New skyline set, three weeks of work. Which window is your favourite?", art: .city, ago: "5h", likes: 1_204),
        PixelPost(id: "post_44", author: "caleb", text: "The tide was perfect this morning.", art: .ocean, ago: "9h", likes: 236),
        PixelPost(id: "post_45", author: "dana", text: "Northern lights from the cabin porch. Hot chocolate helped.", art: .aurora, ago: "1d", likes: 3_071),
    ]

    /// The Live tab's room (a battle between `liveHost` and `liveRival`), as in web.ts.
    static let liveRoom = "pixel-live"
    /// The room of the plain "Live room" mode: one host, no battle.
    static let liveRoomSolo = "pixel-live-room"
    /// The room of the "Battle 4+" mode: four hosts in every round (a free-for-all).
    static let liveRoom4 = "pixel-live-4"
    static let liveHost = "mia"
    static let liveRival = "theo"
    /// The hosts of the battle: the first two play "Battle", all four play "Battle 4+".
    static let liveHosts = [liveHost, liveRival, "sofia", "kai"]

    /// The `resolveUsers` of the demo: what your app would answer from its own user table.
    static func lookUpNames(_ ids: [String]) async throws -> [String: GiftUserInfo] {
        try await Task.sleep(nanoseconds: 150_000_000)
        var out: [String: GiftUserInfo] = [:]
        for id in ids {
            if let person = people[id] {
                out[id] = GiftUserInfo(name: person.name)
            }
        }
        return out
    }

    /// The web demo's string hash: `(h * 31 + code) >>> 0`, starting at 7.
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 7
        for unit in text.utf16 {
            h = h &* 31 &+ UInt32(unit)
        }
        return h
    }
}
