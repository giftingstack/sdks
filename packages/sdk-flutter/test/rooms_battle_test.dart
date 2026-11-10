// Battle scores on the session (SPEC 18.6): RoomClient keeps the round from
// welcome and scores frames, the server clock offset, callbacks that throw.
// The wire parsing and battleView are run by rooms_conformance_test.dart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fake_clock.dart';

Map<String, Object?> battleJson(int ava, int mateo, [String round = 'r1']) =>
    <String, Object?>{
      'round': round,
      'started': 1000,
      'ends': 61000,
      'scores': <Object?>[
        <String, Object?>{'id': 'ava', 'units': ava, 'gifts': ava > 0 ? 1 : 0},
        <String, Object?>{
          'id': 'mateo',
          'units': mateo,
          'gifts': mateo > 0 ? 1 : 0,
        },
      ],
    };

RoomBattle battleOf(int ava, int mateo, [String round = 'r1']) =>
    (parseRoomFrame(jsonEncode(<String, Object?>{
      't': 'scores',
      'battle': battleJson(ava, mateo, round),
    }))! as RoomScoresMessage)
        .battle!;

class _Wire implements RoomSocket {
  @override
  void send(String data) {}

  @override
  void close(int code, String reason) {}
}

class _Session {
  _Session({
    void Function()? throwOnBattle,
    String? Function(String)? resolveName,
    List<String>? sideColors,
    void Function(RoomGiftEvent)? onEvent,
  }) {
    room = RoomClient(
      RoomClientOptions(
        room: 'live_1',
        getToken: ({required bool forceRefresh}) async => 'tok',
        socket: (url, protocols, handlers) {
          sockets.add(handlers);
          return _Wire();
        },
        heartbeatMs: 0,
        onBattle: calls.add,
        resolveName: resolveName,
        sideColors: sideColors,
        onEvent: onEvent,
        now: () => clock.now,
        setTimeout: clock.setTimeout,
        clearTimeout: clock.clearTimeout,
      ),
    );
    if (throwOnBattle != null) room.subscribeBattle(throwOnBattle);
  }

  final FakeRoomClock clock = FakeRoomClock();
  final List<RoomSocketHandlers> sockets = <RoomSocketHandlers>[];
  final List<RoomBattle?> calls = <RoomBattle?>[];
  late final RoomClient room;

  RoomSocketHandlers get socket => sockets.last;

  void send(Object? frame) => socket.onMessage(jsonEncode(frame));

  void welcome({int now = 1000, Object? battle}) => send(<String, Object?>{
        't': 'welcome',
        'viewers': 3,
        'gap': false,
        'replay': <Object?>[],
        'ttl': 3600,
        'now': now,
        if (battle != null) 'battle': battle,
      });

  Future<void> startOpen() async {
    room.start();
    await Future<void>.delayed(Duration.zero);
    socket.onOpen();
  }
}

Map<String, Object?> giftFrame(int at, String to) => <String, Object?>{
      't': 'gift',
      'id': at,
      'at': at,
      'tx': 'gtx_$at',
      'gift': <String, Object?>{'id': 'rose', 'name': 'Rose', 'price': 10},
      'quantity': 1,
      'sender': <String, Object?>{'id': 'u1', 'name': 'Ava'},
      'receiver': <String, Object?>{'id': to},
    };

void main() {
  test('a gift of the round gets the receiver with the room names and colours',
      () async {
    final events = <RoomGiftEvent>[];
    final s = _Session(
      onEvent: events.add,
      resolveName: (id) => id == 'mateo' ? 'Mateo' : null,
      sideColors: <String>['#ff3366', '#00aa88'],
    );
    await s.startOpen();
    expect(s.room.receiverFor('ava'), isNull);
    s.welcome(now: 5000, battle: battleJson(0, 0));
    s.send(giftFrame(5000, 'mateo'));
    s.send(giftFrame(5001, 'ava'));
    s.send(giftFrame(5002, 'viewer'));
    expect(events.map((e) => e.receiver?.toJson()), <Object?>[
      <String, Object?>{'name': 'Mateo', 'side': 1, 'color': '#00aa88'},
      <String, Object?>{'name': 'ava', 'side': 0, 'color': '#ff3366'},
      null,
    ]);
    // The user's own gift: the same answer for "now".
    expect(s.room.receiverFor('mateo')!.name, 'Mateo');
    expect(s.room.receiverFor('viewer'), isNull);
    s.send(<String, Object?>{'t': 'scores', 'battle': null});
    s.send(giftFrame(5003, 'mateo'));
    expect(events[3].receiver, isNull);
    expect(s.room.receiverFor('mateo'), isNull);
  });

  test(
      'takes the round from welcome, then each scores frame; null when removed',
      () async {
    final s = _Session();
    final changes = <RoomBattle?>[];
    s.room.subscribeBattle(() => changes.add(s.room.getBattle()));
    await s.startOpen();
    expect(s.room.getBattle(), isNull);
    expect(s.room.serverNow(), isNull);
    // Local clock 100, server clock 31,000: offset 30,900.
    s.clock.now = 100;
    s.welcome(now: 31000, battle: battleJson(0, 0));
    expect(s.room.getBattle(), battleOf(0, 0));
    expect(s.room.serverNow(), 31000);
    s.send(<String, Object?>{'t': 'scores', 'battle': battleJson(300, 100)});
    s.clock.now = 10100;
    final v = s.room.getBattleView()!;
    expect(v.open, isTrue);
    expect(v.remainingMs, 20000);
    expect(v.total, 400);
    expect(v.leader, 'ava');
    s.send(<String, Object?>{'t': 'scores', 'battle': null});
    expect(s.room.getBattle(), isNull);
    expect(s.room.getBattleView(), isNull);
    expect(changes, <RoomBattle?>[battleOf(0, 0), battleOf(300, 100), null]);
    expect(s.calls, changes);
  });

  test(
      'ignores malformed scores frames; keeps the round across a reconnect '
      'until the next welcome', () async {
    final s = _Session();
    await s.startOpen();
    s.welcome(battle: battleJson(5, 0));
    s.send(<String, Object?>{
      't': 'scores',
      'battle': <String, Object?>{'round': ''},
    });
    s.send(<String, Object?>{'t': 'scores'});
    expect(s.room.getBattle(), battleOf(5, 0));
    s.socket.onClose(1006, '');
    expect(s.room.state.status, RoomStatus.reconnecting);
    expect(s.room.getBattle(), battleOf(5, 0));
    s.room.reconnectNow();
    await Future<void>.delayed(Duration.zero);
    s.socket.onOpen();
    // The new welcome has no round: it was removed while we were away.
    s.welcome();
    expect(s.room.getBattle(), isNull);
  });

  test('a scores frame before the welcome is ignored', () async {
    final s = _Session();
    s.room.start();
    await Future<void>.delayed(Duration.zero);
    s.socket.onOpen();
    s.send(<String, Object?>{'t': 'scores', 'battle': battleJson(1, 2)});
    expect(s.room.getBattle(), isNull);
  });

  test('app callbacks that throw never break the room', () async {
    final s = _Session(throwOnBattle: () => throw StateError('app bug'));
    await s.startOpen();
    s.welcome(battle: battleJson(1, 2));
    expect(s.room.state.status, RoomStatus.open);
    expect(s.room.getBattle(), battleOf(1, 2));
  });
}
