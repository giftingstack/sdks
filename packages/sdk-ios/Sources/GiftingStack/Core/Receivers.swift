import Foundation

// The receiver picker of a battle tray (spec section 21): one gift button, the tray's "Send to" row
// picks the side. Pure: `GiftTray` draws the row and `GiftTrayModel` keeps `selected` and `last`.
// Port of `packages/sdk-js/src/core/receivers.ts`; fixture `receivers.json`.

/// One side the viewer can send to (`GiftTrayModel.receivers`).
public struct TrayReceiver: Sendable, Equatable, Hashable, Identifiable {
    /// Your user id of the receiver.
    public var id: String
    /// The name shown under the avatar.
    public var name: String
    /// The side colour (ring), `#rgb` / `#rrggbb`. nil: the battle palette (`battleSidePalette`, SPEC 18.7).
    public var color: String?
    /// A picture; nil: the name's first letter on the side colour.
    public var avatarUrl: String?

    public init(id: String, name: String, color: String? = nil, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.avatarUrl = avatarUrl
    }
}

/// Which side the next gift goes to (spec 21.2): `selected` if it is in `ids`; else `last` if in `ids`;
/// else `fallback` if in `ids`; else the first id. No ids: `fallback` (or nil).
///   - ids: the receivers' ids, in order.
///   - selected: the pick so far (a tap on a side, or `selectReceiver`).
///   - last: the receiver of this tray's last successful send.
///   - fallback: the plain `receiver` of the tray.
public func resolveReceiver(
    ids: [String],
    selected: String? = nil,
    last: String? = nil,
    fallback: String? = nil
) -> String? {
    guard let first = ids.first else {
        return fallback
    }
    for candidate in [selected, last, fallback] {
        if let id = candidate, ids.contains(id) {
            return id
        }
    }
    return first
}

/// The default label of the tray's "Send to" row (`SEND_TO_LABEL`).
public let defaultSendToLabel = "Send to"

/// The default label of a tappable battle side; `{name}` is replaced (`PRESS_SIDE_LABEL`).
public let defaultPressSideLabel = "Send {name} a gift"
