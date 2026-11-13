/// The receiver picker of a battle tray (SPEC section 21): one gift button,
/// the tray's "Send to" row picks the side. Pure: the widgets draw the row and
/// the tray notifier keeps `selected` and `last`. Port of
/// `packages/sdk-js/src/core/receivers.ts`.
library;

/// One side the viewer can send to.
class TrayReceiver {
  /// Creates a receiver.
  const TrayReceiver({
    required this.id,
    required this.name,
    this.color,
    this.avatarUrl,
  });

  /// Your user id of the receiver.
  final String id;

  /// The name shown under the avatar.
  final String name;

  /// The side colour (ring), `#rrggbb`. Default: the battle palette
  /// (`battleSidePalette`).
  final String? color;

  /// A picture; default the name's first letter on the side colour.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is TrayReceiver &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, name, color, avatarUrl);

  @override
  String toString() => 'TrayReceiver($id, $name)';
}

/// Which side the next gift goes to (SPEC 21.2): [selected] if it is in
/// [ids]; else [last] if in [ids]; else [fallback] if in [ids]; else the
/// first id. No ids: [fallback] (or null).
String? resolveReceiver(
  List<String> ids, {
  String? selected,
  String? last,
  String? fallback,
}) {
  if (ids.isEmpty) return fallback;
  for (final id in <String?>[selected, last, fallback]) {
    if (id != null && ids.contains(id)) return id;
  }
  return ids.first;
}

/// The default "Send to" label.
const String kSendToLabel = 'Send to';

/// The default label of a tappable battle side; `{name}` is replaced.
const String kPressSideLabel = 'Send {name} a gift';
