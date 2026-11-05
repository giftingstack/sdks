import Foundation

/// A display name (and picture) for an external user id. External ids are rarely display names.
public struct GiftUserInfo: Sendable, Equatable, Hashable {
    public var name: String
    public var avatarUrl: String?

    public init(name: String, avatarUrl: String? = nil) {
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

/// Looks up display names for ids (your own user service). Ids it does not answer keep the id
/// itself as the name; a deleted sender (nil id) is `labels.someone`.
public typealias GiftResolveUsers = ([String]) async throws -> [String: GiftUserInfo]

/// The first letter of a name, upper case: the avatar's initial.
public func giftInitial(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else {
        return "?"
    }
    return String(first).uppercased()
}

/// "While you were away" counts: `"37 gifts"`, `"1 person"`, `"2,000+ gifts"` when truncated.
public func awayCountText(_ n: Int, one: String, other: String, truncated: Bool) -> String {
    let text = groupThousands(n) + (truncated ? "+" : "")
    return fillLabel(n == 1 && !truncated ? one : other, ["n": text])
}

/// Who won the race between a lookup and its time limit.
@MainActor
private final class ResolveRace {
    var finished = false
}

/// Calls `resolve(ids)` and returns its answer if it comes within `waitMs`; nil after the wait
/// or on failure (the failure goes to `onError`). A late answer is dropped.
@MainActor
func resolveUsersWithin(
    _ ids: [String],
    waitMs: Int,
    resolve: @escaping GiftResolveUsers,
    onError: ((GiftingError) -> Void)?
) async -> [String: GiftUserInfo]? {
    let race = ResolveRace()
    return await withCheckedContinuation { (continuation: CheckedContinuation<[String: GiftUserInfo]?, Never>) in
        Task { @MainActor in
            var found: [String: GiftUserInfo]?
            do {
                found = try await resolve(ids)
            } catch {
                onError?(asGiftingError(error))
            }
            if !race.finished {
                race.finished = true
                continuation.resume(returning: found)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, waitMs)) * 1_000_000)
            if !race.finished {
                race.finished = true
                continuation.resume(returning: nil)
            }
        }
    }
}
