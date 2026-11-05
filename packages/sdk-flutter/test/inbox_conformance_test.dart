// Runs inbox.json (SPEC section 19) against the pure Dart core: the client call
// getInbox, inboxTimeLabel, inboxRows and inboxUnread. The format is the
// fixtures part of conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/client_runner.dart';
import 'support/fixtures.dart';

void main() {
  final f = readFixture('conformance/inbox.json');

  group('conformance: inbox.json client', () {
    for (final s in asList(f['client']).map(asMap)) {
      test(s['name']! as String, () => runClientScenario(s));
    }
  });

  group('conformance: inbox.json time', () {
    for (final c in asList(f['time']).map(asMap)) {
      test(c['name']! as String, () {
        expect(
          inboxTimeLabel(c['createdAtMs']! as int, c['nowMs']! as int),
          c['label'],
        );
      });
    }
  });

  group('conformance: inbox.json rows', () {
    for (final c in asList(f['rows']).map(asMap)) {
      test(c['name']! as String, () {
        final items = asList(c['items'])
            .map((e) => InboxItem.fromJson(asMap(e)))
            .toList();
        final names = asMap(c['names']).cast<String, String>();
        final rows = inboxRows(items, c['nowMs']! as int, names);
        final want = asList(c['expect']).map(asMap).toList();
        expect(rows.length, want.length);
        for (var i = 0; i < want.length; i++) {
          expect(rows[i].id, want[i]['id'], reason: 'row ${i + 1} id');
          expect(
            rows[i].senderName,
            want[i]['senderName'],
            reason: 'row ${i + 1} senderName',
          );
          expect(
            rows[i].giftName,
            want[i]['giftName'],
            reason: 'row ${i + 1} giftName',
          );
          expect(
            rows[i].quantity,
            want[i]['quantity'],
            reason: 'row ${i + 1} quantity',
          );
          expect(rows[i].time, want[i]['time'], reason: 'row ${i + 1} time');
        }
      });
    }
  });

  group('conformance: inbox.json unread', () {
    const gift = AwayGift(id: 'rose', name: 'Rose', price: 10);
    for (final c in asList(f['unread']).map(asMap)) {
      test(c['name']! as String, () {
        final items = <InboxItem>[
          for (final e in asList(c['items']).map(asMap))
            InboxItem(
              id: 'g',
              createdAt: e['created_at']! as String,
              sender: 'ayla',
              gift: gift,
              quantity: e['quantity']! as int,
              units: 10,
              status: e['status']! as String,
            ),
        ];
        expect(inboxUnread(items, c['lastSeenMs'] as int?), c['count']);
      });
    }
  });

  test('inbox.json has every section', () {
    expect(asList(f['client']).length, greaterThan(1));
    expect(asList(f['time']).length, greaterThan(5));
    expect(asList(f['rows']).length, greaterThan(1));
    expect(asList(f['unread']).length, greaterThan(1));
  });
}
