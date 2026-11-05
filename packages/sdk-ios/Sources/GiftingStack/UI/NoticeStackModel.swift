import Foundation

/// One line of the notice stack.
public struct NoticeLine: Sendable, Equatable, Identifiable {
    /// The notice's `id`: a line is identified by it.
    public let id: Int
    public var data: NoticeData
    /// False once the line started sliding out (its timer fired or it was hidden). The line is
    /// removed shortly after, when the slide-out is done.
    public var visible: Bool

    public init(data: NoticeData, visible: Bool = true) {
        self.id = data.id
        self.data = data
        self.visible = visible
    }
}

/// What `NoticeStackModel.show` did.
public enum NoticeShowResult: Sendable, Equatable {
    /// A line with this id was already shown; it was updated in place.
    case updated
    /// A new line was added at the bottom. `dropped` is the id of the oldest line that had to go.
    case added(dropped: Int?)
}

/// The bookkeeping of the gift notice stack (up to `maxNoticeLines` lines, newest at the bottom).
/// No SwiftUI and no timers: the controller owns the timers and calls `expire` and `removeHidden`.
public struct NoticeStackModel: Sendable, Equatable {
    public static let maxNoticeLines = 3

    /// Oldest first; the last one is the newest (drawn at the bottom).
    public private(set) var lines: [NoticeLine] = []

    public init() {}

    /// A call whose id is a visible line updates it in place. Otherwise (new id, or its line is
    /// already sliding out) a new line goes to the bottom; a fourth line drops the oldest.
    @discardableResult
    public mutating func show(_ data: NoticeData) -> NoticeShowResult {
        if let index = lines.firstIndex(where: { $0.id == data.id }) {
            if lines[index].visible {
                lines[index].data = data
                return .updated
            }
            lines.remove(at: index)
        }
        lines.append(NoticeLine(data: data))
        var dropped: Int?
        if lines.count > NoticeStackModel.maxNoticeLines {
            dropped = lines.removeFirst().id
        }
        return .added(dropped: dropped)
    }

    /// The line's timer fired: it starts sliding out. False when there is no visible such line.
    @discardableResult
    public mutating func expire(id: Int) -> Bool {
        guard let index = lines.firstIndex(where: { $0.id == id && $0.visible }) else {
            return false
        }
        lines[index].visible = false
        return true
    }

    /// Takes a line out once its slide-out is done. Only a line that is not visible goes, so a
    /// line that was shown again in the meantime stays.
    @discardableResult
    public mutating func removeHidden(id: Int) -> Bool {
        guard let index = lines.firstIndex(where: { $0.id == id && !$0.visible }) else {
            return false
        }
        lines.remove(at: index)
        return true
    }

    /// The core's hide: the newest visible line starts sliding out. Returns its id.
    @discardableResult
    public mutating func hideNewest() -> Int? {
        guard let index = lines.lastIndex(where: { $0.visible }) else {
            return nil
        }
        lines[index].visible = false
        return lines[index].id
    }

    /// Removes every line.
    public mutating func clear() {
        lines = []
    }
}
