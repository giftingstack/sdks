// GiftRoom (the Flutter wrapper of RoomClient): a fake socket speaking the
// real wire protocol, the real effect layer, the app lifecycle, `roomId` on
// the send path, and the real dart:io transport against a local WebSocket
// server. The state machine itself is run by rooms_conformance_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';
import 'package:giftingstack/src/ui/notice.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'support/ui_harness.dart';

/// A token whose claim `u` is [user] (not signed: the client never checks it).
String tokenFor(String user) {
  final claims = base64Url
      .encode(utf8.encode(jsonEncode(<String, Object?>{'u': user})))
      .replaceAll('=', '');
  return 'gs_ct_$claims.AAAA';
}

class FakeWire implements RoomSocket {
  FakeWire(this.url, this.protocols, this.handlers);

  final String url;
  final List<String> protocols;
  final RoomSocketHandlers handlers;
  final List<String> sent = <String>[];
  int? closedWith;

  @override
  void send(String data) => sent.add(data);

  @override
  void close(int code, String reason) => closedWith = code;

  void welcome({int viewers = 3, int now = 1000, List<Object?>? replay}) =>
      handlers.onMessage(
        jsonEncode(<String, Object?>{
          't': 'welcome',
          'viewers': viewers,
          'gap': false,
          'replay': replay ?? <Object?>[],
          'ttl': 3600,
          'now': now,
        }),
      );
}

Map<String, Object?> giftFrame(
  int id,
  String tx, {
  String sender = 'ayla',
  int price = 10,
  int at = 1000,
}) =>
    <String, Object?>{
      't': 'gift',
      'id': id,
      'at': at,
      'tx': tx,
      'gift': <String, Object?>{
        'id': 'rose',
        'name': 'Rose',
        'price': price,
        'icon_url': null,
      },
      'quantity': 2,
      'sender': <String, Object?>{'id': sender, 'name': 'Ayla'},
      'receiver': <String, Object?>{'id': 'host'},
    };

