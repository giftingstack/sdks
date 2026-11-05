import Foundation
import GiftingStack
import SwiftUI

/// The colours of the pretend app around the SDK (packages/sdk-js/demo/pixel.css).
struct PixelPalette {
    let background: Color
    let card: Color
    let line: Color
    let text: Color
    let muted: Color
    let accent: Color
    let accent2: Color
}

/// The demo themes (demo only: an app passes `theme` to each SDK view).
enum PixelTheme: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case pink = "Pink"

    var id: String {
        rawValue
    }

    var gifting: GiftingTheme {
        switch self {
        case .dark:
            return GiftingTheme.dark
        case .light:
            return GiftingTheme.light
        case .pink:
            return (try? GiftingTheme.fromAccent("#ff4f9a", mode: .dark)) ?? GiftingTheme.dark
        }
    }

    var palette: PixelPalette {
        switch self {
        case .dark:
            return PixelPalette(
                background: Color(giftingHex: 0x0A0A11),
                card: Color(giftingHex: 0x151521),
                line: Color(giftingHex: 0x262638),
                text: Color(giftingHex: 0xF4F2FF),
                muted: Color(giftingHex: 0x9A98B6),
                accent: Color(giftingHex: 0x8B7BFF),
                accent2: Color(giftingHex: 0xFF5FA2)
            )
        case .light:
            return PixelPalette(
                background: Color(giftingHex: 0xF1F0F8),
                card: Color(giftingHex: 0xFFFFFF),
                line: Color(giftingHex: 0xE3E1EE),
                text: Color(giftingHex: 0x17162A),
                muted: Color(giftingHex: 0x65647E),
                accent: Color(giftingHex: 0x6A4CFF),
                accent2: Color(giftingHex: 0xE0457B)
            )
        case .pink:
            return PixelPalette(
                background: Color(giftingHex: 0x150A13),
                card: Color(giftingHex: 0x231221),
                line: Color(giftingHex: 0x3E2139),
                text: Color(giftingHex: 0xFFF1F8),
                muted: Color(giftingHex: 0xC49AB5),
                accent: Color(giftingHex: 0xFF4F9A),
                accent2: Color(giftingHex: 0xFFA24F)
            )
        }
    }

    var isLight: Bool {
        self == .light
    }
}

enum PixelTab: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case live = "Live"
    case top = "Top"
    case inbox = "Inbox"
    case me = "Me"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .feed:
            return "house.fill"
        case .live:
            return "dot.radiowaves.left.and.right"
        case .top:
            return "chart.bar.fill"
        case .inbox:
            return "bell.fill"
        case .me:
            return "person.crop.circle.fill"
        }
    }
}

/// Which gift the developer menu's "Play gift" and "x5 combo" use.
enum PixelIncomingMode: String, CaseIterable, Identifiable {
    case tray = "Same as tray"
    case random = "Random"
    case cheapest = "Cheapest"
    case priciest = "Priciest"

    var id: String {
        rawValue
    }
}

enum PixelMotion: String, CaseIterable, Identifiable {
    case system = "System"
    case reduced = "Reduced"

    var id: String {
        rawValue
    }
}

/// Remembers that the "while you were away" card was shown once after install. A real app shows
/// it until new gifts arrive; this demo's mock data starts over on every launch.
final class AwaySeenStore {
    private let key = "pixel-away-seen"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    var seen: Bool {
        defaults.bool(forKey: key)
    }

    func markSeen() {
        defaults.set(true, forKey: key)
    }
}

/// Everything the pretend app keeps alive (mirrors packages/sdk-js/demo/web.ts). What a customer
/// would write: the effect controller, the tray model, one wall loader, the away model and the
/// leaderboard models. The rest is the demo's own fake app.
@MainActor
final class PixelModel: ObservableObject {
    let client: MockGiftingClient
    let effects: GiftEffectController
    let tray: GiftTrayModel
    /// One wall loader for the whole app (every `GiftWall` shares its batches and cache).
    let walls: GiftWallLoader
    let away: GiftAwayModel
    let senders: GiftLeaderboardModel
    let receivers: GiftLeaderboardModel
    let awaySeen: AwaySeenStore
    /// The Live tab: a pretend rooms server and the SDK's real room model running against it. In a
    /// real app: `GiftRoomModel(room:getToken:client:effects:)` with no `socket`.
    let fakeRoom: DemoFakeRoom
    let room: GiftRoomModel

