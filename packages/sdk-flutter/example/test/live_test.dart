import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack_example/catalog.dart';
import 'package:giftingstack_example/chat.dart';
import 'package:giftingstack_example/fake_room.dart';

void main() {
  group('addGiftLine (comment column and chat combos)', () {
    test(
        'the same sender+gift+receiver adds up, even past comments, and '
        'moves to the bottom', () {
      final lines = <ChatLine>[];
      addGiftLine(lines,
          from: 'zoe',
          giftId: 'rose',
          name: 'Rose',
          to: 'mira',
          quantity: 1);
      lines.add(ChatLine.text(true, 'hi'));
      addGiftLine(lines,
          from: 'zoe',
          giftId: 'rose',
          name: 'Rose',
          to: 'mira',
          quantity: 2);
      expect(lines.length, 2);
      expect(lines.last.isGift, isTrue);
      expect(lines.last.count, 3);
      expect(lines.last.giftText((id) => id.toUpperCase()), 'ZOE sent Rose ×3');
      expect(lines.first.text, 'hi');
    });

    test('another sender, gift or receiver is its own line', () {
      final lines = <ChatLine>[];
      void add(String? from, String gift, String to) => addGiftLine(lines,
          from: from,
          giftId: gift,
          name: gift,
          to: to,
          quantity: 1);
      add('zoe', 'rose', 'mira');
      add('max', 'rose', 'mira');
      add('zoe', 'tulip', 'mira');
      add('zoe', 'rose', 'noor');
      add(null, 'rose', 'mira');
      expect(lines.length, 5);
      expect(lines.last.giftText(), 'You sent rose');
    });

    test('a thank-you in between does not cut a combo; 5 s later is new',
        () {
      final lines = <ChatLine>[];
      void send(int now) => addGiftLine(lines,
          giftId: 'rose',
          name: 'Rose',
          quantity: 1,
          now: now,
          moveDown: false);
      send(1000);
      send(2000);
      send(3000);
      expect(lines.length, 1);
      expect(lines.single.giftText(), 'You sent Rose ×3');
      lines.add(ChatLine.text(false, 'Thank you!!'));
      expect(
          addGiftLine(lines,
              giftId: 'rose',
              name: 'Rose',
              quantity: 0,
              now: 3500,
              moveDown: false),
          isTrue,
          reason: 'went on after its thank-you');
      send(7900);
      expect(lines.length, 2);
      expect(lines.first.giftText(), 'You sent Rose ×4');
      expect(lines.last.text, 'Thank you!!');
      send(12900);
      expect(lines.length, 3);
      expect(lines.last.giftText(), 'You sent Rose');
    });

    test('keepLast bounds the column', () {
      final lines = [for (var i = 0; i < 12; i++) ChatLine.text(true, '$i')];
      keepLast(lines);
      expect(lines.map((l) => l.text), ['7', '8', '9', '10', '11']);
      keepLast(lines, 2);
      expect(lines.length, 2);
    });
  });

  group('fake room', () {
    List<Map<String, Object?>> run({required bool battle}) {
      final frames = <Map<String, Object?>>[];
      fakeAsync((async) {
        final factory = fakeRoomSocketFactory(
          gifts: () => fallbackGifts,
          senders: const ['zoe', 'max'],
          nameOf: (id) => id,
          minDelayMs: 1000,
          maxDelayMs: 2000,
          battle: battle,
        );
        late RoomSocket socket;
        socket = factory(
          'wss://x',
          const ['gs.v1', 't'],
          RoomSocketHandlers(
            onOpen: () => socket.send(jsonEncode({'t': 'hello'})),
            onMessage: (d) => frames.add(jsonDecode(d) as Map<String, Object?>),
            onClose: (_, __) {},
          ),
        );
        async.elapse(const Duration(seconds: 100));
        socket.close(1000, 'bye');
      });
      return frames;
    }

    test('a room without a battle: no battle in welcome, no scores frames', () {
      final frames = run(battle: false);
      final welcome = frames.firstWhere((f) => f['t'] == 'welcome');
      expect(welcome.containsKey('battle'), isFalse);
      expect(frames.where((f) => f['t'] == 'scores'), isEmpty);
      final gifts = frames.where((f) => f['t'] == 'gift').toList();
      expect(gifts, isNotEmpty);
      for (final g in gifts) {
        expect((g['receiver']! as Map)['id'], 'mira');
      }
    });

    test('a battle room still has a round and scores', () {
      final frames = run(battle: true);
      final welcome = frames.firstWhere((f) => f['t'] == 'welcome');
      expect(welcome['battle'], isNotNull);
      expect(frames.where((f) => f['t'] == 'scores'), isNotEmpty);
    });
  });
}