void main() {
  late List<FakeWire> wires;
  late List<bool> tokenAsks;

  RoomSocketFactory factory() => (url, protocols, handlers) {
        final w = FakeWire(url, List<String>.of(protocols), handlers);
        wires.add(w);
        return w;
      };

  Future<String> getToken({required bool forceRefresh}) async {
    tokenAsks.add(forceRefresh);
    return tokenFor('me');
  }

  setUp(() {
    wires = <FakeWire>[];
    tokenAsks = <bool>[];
  });

  Future<GiftRoom> join(
    WidgetTester tester, {
    GiftEffectController? effects,
    void Function(RoomGiftEvent)? onEvent,
  }) async {
    final room = GiftRoom(
      room: 'live_1',
      getToken: getToken,
      effects: effects,
      onEvent: onEvent,
      socket: factory(),
      // No app pings: the fake server would have to answer them.
      heartbeatMs: 0,
    );
    await tester.pump();
    expect(wires, hasLength(1));
    wires.single.handlers.onOpen();
    await tester.pump();
    wires.single.welcome();
    await tester.pump();
    return room;
  }

  group('GiftRoom', () {
    testWidgets(
        'joins with gs.v1 + token, says hello, plays room gifts in the '
        'effect layer, skips the own gift', (tester) async {
      final images = ControlledImages(autoLoad: true);
      await images.init(tester);
      final fx = GiftEffectController();
      await tester.pumpWidget(layerApp(controller: fx, images: images));
      final seen = <String>[];
      final room = await join(
        tester,
        effects: fx,
        onEvent: (e) => seen.add(e.tx),
      );
      final wire = wires.single;
      expect(wire.url, 'wss://rt.giftingstack.com/v1/rooms/live_1');
      expect(wire.protocols, <String>['gs.v1', tokenFor('me')]);
      expect(wire.sent.first, '{"t":"hello","v":1,"last":null}');
      expect(room.status, RoomStatus.open);
      expect(room.viewers, 3);

      wire.handlers.onMessage(jsonEncode(giftFrame(1, 'gtx_a')));
      await tester.pump();
      expect(find.byType(EffectItem), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      final notice = tester.widget<GiftNotice>(find.byType(GiftNotice));
      expect(notice.data.senderName, 'Ayla');
      expect(notice.data.count, 2);

      // The token's user is "me": their gift already played at the tap.
      wire.handlers
          .onMessage(jsonEncode(giftFrame(2, 'gtx_own', sender: 'me')));
      await tester.pump();
      expect(seen, <String>['gtx_a']);

      wire.handlers.onMessage('{"t":"viewers","n":9}');
      expect(room.viewers, 9);
      room.dispose();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('notifies listeners on state changes, never after dispose',
        (tester) async {
      var n = 0;
      final room = GiftRoom(
        room: 'live_1',
        getToken: getToken,
        socket: factory(),
      );
      room.addListener(() => n++);
      await tester.pump();
      final before = n;
      wires.single.handlers.onOpen();
      wires.single.welcome();
      expect(n, greaterThan(before));
      room.dispose();
      expect(wires.single.closedWith, 1000);
      expect(room.state.status, RoomStatus.closed);
      expect(room.state.code, 1000);
    });

    testWidgets(
        'background: connected for 60 s, then closed; foreground '
        'resumes with the last event id', (tester) async {
      final room = await join(tester);
      wires.single.handlers.onMessage(jsonEncode(giftFrame(7, 'gtx_a')));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 59));
      expect(room.status, RoomStatus.open);
      expect(wires.single.closedWith, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(room.status, RoomStatus.paused);
      expect(wires.single.closedWith, 1000);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(wires, hasLength(2));
      wires.last.handlers.onOpen();
      expect(wires.last.sent.single, '{"t":"hello","v":1,"last":7}');
      wires.last.welcome(replay: <Object?>[giftFrame(7, 'gtx_a')]);
      await tester.pump();
      expect(room.status, RoomStatus.open);
      room.dispose();
    });

    testWidgets('back within 60 s: the socket was never closed',
        (tester) async {
      final room = await join(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 120));
      expect(room.status, RoomStatus.open);
      expect(wires, hasLength(1));
      expect(wires.single.closedWith, isNull);
      room.dispose();
    });

    testWidgets(
        'a dropped socket reconnects by itself; the app lifecycle is '
        'not needed', (tester) async {
      final room = await join(tester);
      wires.single.handlers.onClose(1006, '');
      await tester.pump();
      expect(room.status, RoomStatus.reconnecting);
      await tester.pump(const Duration(seconds: 6));
      expect(wires, hasLength(2));
      room.dispose();
    });

    testWidgets('a bad room id closes at once and opens nothing',
        (tester) async {
      final room = GiftRoom(
        room: 'no spaces',
        getToken: getToken,
        socket: factory(),
      );
      await tester.pump();
      expect(room.status, RoomStatus.closed);
      expect(room.state.code, 4004);
      expect(wires, isEmpty);
      expect(tokenAsks, isEmpty);
      room.dispose();
    });

    testWidgets('battle: holder exposes the round and view, notifies, onBattle',
        (tester) async {
      final seen = <RoomBattle?>[];
      final room = GiftRoom(
        room: 'live_1',
        getToken: getToken,
        socket: factory(),
        heartbeatMs: 0,
        onBattle: seen.add,
      );
      await tester.pump();
      wires.single.handlers.onOpen();
      await tester.pump();
      var notified = 0;
      room.addListener(() => notified++);
      wires.single.welcome();
      await tester.pump();
      expect(room.battle, isNull);
      expect(room.battleView, isNull);
      final before = notified;
      wires.single.handlers.onMessage(jsonEncode(<String, Object?>{
        't': 'scores',
        'battle': <String, Object?>{
          'round': 'r1',
          'started': 0,
          'ends': 100000000000000,
          'scores': <Object?>[
            <String, Object?>{'id': 'ava', 'units': 10, 'gifts': 1},
            <String, Object?>{'id': 'mateo', 'units': 30, 'gifts': 2},
          ],
        },
      }));
      expect(notified, greaterThan(before));
      expect(room.battle!.round, 'r1');
      expect(room.battleView!.leader, 'mateo');
      expect(room.battleView!.sides.map((x) => x.share), <double>[0.25, 0.75]);
      wires.single.handlers.onMessage(
        jsonEncode(<String, Object?>{'t': 'scores', 'battle': null}),
      );
      expect(room.battle, isNull);
      expect(seen.map((b) => b?.round), <String?>['r1', null]);
      room.dispose();
    });
  });

  group('roomId on the send path', () {
    test('GiftingClient sends room_id only when given', () async {
      final bodies = <Map<String, Object?>>[];
      final client = GiftingClient(
        getToken: ({required bool forceRefresh}) async => 'tok',
        httpClient: http_testing.MockClient((http.Request req) async {
          bodies.add(jsonDecode(req.body) as Map<String, Object?>);
          return http.Response(
            jsonEncode(<String, Object?>{
              'id': 'gtx_1',
              'sender': 'ayla',
              'receiver': 'mert',
              'gift': <String, Object?>{'id': 'rose', 'name': 'Rose'},
              'quantity': 1,
              'unit_price': 10,
              'total': 10,
              'status': 'completed',
              'created_at': '2026-10-12T00:00:00Z',
              'sender_balance_after': 90,
            }),
            201,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await client.sendGift(
        const SendGiftInput(receiver: 'mert', giftId: 'rose', roomId: 'live_1'),
      );
      await client.sendGift(
        const SendGiftInput(receiver: 'mert', giftId: 'rose'),
      );
      expect(bodies[0]['room_id'], 'live_1');
      expect(bodies[1].containsKey('room_id'), isFalse);
    });

    testWidgets('GiftTrayNotifier(roomId) names the room in every send',
        (tester) async {
      final api = _RoomApi();
      final tray = GiftTrayNotifier(
        client: api,
        receiver: 'host',
        roomId: 'live_1',
        reference: 'post_1',
      );
      api.gifts.complete(const <Gift>[
        Gift(id: 'rose', name: 'Rose', price: 10, sortOrder: 1),
      ]);
      api.me.complete(const Me(user: 'ayla', balance: 100));
      await tester.pump();
      unawaited(tray.send(tray.gifts.single));
      await tester.pump();
      expect(api.lastSend?.roomId, 'live_1');
      expect(api.lastSend?.reference, 'post_1');
      expect(api.lastSend?.receiver, 'host');
      tray.dispose();
    });
  });

  group('dart:io transport', () {
    test(
        'a real local WebSocket server: subprotocols, hello, welcome, gift, '
        'a final close code', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requested = Completer<List<String>>();
      final hello = Completer<String>();
      unawaited(
        server.forEach((HttpRequest req) async {
          requested.complete(
            req.headers['sec-websocket-protocol']!
                .expand((String h) => h.split(',').map((s) => s.trim()))
                .toList(),
          );
          final ws = await WebSocketTransformer.upgrade(
            req,
            protocolSelector: (List<String> p) => p.first,
          );
          ws.listen((Object? data) {
            if (data is String && !hello.isCompleted) {
              hello.complete(data);
              ws
                ..add(
                  jsonEncode(<String, Object?>{
                    't': 'welcome',
                    'viewers': 2,
                    'gap': false,
                    'replay': <Object?>[],
                    'ttl': 3600,
                    'now': DateTime.now().millisecondsSinceEpoch,
                  }),
                )
                ..add(
                  jsonEncode(
                    giftFrame(
                      5,
                      'gtx_real',
                      at: DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                );
              Timer(
                const Duration(milliseconds: 100),
                () => ws.close(4003, 'forbidden'),
              );
            }
          });
        }),
      );

      final events = <RoomGiftEvent>[];
      final room = GiftRoom(
        room: 'live_1',
        url: 'ws://127.0.0.1:${server.port}/',
        getToken: getToken,
        onEvent: events.add,
        observeLifecycle: false,
      );
      addTearDown(room.dispose);
      final done = Completer<void>();
      room.addListener(() {
        if (room.status == RoomStatus.closed && !done.isCompleted) {
          done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 10));

      expect(await requested.future, <String>['gs.v1', tokenFor('me')]);
      expect(await hello.future, '{"t":"hello","v":1,"last":null}');
      expect(events.map((e) => e.tx), <String>['gtx_real']);
      expect(events.single.quantity, 2);
      expect(room.viewers, 2);
      // 4003 is final: no reconnect.
      expect(room.state.code, 4003);
      expect(room.state.reason, 'forbidden');
    });

    test('connection refused is a close with 1006 (then a retry is planned)',
        () async {
      final closes = <int>[];
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);
      final gotClose = Completer<void>();
      final sock = ioRoomSocketFactory()(
        'ws://127.0.0.1:$port/',
        <String>['gs.v1', 'x'],
        RoomSocketHandlers(
          onOpen: () => closes.add(-1),
          onMessage: (_) {},
          onClose: (code, reason) {
            closes.add(code);
            gotClose.complete();
          },
        ),
      );
      await gotClose.future.timeout(const Duration(seconds: 10));
      expect(closes, <int>[1006]);
      sock.close(1000, 'client');
      expect(closes, <int>[1006], reason: 'reported exactly once');
    });
  });
}

class _RoomApi extends _FakeApiBase {
  final Completer<List<Gift>> gifts = Completer<List<Gift>>();
  final Completer<Me> me = Completer<Me>();
  SendGiftInput? lastSend;

  @override
  Future<List<Gift>> getGifts() => gifts.future;

  @override
  Future<Me> getMe() => me.future;

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) {
    lastSend = input;
    return Completer<GiftTransaction>().future;
  }
}

/// Everything else a tray never calls.
abstract class _FakeApiBase implements GiftingClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