    @Published var gifts: [Gift] = demoGifts
    /// The Live tab's feed of room gifts, newest first (30 at most).
    @Published var roomFeed: [PixelRoomFeedItem] = []
    @Published var tab: PixelTab = .feed
    @Published var balance = 0
    @Published var received = PixelData.startReceived
    /// The Inbox tab's list: the SDK's `GiftInbox` reads the last 24 hours from the mock server.
    let inbox: GiftInboxModel
    /// The unread badge: gifts newer than the newest row shown when the tab was last viewed.
    @Published var unread = 0
    private var inboxItems: [InboxItem] = []
    private var inboxSeenMs: Int? = PixelModel.nowMs()
    /// Refresh keys of the walls, by "receiver|reference".
    @Published var wallKeys: [String: Int] = [:]
    /// The post the tray is for (the last one whose Gift button was pressed). Whether it is shown is `tray.isOpen`.
    @Published var trayPost: PixelPost?
    @Published var trayGiftId: String?
    /// Grows with every opening: the tray starts fresh.
    @Published var trayToken = 0
    // The SDK does the rest (SPEC 9.4): picking a gift lowers the sheet (collapseOnSelect) and the dim goes away
    // while it is low, a tap on the dim closes the tray (scrimTap: .dismiss), and the Gift button toggles it.
    /// The gift selected in the tray last ("Same as tray").
    @Published var selectedId = "sun-dragon"
    @Published var storeOpen = false
    @Published var devMenuOpen = false
    @Published var incomingMode: PixelIncomingMode = .tray
    @Published var quality: EffectQuality = .high
    @Published var theme: PixelTheme = .dark
    @Published var motion: PixelMotion = .system
    @Published var offline = false
    @Published var hidden = false
    @Published var board: LeaderboardBoard = .senders

    private var started = false
    private var liveTask: Task<Void, Never>?

    init() {
        let client = MockGiftingClient()
        let effects = GiftEffectController()
        let seen = AwaySeenStore()
        self.client = client
        self.effects = effects
        self.awaySeen = seen
        // Closed until a Gift button opens it.
        self.tray = GiftTrayModel(client: client, receiver: "mateo", effects: effects, reference: "post_42", open: false)
        self.walls = GiftWallLoader(client: client)
        self.away = GiftAwayModel(
            client: client,
            effects: effects,
            resolveUsers: PixelData.lookUpNames,
            autoCheck: false,
            onShow: { _ in
                seen.markSeen()
            }
        )
        self.senders = GiftLeaderboardModel(client: client, board: .senders, resolveUsers: PixelData.lookUpNames)
        self.receivers = GiftLeaderboardModel(client: client, board: .receivers, resolveUsers: PixelData.lookUpNames)
        self.inbox = GiftInboxModel(client: client, resolveUsers: PixelData.lookUpNames, pageSize: 8)
        let fakeRoom = DemoFakeRoom(
            gifts: demoGifts,
            senders: PixelData.senders.filter { $0 != PixelData.liveHost && $0 != PixelData.liveRival },
            receivers: [PixelData.liveHost, PixelData.liveRival]
        )
        self.fakeRoom = fakeRoom
        self.room = GiftRoomModel(
            room: PixelData.liveRoom,
            getToken: { _ in demoRoomToken(PixelData.me) },
            client: client,
            effects: effects,
            resolveName: { PixelData.displayName($0) },
            socket: fakeRoom.socketFactory
        )
        // Closures capturing self come after every stored property is assigned (Swift refuses them before).
        tray.controller.onSent = { [weak self] tx in
            self?.didSend(tx)
        }
        room.onEvent = { [weak self] event in
            self?.roomGift(event)
        }
        inbox.onLoaded = { [weak self] items in
            self?.inboxLoaded(items)
        }
    }

    // MARK: - Inbox badge

