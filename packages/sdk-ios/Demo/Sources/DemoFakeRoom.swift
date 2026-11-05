import Foundation
import GiftingStack

/// A pretend rooms server for the demo (the Swift twin of packages/sdk-js/demo/fakeRoom.ts): a
/// `RoomSocket` that speaks the real wire protocol (SPEC 17: `hello` -> `welcome`, then `gift`,
/// `viewers` and `scores` frames), so the demo runs the SDK's real `GiftRoomModel` without a rooms
/// Worker. Other people send gifts to the room every few seconds, now and then five in a row (a
/// combo). The room also runs back-to-back battle rounds between the receivers and sends `scores`
/// frames like the real room (SPEC 17.8: at most one per 250 ms, nothing when a round ends, a new
/// round after a short break). Inject `socketFactory` as `GiftRoomModel(socket:)`; call `publish`
/// for the app's own sends. Demo only, not part of the SDK. The demo has no test target, so this
/// is kept small and untested.
@MainActor
final class DemoFakeRoom {
    /// The catalog the others' gifts come from (the demo sets it once the library loaded).
    var gifts: [Gift]

    private let senders: [String]
    private let receivers: [String]
    private let roundMs: Int
    private let breakMs: Int
    private var viewers = 38 + Int.random(in: 0..<20)
    private var sockets: [DemoFakeRoomSocket] = []
    private var nextId = Int(Date().timeIntervalSince1970 * 1000) * 1000
    private var nextTx = 1

    private var battle: RoomBattle?
    private var roundNo = 0
    private var roundTask: Task<Void, Never>?
    private var scoresTask: Task<Void, Never>?
    private var lastScoresAt = 0

    init(gifts: [Gift], senders: [String], receivers: [String], roundMs: Int = 90_000, breakMs: Int = 8_000) {
        self.gifts = gifts
        self.senders = senders
        self.receivers = receivers
        self.roundMs = roundMs
        self.breakMs = breakMs
    }

    /// For `GiftRoomModel(socket:)`: every "connection" is a socket of this room.
    var socketFactory: RoomSocketFactory {
        let room = self
        return { _, _, handlers in
            DemoFakeRoomSocket(room: room, handlers: handlers)
        }
    }

    /// What the real API does after a send with `room_id`: the gift reaches everyone in the room
    /// (and counts for the round). The SDK leaves the sender's own gifts out of its events.
    func publish(sender: String, gift: Gift, quantity: Int, receiver: String) {
        deliver(sender: sender, gift: gift, quantity: quantity, receiver: receiver)
    }

    // MARK: - Used by the socket

    func welcomeFrame() -> String {
        if battle == nil {
            startRound()
        }
        var frame: [String: Any] = [
            "t": "welcome", "v": 1, "viewers": viewers, "gap": false, "replay": [Any](),
            "ttl": 3600, "now": nowMs(),
        ]
        if let battle = battle {
            frame["battle"] = json(battle)
        }
        return encode(frame)
    }

    func join(_ socket: DemoFakeRoomSocket) {
        sockets.append(socket)
    }

    func leave(_ socket: DemoFakeRoomSocket) {
        sockets.removeAll { $0 === socket }
        if sockets.isEmpty {
            roundTask?.cancel()
            scoresTask?.cancel()
            roundTask = nil
            scoresTask = nil
            battle = nil
        }
    }

    /// Only the first open socket drives the traffic, so a second viewer sees the same gifts.
    func drives(_ socket: DemoFakeRoomSocket) -> Bool {
        sockets.first === socket
    }

    /// Someone in the room sends a gift; 1 in 12 times it is a combo of five (250 ms apart).
    func othersGift(through socket: DemoFakeRoomSocket) {
        // Mostly everyday gifts (the cheaper 60%): luxury effects cover the stream, so they are rare.
        let byPrice = gifts.sorted { $0.price < $1.price }
        let cheap = Array(byPrice.prefix(max(1, Int((Double(gifts.count) * 0.6).rounded(.up)))))
        let pool = Int.random(in: 0..<10) == 0 ? gifts : cheap
        guard let sender = senders.randomElement(), let gift = pool.randomElement(), drives(socket) else {
            return
        }
        let receiver = receivers.randomElement() ?? "mia"
        if Double.random(in: 0..<1) < 1.0 / 12.0 {
            for i in 0..<5 {
                socket.later(i * 250) { [weak self] in
                    self?.deliver(sender: sender, gift: gift, quantity: 1, receiver: receiver)
                }
            }
        } else {
            deliver(sender: sender, gift: gift, quantity: Int.random(in: 1...2), receiver: receiver)
        }
    }

    /// The viewer count wanders a little, like a real room.
    func driftViewers() {
        viewers = max(1, viewers + Int.random(in: 0..<7) - 3)
        broadcast(["t": "viewers", "n": viewers])
    }

    // MARK: - Room and battle

