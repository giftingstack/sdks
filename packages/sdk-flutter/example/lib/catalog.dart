import 'dart:async';
import 'dart:convert';

import 'package:giftingstack/giftingstack.dart';
import 'package:http/http.dart' as http;

/// The gift pictures come from the public library host, like in a real app.
const String assetsHost = 'https://assets.giftingstack.com';

/// Small picture (256 px).
String iconUrl(String id) => '$assetsHost/gifts/$id/256.webp';

/// Big picture (512 px).
String artUrl(String id) => '$assetsHost/gifts/$id/512.webp';

/// The small list used when the live library cannot be loaded (offline, the
/// host is down): twelve gifts from cheap to grand.
const List<(String id, String name, int price)> _fallback = [
  ('pink-tulip', 'Pink tulip', 10),
  ('heart-latte', 'Heart latte', 20),
  ('party-popper', 'Party popper', 25),
  ('bear-boba', 'Bear boba', 45),
  ('cool-star', 'Cool star', 100),
  ('magic-hat', 'Magic hat', 350),
  ('rainbow-gem', 'Rainbow gem', 500),
  ('treasure-chest', 'Treasure chest', 1000),
  ('heart-box', 'Heart box', 2000),
  ('crystal-pegasus', 'Crystal pegasus', 18000),
  ('golden-griffin', 'Golden griffin', 22000),
  ('sun-dragon', 'Sun dragon', 40000),
];

/// The gifts as the API would return them, when the library cannot be loaded.
final List<Gift> fallbackGifts = [
  for (final (i, g) in _fallback.indexed)
    Gift(
      id: g.$1,
      name: g.$2,
      price: g.$3,
      iconUrl: iconUrl(g.$1),
      animationUrl: artUrl(g.$1),
      sortOrder: i,
    ),
];

/// Twelve chosen gifts that always come first (as the web demo).
const List<String> pick = [
  'pink-tulip',
  'heart-latte',
  'bear-boba',
  'cool-star',
  'magic-hat',
  'rainbow-gem',
  'treasure-chest',
  'golden-griffin',
  'phoenix',
  'sun-dragon',
  'heart-turkey',
  'star-whale',
];

/// How many more gifts follow the chosen twelve.
const int _more = 78;

/// One gift of `library.json`.
class LibraryGift {
  /// Creates a library gift.
  const LibraryGift(this.id, this.name, this.price);

  /// The id, also the folder of its pictures.
  final String id;

  /// The display name.
  final String name;

  /// `suggested_price`.
  final int price;
}

/// The selection of `packages/sdk-js/demo/shared.ts` `loadGifts`: the twelve
/// chosen gifts, then others spread from cheap to grand (about ninety in all),
/// so the expanded sheet has plenty to scroll. The 108 country hearts share
/// one price: only one of them is kept.
List<Gift> selectGifts(List<LibraryGift> library) {
  final others = library
      .where(
        (g) =>
            !pick.contains(g.id) &&
            (!g.id.startsWith('heart-') || g.id == 'heart-turkey'),
      )
      .toList()
    ..sort((a, b) => a.price.compareTo(b.price));
  final count = others.length < _more ? others.length : _more;
  final step = others.length / _more;
  final more = [for (var i = 0; i < count; i++) others[(i * step).floor()].id];
  final out = <Gift>[];
  for (final id in [...pick, ...more]) {
    final g = library.where((x) => x.id == id).firstOrNull;
    if (g == null) continue;
    out.add(
      Gift(
        id: id,
        name: g.name,
        price: g.price,
        iconUrl: iconUrl(id),
        animationUrl: artUrl(id),
        sortOrder: out.length,
      ),
    );
  }
  return out;
}

/// Reads `library.json` text into [LibraryGift]s; null when it is not usable.
List<LibraryGift>? parseLibrary(String body) {
  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final gifts = json['gifts'] as List<dynamic>;
    return [
      for (final g in gifts.cast<Map<String, dynamic>>())
        LibraryGift(
          g['id'] as String,
          g['name'] as String,
          (g['suggested_price'] as num).toInt(),
        ),
    ];
  } on Object {
    return null;
  }
}

/// Loads the live library (`$assetsHost/library.json`) and selects about ninety
/// gifts; on any problem the small [fallbackGifts] list. [client] is for tests.
Future<List<Gift>> loadGifts({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse('$assetsHost/library.json'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return fallbackGifts;
    final library = parseLibrary(utf8.decode(res.bodyBytes));
    if (library == null) return fallbackGifts;
    final gifts = selectGifts(library);
    return gifts.length >= pick.length ~/ 2 ? gifts : fallbackGifts;
  } on Object {
    return fallbackGifts;
  } finally {
    if (client == null) c.close();
  }
}
