import 'dart:async';
import 'dart:math';

import 'package:giftingstack/giftingstack.dart';

/// Gifts that arrive by themselves, like a live app: every 20-40 s, mostly
/// small, now and then medium, rarely large. Off by default (`liveFeed` in
/// main.dart): the developer menu plays them instead. Demo only, not part of
/// the SDK.
enum Tier { small, medium, large }

/// One pretend incoming gift.
class Incoming {
  /// Creates one.
  const Incoming(this.gift, this.sender, this.quantity);

  /// The gift.
  final Gift gift;

  /// The sender's external id.
  final String sender;

  /// How many.
  final int quantity;
}

/// Same default limits as the effect layer: medium from 100, large from 10 000.
Tier tierOf(int price) => price >= 10000
    ? Tier.large
    : price >= 100
        ? Tier.medium
        : Tier.small;

/// 78 % small, 19 % medium, 3 % large.
Tier rollTier(double r) => r < 0.78
    ? Tier.small
    : r < 0.97
        ? Tier.medium
        : Tier.large;

/// A random delay between 20 and 40 s.
Duration nextDelay(Random rand) =>
    Duration(milliseconds: 20000 + rand.nextInt(20000));

/// A random gift of the rolled tier (the nearest tier that has gifts when it
/// is empty), from a random sender in [senders].
Incoming pickIncoming(List<Gift> gifts, List<String> senders, Random rand) {
  final want = rollTier(rand.nextDouble());
  final tiers = [...Tier.values]..sort(
      (a, b) =>
          (a.index - want.index).abs().compareTo((b.index - want.index).abs()),
    );
  final tier = tiers.firstWhere(
    (t) => gifts.any((g) => tierOf(g.price) == t),
    orElse: () => want,
  );
  final pool = gifts.where((g) => tierOf(g.price) == tier).toList();
  final from = pool.isEmpty ? gifts : pool;
  final gift = from[rand.nextInt(from.length)];
  final sender = senders[rand.nextInt(senders.length)];
  final quantity = switch (tierOf(gift.price)) {
    Tier.small => 1 + rand.nextInt(3),
    Tier.medium => 1 + rand.nextInt(2),
    Tier.large => 1,
  };
  return Incoming(gift, sender, quantity);
}

/// Starts the stream; call `cancel()` on the result to end it. The first gift
/// comes after one random delay. [gifts] is read at each tick.
Timer startIncoming({
  required List<Gift> Function() gifts,
  required List<String> senders,
  required void Function(Incoming incoming) onGift,
  Random? random,
}) {
  final rand = random ?? Random();
  late Timer timer;
  Timer arm() => timer = Timer(nextDelay(rand), () {
        final list = gifts();
        if (list.isNotEmpty && senders.isNotEmpty) {
          onGift(pickIncoming(list, senders, rand));
        }
        arm();
      });
  arm();
  // The caller cancels the first timer; each tick re-arms a new one, so wrap.
  return _Chain(() => timer);
}

class _Chain implements Timer {
  _Chain(this._current);

  final Timer Function() _current;

  @override
  void cancel() => _current().cancel();

  @override
  bool get isActive => _current().isActive;

  @override
  int get tick => _current().tick;
}
