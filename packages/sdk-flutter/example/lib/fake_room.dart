import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:giftingstack/giftingstack.dart';

/// A pretend rooms server for the demo: a [RoomSocket] that speaks the real
/// wire protocol (SPEC 17: `hello` -> `welcome`, then `gift` and `viewers`
/// frames), so the demo runs the SDK's real [GiftRoom] code without a rooms
/// Worker. Other people send gifts to the room every few seconds, now and then
/// five in a row (a combo), and a battle round between two hosts that the
/// gifts score into (the SDK's battle bar draws it). Not part of the SDK; a real app passes no `socket:`
/// and talks to `wss://rt.giftingstack.com`.
RoomSocketFactory fakeRoomSocketFactory({
  required List<Gift> Function() gifts,
  required List<String> senders,
  required String Function(String id) nameOf,
  Random? random,
  int minDelayMs = 8000,
  int maxDelayMs = 16000,
}) {
  final rand = random ?? Random();
  var nextId = DateTime.now().millisecondsSinceEpoch * 1000;
  var nextTx = 1;
  var viewers = 38 + rand.nextInt(20);

  Map<String, Object?> frame(
    String sender,
    Gift gift,
    int quantity,
    String receiver,
  ) =>
      <String, Object?>{
        't': 'gift',
        'id': ++nextId,
        'at': DateTime.now().millisecondsSinceEpoch,
        'tx': 'gtx_demo${nextTx++}',
        'gift': <String, Object?>{
          'id': gift.id,
          'name': gift.name,
          'price': gift.price,
          'icon_url': gift.iconUrl,
        },
        'quantity': quantity,
        'sender': <String, Object?>{'id': sender, 'name': nameOf(sender)},
        'receiver': <String, Object?>{'id': receiver},
      };

  return (url, protocols, handlers) => _FakeRoomSocket(
        handlers: handlers,
        rand: rand,
        minDelayMs: minDelayMs,
        maxDelayMs: maxDelayMs,
        gifts: gifts,
        senders: senders,
        frame: frame,
        viewers: () => viewers,
        setViewers: (n) => viewers = n,
      );
}

class _FakeRoomSocket implements RoomSocket {
  _FakeRoomSocket({
    required this.handlers,
    required this.rand,
    required this.minDelayMs,
    required this.maxDelayMs,
    required this.gifts,
    required this.senders,
    required this.frame,
    required this.viewers,
    required this.setViewers,
  }) {
    _later(150, () {
      _open = true;
      handlers.onOpen();
    });
  }

  final RoomSocketHandlers handlers;
  final Random rand;
  final int minDelayMs;
  final int maxDelayMs;
  final List<Gift> Function() gifts;
  final List<String> senders;
  final Map<String, Object?> Function(String, Gift, int, String) frame;
  final int Function() viewers;
  final void Function(int) setViewers;

  /// The two hosts of the battle bar, and the length of a round.
  static const List<String> receivers = <String>['mira', 'noor'];
  static const int roundMs = 45000;
  static const int breakMs = 5000;

  int _round = 1;
  int _started = DateTime.now().millisecondsSinceEpoch;
  final List<int> _units = <int>[0, 0];
  final List<int> _count = <int>[0, 0];

  final Set<Timer> _timers = <Timer>{};
  bool _open = false;
  bool _closed = false;

  @override
  void send(String data) {
    if (!_open || _closed) return;
    final Object? msg;
    try {
      msg = jsonDecode(data);
    } on FormatException {
      return;
    }
    final t = msg is Map<String, Object?> ? msg['t'] : null;
    if (t == 'hello') {
      _push(<String, Object?>{
        't': 'welcome',
        'v': 1,
        'viewers': viewers(),
        'gap': false,
        'replay': <Object?>[],
        'ttl': 3600,
        'now': DateTime.now().millisecondsSinceEpoch,
        'battle': _battle(),
      });
      _schedule();
      _drift();
      _later(roundMs, _endRound);
    } else if (t == 'ping') {
      _push(<String, Object?>{'t': 'pong'});
    }
  }

  @override
  void close(int code, String reason) {
    if (_closed) return;
    _closed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  Map<String, Object?> _battle() => <String, Object?>{
        'round': 'demo_r$_round',
        'started': _started,
        'ends': _started + roundMs,
        'scores': <Object?>[
          for (var i = 0; i < 2; i++)
            <String, Object?>{
              'id': receivers[i],
              'units': _units[i],
              'gifts': _count[i],
            },
        ],
      };

  /// Counts a gift into the round while it is open, then tells the room.
  void _score(int side, Gift gift, int quantity) {
    if (DateTime.now().millisecondsSinceEpoch >= _started + roundMs) return;
    _units[side] += gift.price * quantity;
    _count[side] += quantity;
    _push(<String, Object?>{'t': 'scores', 'battle': _battle()});
  }

  /// The round is over (the bar shows Final); a new one starts after a break.
  void _endRound() {
    _push(<String, Object?>{'t': 'scores', 'battle': _battle()});
    _later(breakMs, () {
      _round++;
      _started = DateTime.now().millisecondsSinceEpoch;
      _units.fillRange(0, 2, 0);
      _count.fillRange(0, 2, 0);
      _push(<String, Object?>{'t': 'scores', 'battle': _battle()});
      _later(roundMs, _endRound);
    });
  }

  void _push(Map<String, Object?> message) {
    if (!_closed) handlers.onMessage(jsonEncode(message));
  }

  void _later(int ms, void Function() fn) {
    late final Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (!_closed) fn();
    });
    _timers.add(t);
  }

  /// Someone in the room sends a gift; 1 in 12 times it is a combo of five.
  void _schedule() {
    _later(minDelayMs + rand.nextInt(maxDelayMs - minDelayMs + 1), () {
      final catalog = gifts();
      if (catalog.isNotEmpty && senders.isNotEmpty) {
        final sender = senders[rand.nextInt(senders.length)];
        // Mostly everyday gifts (the cheaper 60%): luxury effects cover the
        // stream, so they are rare.
        final byPrice = [...catalog]..sort((a, b) => a.price.compareTo(b.price));
        final cheap = byPrice.take(max(1, (catalog.length * 0.6).ceil())).toList();
        final from = rand.nextInt(10) == 0 ? catalog : cheap;
        final gift = from[rand.nextInt(from.length)];
        final side = rand.nextInt(2);
        final to = receivers[side];
        if (rand.nextInt(12) == 0) {
          for (var i = 0; i < 5; i++) {
            _later(i * 250, () {
              _push(frame(sender, gift, 1, to));
              _score(side, gift, 1);
            });
          }
        } else {
          final quantity = 1 + rand.nextInt(2);
          _push(frame(sender, gift, quantity, to));
          _score(side, gift, quantity);
        }
      }
      _schedule();
    });
  }

  /// The viewer count wanders a little, like a real room.
  void _drift() {
    _later(5000, () {
      setViewers(max(1, viewers() + rand.nextInt(7) - 3));
      _push(<String, Object?>{'t': 'viewers', 'n': viewers()});
      _drift();
    });
  }
}

/// A token shaped like the real one (`gs_ct_<claims>.<signature>`) so the SDK
/// can read the user from it (it never checks the signature: only the server
/// does). Not a secret, not valid anywhere.
String demoRoomToken(String user) {
  final claims = base64Url
      .encode(
        utf8.encode(
            jsonEncode(<String, Object?>{'v': 1, 'u': user, 'n': user})),
      )
      .replaceAll('=', '');
  return 'gs_ct_$claims.demo';
}