    static func nowMs() -> Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }

    /// Every load of the list: the badge counts what is newer than the last viewed row.
    private func inboxLoaded(_ items: [InboxItem]) {
        inboxItems = items
        if tab == .inbox {
            markInboxSeen()
        } else {
            unread = inboxUnread(items, lastSeenMs: inboxSeenMs)
        }
    }

    /// The tab is on screen: remember the newest row shown, clear the badge.
    private func markInboxSeen() {
        var newest = inboxSeenMs
        for item in inboxItems {
            if let ms = inboxParseTime(item.createdAt), ms > (newest ?? Int.min) {
                newest = ms
            }
        }
        inboxSeenMs = newest
        unread = 0
    }

    // MARK: - Live tab

    /// The Live tab is on screen: join the room (or reconnect, with resume).
    func joinLive() {
        room.join()
    }

    /// The Live tab went off: close the socket, keep the resume point.
    func leaveLive() {
        room.pause()
    }

    private func roomGift(_ event: RoomGiftEvent) {
        let what = event.quantity > 1 ? "\(event.quantity) x \(event.gift.name)" : event.gift.name
        let to = event.receiverId.map { PixelData.firstName($0) }
        roomFeed.insert(PixelRoomFeedItem(id: event.tx, sender: event.sender ?? "Someone", what: what, to: to), at: 0)
        if roomFeed.count > 30 {
            roomFeed = Array(roomFeed.prefix(30))
        }
    }

    /// The app is on screen (once).
    func start() {
        if started {
            return
        }
        started = true
        tray.start()
        syncBalance()
        Task { [weak self] in
            await self?.loadLibrary()
        }
        // The away card: the first time after install only, then from the developer menu.
        if !awaySeen.seen {
            showAway()
        }
        if PixelData.liveFeed {
            startLiveFeed()
        }
    }

    var reducedMotion: Bool? {
        motion == .reduced ? true : nil
    }

    // MARK: - Library, balance, walls

    /// About ninety gifts from the live library; the small built-in list stays on failure.
    func loadLibrary() async {
        guard let list = await DemoLibrary.load() else {
            return
        }
        await client.setGifts(list)
        gifts = list
        fakeRoom.gifts = list
        tray.refresh()
    }

    func syncBalance() {
        let client = self.client
        Task { [weak self] in
            if let me = try? await client.getMe() {
                self?.balance = me.balance
            }
        }
    }

    static func wallKey(_ receiver: String, _ reference: String?) -> String {
        "\(receiver)|\(reference ?? "")"
    }

    func wallRefresh(_ receiver: String, _ reference: String?) -> Int {
        wallKeys[PixelModel.wallKey(receiver, reference)] ?? 0
    }

    func bumpWall(_ receiver: String, _ reference: String?) {
        let key = PixelModel.wallKey(receiver, reference)
        wallKeys[key] = (wallKeys[key] ?? 0) + 1
    }

    func bumpAllWalls() {
        for post in PixelData.posts {
            bumpWall(post.author, post.id)
        }
        bumpWall(PixelData.me, nil)
    }

    func refreshBoards() {
        senders.refresh()
        receivers.refresh()
    }

    // MARK: - Tabs

    func select(_ next: PixelTab) {
        // The tray stays above the tab bar, so a tap on the bar closes it.
        if tray.isOpen && next != tab {
            closeTray()
        }
        tab = next
        if next == .inbox {
            markInboxSeen()
        }
    }

    // MARK: - Tray and coin store

    /// The Gift button of a post: the same post toggles the tray, another post opens it for that post.
    func giftButton(_ post: PixelPost, roomId: String? = nil) {
        if trayPost?.id == post.id, tray.controller.receiver == post.author, tray.controller.roomId == roomId {
            tray.toggle()
        } else {
            openTray(post, roomId: roomId)
        }
    }

    /// Opens the tray for a post (or a chip of its wall, with that gift picked), fresh at its first state.
    func openTray(_ post: PixelPost, giftId: String? = nil, roomId: String? = nil) {
        tray.controller.receiver = post.author
        tray.controller.reference = post.id
        tray.controller.roomId = roomId
        trayGiftId = giftId
        trayToken += 1
        trayPost = post
        tray.open()
        tray.refresh()
    }

    func closeTray() {
        trayGiftId = nil
        tray.close()
    }

    /// After a send: the balance and the post's wall update (the effect keeps playing in the
    /// layer; the tray stays open).
    private func didSend(_ tx: GiftTransaction) {
        balance = tx.senderBalanceAfter
        bumpWall(tx.receiver, tx.reference)
        // What the API does after a send with `room_id` (the demo has no server): the room gets it.
        if tray.controller.roomId == PixelData.liveRoom, let gift = gifts.first(where: { $0.id == tx.gift.id }) {
            fakeRoom.publish(sender: PixelData.me, gift: gift, quantity: tx.quantity, receiver: tx.receiver)
        }
        // The tray stays open after a send, like a live app: tap again for a combo, the Gift
        // button again to close it.
    }

    /// The pretend store's "buy": credit the coins (it ADDS), then reload the balance.
    func buy(_ coins: Int) {
        storeOpen = false
        let client = self.client
        let tray = self.tray
        Task { [weak self] in
            await client.credit(coins)
            tray.refresh()
            self?.syncBalance()
        }
    }

    // MARK: - Gifts from others

    private func chosenGift(_ mode: PixelIncomingMode) -> Gift? {
        switch mode {
        case .tray:
            return gifts.first(where: { $0.id == selectedId }) ?? gifts.first
        case .random:
            return gifts.randomElement()
        case .cheapest:
            return gifts.min(by: { $0.price < $1.price })
        case .priciest:
            return gifts.max(by: { $0.price < $1.price })
        }
    }

    /// Someone else sends the signed-in user a gift: effect, profile wall, inbox, badge.
    func deliver(_ gift: Gift, sender: String, quantity: Int) {
        effects.play(GiftEffectEvent(gift: gift, sender: PixelData.displayName(sender), quantity: quantity))
        received += quantity
        let client = self.client
        let me = PixelData.me
        Task { [weak self] in
            await client.addToWall(me, giftId: gift.id, quantity: quantity, reference: nil)
            await client.addInbox(gift, sender: sender, quantity: quantity)
            self?.bumpWall(me, nil)
            // The list (and with it the badge) reloads from the server's first page.
            self?.inbox.refresh()
        }
    }

    func playIncoming() {
        guard let gift = chosenGift(incomingMode), let sender = PixelData.senders.randomElement() else {
            return
        }
        deliver(gift, sender: sender, quantity: 1)
    }

    /// Five in a row from one person, 250 ms apart: the combo counter.
    func combo() {
        guard let gift = chosenGift(incomingMode), let sender = PixelData.senders.randomElement() else {
            return
        }
        for i in 0..<5 {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(i) * 250_000_000)
                self?.deliver(gift, sender: sender, quantity: 1)
            }
        }
    }

    private static func tier(_ price: Int) -> Int {
        price >= 10_000 ? 2 : (price >= 100 ? 1 : 0)
    }

    /// One gift of the live feed: 78 % small, 19 % medium, 3 % large.
    private func liveGift() {
        let roll = Double.random(in: 0..<1)
        let want = roll < 0.78 ? 0 : (roll < 0.97 ? 1 : 2)
        let pool = gifts.filter { PixelModel.tier($0.price) == want }
        guard let gift = (pool.isEmpty ? gifts : pool).randomElement(), let sender = PixelData.senders.randomElement() else {
            return
        }
        let quantity = want == 0 ? Int.random(in: 1...3) : (want == 1 ? Int.random(in: 1...2) : 1)
        deliver(gift, sender: sender, quantity: quantity)
    }

    private func startLiveFeed() {
        liveTask?.cancel()
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                let delayMs = UInt64(Int.random(in: 20_000...40_000))
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                guard let self = self else {
                    return
                }
                if !self.offline {
                    self.liveGift()
                }
            }
        }
    }

    // MARK: - Developer menu

    /// "While you were away" again: the mock server has new gifts, then check.
    func showAway() {
        let client = self.client
        let away = self.away
        Task {
            await client.armAway()
            away.check()
        }
    }

    /// Someone else sends five of a random gift to every post and to the profile.
    func wallPlus() {
        let client = self.client
        let posts = PixelData.posts
        var picks: [String] = []
        for _ in posts {
            picks.append(gifts.randomElement()?.id ?? "pink-tulip")
        }
        let mine = gifts.randomElement()?.id ?? "pink-tulip"
        let me = PixelData.me
        Task { [weak self] in
            for (index, post) in posts.enumerated() {
                await client.addToWall(post.author, giftId: picks[index], quantity: 5, reference: post.id)
            }
            await client.addToWall(me, giftId: mine, quantity: 5, reference: nil)
            self?.bumpAllWalls()
        }
    }

    func setQuality(_ value: EffectQuality) {
        quality = value
        away.controller.quality = value
    }

    func setMotion(_ value: PixelMotion) {
        motion = value
        away.reducedMotion = value == .reduced ? true : nil
    }

    func setHidden(_ value: Bool) {
        hidden = value
        let client = self.client
        Task { [weak self] in
            await client.setHidden(value)
            self?.refreshBoards()
        }
    }

    func setOffline(_ value: Bool) {
        offline = value
        let client = self.client
        Task { [weak self] in
            await client.setOffline(value)
            guard let self = self, !value else {
                return
            }
            self.bumpAllWalls()
            self.refreshBoards()
            self.syncBalance()
            self.tray.refresh()
        }
    }

    /// Back to the start: 60,000 coins, walls and inbox as at launch, the away card once more.
    func reset() {
        closeTray()
        storeOpen = false
        received = PixelData.startReceived
        hidden = false
        inboxSeenMs = PixelModel.nowMs()
        inboxItems = []
        unread = 0
        let client = self.client
        Task { [weak self] in
            await client.reset()
            guard let self = self else {
                return
            }
            self.inbox.refresh()
            self.bumpAllWalls()
            self.refreshBoards()
            self.syncBalance()
            self.tray.refresh()
            self.showAway()
        }
    }
}