    private func nowMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func deliver(sender: String, gift: Gift, quantity: Int, receiver: String) {
        nextId += 1
        var giftInfo: [String: Any] = ["id": gift.id, "name": gift.name, "price": gift.price]
        if let icon = gift.iconUrl {
            giftInfo["icon_url"] = icon
        }
        broadcast([
            "t": "gift", "id": nextId, "at": nowMs(), "tx": "gtx_demo\(nextTx)",
            "gift": giftInfo, "quantity": quantity,
            "sender": ["id": sender, "name": PixelData.displayName(sender)],
            "receiver": ["id": receiver],
        ])
        nextTx += 1
        count(receiver: receiver, gift: gift, quantity: quantity)
    }

    private func count(receiver: String, gift: Gift, quantity: Int) {
        let now = nowMs()
        guard var current = battle, now >= current.started, now < current.ends,
              let index = current.scores.firstIndex(where: { $0.id == receiver })
        else {
            return
        }
        current.scores[index].units += gift.price * quantity
        current.scores[index].gifts += quantity
        battle = current
        queueScores()
    }

    private func startRound() {
        roundNo += 1
        let now = nowMs()
        battle = RoomBattle(
            round: "demo_r\(roundNo)",
            started: now,
            ends: now + roundMs,
            scores: receivers.map { RoomScoreEntry(id: $0, units: 0, gifts: 0) }
        )
        queueScores()
        // No frame when the round ends (clients count down to `ends`); the next round starts later.
        roundTask?.cancel()
        let wait = UInt64(roundMs + breakMs) * 1_000_000
        roundTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            if Task.isCancelled {
                return
            }
            self?.startRound()
        }
    }

    /// Like the real room: a full snapshot, at most one per 250 ms, never one per gift.
    private func queueScores() {
        if scoresTask != nil {
            return
        }
        let wait = max(0, lastScoresAt + 250 - nowMs())
        scoresTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            if Task.isCancelled {
                return
            }
            self?.sendScores()
        }
    }

    private func sendScores() {
        scoresTask = nil
        lastScoresAt = nowMs()
        var frame: [String: Any] = ["t": "scores", "battle": NSNull()]
        if let battle = battle {
            frame["battle"] = json(battle)
        }
        broadcast(frame)
    }

    private func json(_ b: RoomBattle) -> [String: Any] {
        [
            "round": b.round, "started": b.started, "ends": b.ends,
            "scores": b.scores.map { ["id": $0.id, "units": $0.units, "gifts": $0.gifts] as [String: Any] },
        ]
    }

    private func broadcast(_ frame: [String: Any]) {
        let text = encode(frame)
        for socket in sockets {
            socket.push(text)
        }
    }

    private func encode(_ frame: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: frame), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

/// One "connection" to the pretend room: opens after 150 ms, answers `hello` with `welcome`.
@MainActor
final class DemoFakeRoomSocket: RoomSocket {
    private let room: DemoFakeRoom
    private let handlers: RoomSocketHandlers
    private var tasks: [Task<Void, Never>] = []
    private var isOpen = false
    private var closed = false

    init(room: DemoFakeRoom, handlers: RoomSocketHandlers) {
        self.room = room
        self.handlers = handlers
        later(150) { [weak self] in
            self?.isOpen = true
            self?.handlers.onOpen()
        }
    }

    func send(_ text: String) {
        guard isOpen, !closed else {
            return
        }
        if text == "ping" {
            push("pong")
            return
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            object["t"] as? String == "hello"
        else {
            return
        }
        push(room.welcomeFrame())
        room.join(self)
        scheduleGift()
        scheduleDrift()
    }

    func close(code: Int, reason: String) {
        if closed {
            return
        }
        closed = true
        for task in tasks {
            task.cancel()
        }
        tasks = []
        room.leave(self)
    }

    func push(_ text: String) {
        if !closed {
            handlers.onMessage(text)
        }
    }

    func later(_ ms: Int, _ fire: @escaping @MainActor () -> Void) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            if Task.isCancelled {
                return
            }
            guard let self = self, !self.closed else {
                return
            }
            fire()
        }
        tasks.append(task)
    }

    private func scheduleGift() {
        later(Int.random(in: 8_000...16_000)) { [weak self] in
            guard let self = self else {
                return
            }
            self.room.othersGift(through: self)
            self.scheduleGift()
        }
    }

    private func scheduleDrift() {
        later(5_000) { [weak self] in
            guard let self = self else {
                return
            }
            self.room.driftViewers()
            self.scheduleDrift()
        }
    }
}

/// A token shaped like the real one (`gs_ct_<claims>.<signature>`) so the SDK can read the user
/// from it (it never checks the signature: only the server does). Not a secret, not valid anywhere.
func demoRoomToken(_ user: String) -> String {
    let claims = "{\"v\":1,\"u\":\"\(user)\",\"n\":\"\(user)\"}"
    let b64 = Data(claims.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "gs_ct_\(b64).demo"
}
