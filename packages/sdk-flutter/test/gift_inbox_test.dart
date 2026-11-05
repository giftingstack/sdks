// Widget tests of GiftInbox (SPEC 19.3): every state, paging, names, the
// accessibility labels and reduced motion. The pure rules (time label, rows,
// unread) are in inbox_conformance_test.dart (inbox.json). What these cannot
// judge (how it looks and feels on a phone) needs a device.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/component_harness.dart';
import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const int _nowMs = 1793613600000;

const Key _list = ValueKey<String>('gift-inbox-list');
const Key _skeleton = ValueKey<String>('gift-inbox-skeleton');
const Key _empty = ValueKey<String>('gift-inbox-empty');
const Key _error = ValueKey<String>('gift-inbox-error');
const Key _retry = ValueKey<String>('gift-inbox-retry');
const Key _more = ValueKey<String>('gift-inbox-more');
const Key _spinner = ValueKey<String>('gift-inbox-spinner');

Key rowKey(String id) => ValueKey<String>('gift-inbox-row-$id');

/// A gift sent [agoMs] before the test clock.
InboxItem item(
  String id, {
  String? sender = 'ayla',
  String gift = 'rose',
  int quantity = 1,
  String status = 'completed',
  int agoMs = 30000,
}) =>
    InboxItem(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _nowMs - agoMs,
        isUtc: true,
      ).toIso8601String(),
      sender: sender,
      gift: AwayGift(
        id: gift,
        name: '${gift[0].toUpperCase()}${gift.substring(1)}',
        price: 10,
        iconUrl: 'https://assets.test/$gift/256.webp',
      ),
      quantity: quantity,
      units: 10 * quantity,
      status: status,
    );

Inbox page(
  List<InboxItem> items, {
  bool hasMore = false,
  String? next,
}) =>
    Inbox(
      user: 'user_123',
      since: '2026-11-01T10:00:00.000Z',
      until: '2026-11-02T10:00:00.000Z',
      data: items,
      hasMore: hasMore,
      nextCursor: next,
    );

void main() {
  late ScriptedClient api;
  late ControlledImages images;
  final key = GlobalKey<GiftInboxState>();

  setUp(() {
    api = ScriptedClient();
  });

  Future<void> pumpInbox(
    WidgetTester tester, {
    int pageSize = 20,
    Future<Map<String, AwayUser>> Function(List<String>)? resolveUsers,
    void Function(List<InboxItem>)? onLoaded,
    void Function(GiftingException)? onError,
    bool? reducedMotion,
    bool disableAnimations = false,
    GiftingTheme theme = const GiftingTheme(),
    GiftLabels labels = const GiftLabels(),
  }) async {
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    await tester.pumpWidget(
      hostApp(
        SizedBox(
          width: 400,
          child: GiftInbox(
            key: key,
            client: api,
            pageSize: pageSize,
            resolveUsers: resolveUsers,
            onLoaded: onLoaded,
            onError: onError,
            reducedMotion: reducedMotion,
            theme: theme,
            labels: labels,
            imageProvider: images.call,
            now: () => _nowMs,
          ),
        ),
        disableAnimations: disableAnimations,
      ),
    );
  }

  Future<void> answer(WidgetTester tester, Inbox p) async {
    api.take('getInbox', 'answer').completer.complete(p);
    await tester.idle();
    await tester.pump();
    await tester.pump();
  }

  Future<void> failWith(WidgetTester tester) async {
    api.take('getInbox', 'fail').completer.completeError(
          const GiftingException(503, 'boom', 'later'),
        );
    await tester.idle();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Map<String, Object?> lastQuery() =>
      (api.calls.last['args']! as Map<String, Object?>)['query']!
          as Map<String, Object?>;

  Finder inRow(String id, Finder f) =>
      find.descendant(of: find.byKey(rowKey(id)), matching: f);

  group('loading, ready, empty, error', () {
    testWidgets('the first request is page one with the page size',
        (tester) async {
      await pumpInbox(tester);
      expect(api.calls.single, <String, Object?>{
        'method': 'getInbox',
        'args': <String, Object?>{
          'query': <String, Object?>{'limit': 20},
        },
      });
      await finish(tester);
    });

    testWidgets('pageSize is the limit', (tester) async {
      await pumpInbox(tester, pageSize: 5);
      expect(lastQuery(), <String, Object?>{'limit': 5});
      await finish(tester);
    });

    testWidgets('loading: skeleton rows that pulse, then the list',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInbox(tester);
      expect(find.byKey(_skeleton), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue, reason: 'it pulses');
      await answer(tester, page(<InboxItem>[item('g1')]));
      expect(find.byKey(_skeleton), findsNothing);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('loading with reducedMotion: the skeleton is static',
        (tester) async {
      await pumpInbox(tester, reducedMotion: true);
      expect(find.byKey(_skeleton), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse, reason: 'static skeleton');
      await finish(tester);
    });

    testWidgets('the system "remove animations" setting makes it static',
        (tester) async {
      await pumpInbox(tester, disableAnimations: true);
      expect(tester.hasRunningAnimations, isFalse);
      await finish(tester);
    });

    testWidgets('ready: the sentence, the quantity and the time',
        (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(<InboxItem>[
          item('g3', quantity: 3),
          item('g2', sender: null, gift: 'hat', agoMs: 3 * 3600000 + 5000),
          item('g1', sender: 'mert', gift: 'crown', agoMs: 90 * 60000),
        ]),
      );
      expect(find.byKey(_list), findsOneWidget);
      expect(inRow('g3', find.text('ayla sent you Rose x3')), findsOneWidget);
      expect(inRow('g3', find.text('now')), findsOneWidget);
      expect(inRow('g2', find.text('Someone sent you Hat')), findsOneWidget);
      expect(inRow('g2', find.text('3h')), findsOneWidget);
      expect(inRow('g1', find.text('mert sent you Crown')), findsOneWidget);
      expect(inRow('g1', find.text('1h')), findsOneWidget);
      // One gift: no "x1".
      expect(find.textContaining('x1'), findsNothing);
      // The avatar is the sender's initial.
      expect(inRow('g3', find.text('A')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('newest first, in the order the server sent', (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(<InboxItem>[
          item('g3'),
          item('g2', agoMs: 600000),
          item('g1', agoMs: 7200000),
        ]),
      );
      final y3 = tester.getTopLeft(find.byKey(rowKey('g3'))).dy;
      final y2 = tester.getTopLeft(find.byKey(rowKey('g2'))).dy;
      final y1 = tester.getTopLeft(find.byKey(rowKey('g1'))).dy;
      expect(y3, lessThan(y2));
      expect(y2, lessThan(y1));
      await finish(tester);
    });

    testWidgets('reversed gifts are hidden', (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(<InboxItem>[
          item('g2', status: 'reversed'),
          item('g1', agoMs: 120000),
        ]),
      );
      expect(find.byKey(rowKey('g2')), findsNothing);
      expect(find.byKey(rowKey('g1')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('empty: the empty text', (tester) async {
      await pumpInbox(tester);
      await answer(tester, page(const <InboxItem>[]));
      expect(find.byKey(_empty), findsOneWidget);
      expect(find.text('No gifts in the last 24 hours'), findsOneWidget);
      expect(find.byKey(_more), findsNothing);
      await finish(tester);
    });

    testWidgets('only reversed gifts and nothing more: empty', (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(<InboxItem>[item('g1', status: 'reversed')]),
      );
      expect(find.byKey(_empty), findsOneWidget);
      await finish(tester);
    });

    testWidgets('error: message and Try again asks again', (tester) async {
      final handle = tester.ensureSemantics();
      final errors = <String>[];
      await pumpInbox(tester, onError: (e) => errors.add(e.type));
      await failWith(tester);
      expect(find.byKey(_error), findsOneWidget);
      expect(find.text('Could not load gifts'), findsOneWidget);
      expect(errors, <String>['boom']);
      final retry = tester.getSemantics(find.bySemanticsLabel('Try again'));
      expect(
        isSemantics(isButton: true).matches(retry, <dynamic, dynamic>{}),
        isTrue,
      );
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(api.calls.length, 2);
      expect(find.byKey(_skeleton), findsOneWidget);
      await answer(tester, page(<InboxItem>[item('g1')]));
      expect(find.byKey(_error), findsNothing);
      expect(find.byKey(rowKey('g1')), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });
  });

  group('show more', () {
    testWidgets('appends the next page with the cursor; hidden at the end',
        (tester) async {
      await pumpInbox(tester, pageSize: 2, reducedMotion: true);
      await answer(
        tester,
        page(
          <InboxItem>[item('g4'), item('g3', agoMs: 60000)],
          hasMore: true,
          next: 'ib1.NEXT',
        ),
      );
      expect(find.byKey(_more), findsOneWidget);
      expect(find.text('Show more'), findsOneWidget);
      await tester.tap(find.byKey(_more));
      await tester.pump();
      expect(lastQuery(), <String, Object?>{'cursor': 'ib1.NEXT', 'limit': 2});
      // While it loads the button is gone.
      expect(find.byKey(_more), findsNothing);
      await answer(
        tester,
        page(<InboxItem>[item('g2', agoMs: 7200000)]),
      );
      expect(find.byKey(rowKey('g4')), findsOneWidget);
      expect(find.byKey(rowKey('g2')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(rowKey('g3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(rowKey('g2'))).dy),
      );
      expect(find.byKey(_more), findsNothing);
      await finish(tester);
    });

    testWidgets('a spinner shows while the next page loads', (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(<InboxItem>[item('g1')], hasMore: true, next: 'c1'),
      );
      await tester.tap(find.byKey(_more));
      await tester.pump();
      expect(find.byKey(_spinner), findsOneWidget);
      await answer(tester, page(<InboxItem>[item('g0', agoMs: 90000)]));
      expect(find.byKey(_spinner), findsNothing);
      await finish(tester);
    });

    testWidgets('a failed page keeps the rows and the button', (tester) async {
      final errors = <String>[];
      await pumpInbox(
        tester,
        reducedMotion: true,
        onError: (e) => errors.add(e.type),
      );
      await answer(
        tester,
        page(<InboxItem>[item('g1')], hasMore: true, next: 'c1'),
      );
      await tester.tap(find.byKey(_more));
      await tester.pump();
      await failWith(tester);
      expect(errors, <String>['boom']);
      expect(find.byKey(rowKey('g1')), findsOneWidget);
      expect(find.byKey(_more), findsOneWidget);
      expect(find.byKey(_error), findsNothing);
      // Tapping again asks for the same page again.
      await tester.tap(find.byKey(_more));
      await tester.pump();
      expect(lastQuery(), <String, Object?>{'cursor': 'c1', 'limit': 20});
      await finish(tester);
    });

    testWidgets('a first page of only reversed gifts still offers more',
        (tester) async {
      await pumpInbox(tester);
      await answer(
        tester,
        page(
          <InboxItem>[item('g1', status: 'reversed')],
          hasMore: true,
          next: 'c1',
        ),
      );
      expect(find.byKey(_empty), findsNothing);
      expect(find.byKey(_more), findsOneWidget);
      await finish(tester);
    });
  });

  group('names, callbacks, refresh', () {
    testWidgets('resolveUsers turns sender ids into names', (tester) async {
      final asked = <List<String>>[];
      await pumpInbox(
        tester,
        resolveUsers: (ids) async {
          asked.add(ids);
          return <String, AwayUser>{
            'ayla': const AwayUser(name: 'Ayla K.'),
          };
        },
      );
      await answer(
        tester,
        page(<InboxItem>[
          item('g2', sender: 'mert', agoMs: 60000),
          item('g1', agoMs: 120000),
          item('g0', sender: null, agoMs: 180000),
        ]),
      );
      await tester.idle();
      await tester.pump();
      expect(asked, <List<String>>[
        <String>['mert', 'ayla'],
      ]);
      expect(inRow('g1', find.text('Ayla K. sent you Rose')), findsOneWidget);
      // Not answered: the id stays. A deleted sender is never asked for.
      expect(inRow('g2', find.text('mert sent you Rose')), findsOneWidget);
      expect(inRow('g0', find.text('Someone sent you Rose')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('onLoaded gets every loaded gift, reversed ones included',
        (tester) async {
      final loaded = <List<String>>[];
      await pumpInbox(
        tester,
        reducedMotion: true,
        onLoaded: (items) => loaded.add(items.map((i) => i.id).toList()),
      );
      await answer(
        tester,
        page(
          <InboxItem>[item('g2'), item('g1', status: 'reversed')],
          hasMore: true,
          next: 'c1',
        ),
      );
      expect(loaded, <List<String>>[
        <String>['g2', 'g1'],
      ]);
      await tester.tap(find.byKey(_more));
      await tester.pump();
      await answer(tester, page(<InboxItem>[item('g0', agoMs: 90000)]));
      expect(loaded.last, <String>['g2', 'g1', 'g0']);
      await finish(tester);
    });

    testWidgets('refresh() reloads from the first page and replaces the list',
        (tester) async {
      await pumpInbox(tester, reducedMotion: true);
      await answer(
        tester,
        page(<InboxItem>[item('g1')], hasMore: true, next: 'c1'),
      );
      key.currentState!.refresh();
      await tester.pump();
      expect(api.calls.length, 2);
      expect(lastQuery(), <String, Object?>{'limit': 20});
      // The list stays until the answer arrives.
      expect(find.byKey(rowKey('g1')), findsOneWidget);
      expect(find.byKey(_skeleton), findsNothing);
      await answer(
        tester,
        page(<InboxItem>[item('g9'), item('g1', agoMs: 60000)]),
      );
      expect(find.byKey(rowKey('g9')), findsOneWidget);
      expect(find.byKey(_more), findsNothing);
      await finish(tester);
    });

    testWidgets('a failed refresh keeps the list', (tester) async {
      final errors = <String>[];
      await pumpInbox(
        tester,
        reducedMotion: true,
        onError: (e) => errors.add(e.type),
      );
      await answer(tester, page(<InboxItem>[item('g1')]));
      key.currentState!.refresh();
      await tester.pump();
      await failWith(tester);
      expect(errors, <String>['boom']);
      expect(find.byKey(rowKey('g1')), findsOneWidget);
      expect(find.byKey(_error), findsNothing);
      await finish(tester);
    });

    testWidgets('an answer that arrives after a refresh is dropped',
        (tester) async {
      await pumpInbox(tester, reducedMotion: true);
      key.currentState!.refresh();
      await tester.pump();
      expect(api.pending.length, 2);
      await answer(tester, page(<InboxItem>[item('old')]));
      expect(find.byKey(rowKey('old')), findsNothing);
      await answer(tester, page(<InboxItem>[item('new')]));
      expect(find.byKey(rowKey('new')), findsOneWidget);
      await finish(tester);
    });
  });

  group('labels, theme, accessibility', () {
    testWidgets('one element per row with the sentence and the time',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInbox(
        tester,
        resolveUsers: (ids) async => <String, AwayUser>{
          'ayla': const AwayUser(name: 'Ayla K.'),
        },
      );
      await answer(
        tester,
        page(<InboxItem>[
          item('g2', quantity: 3),
          item('g1', sender: null, gift: 'hat', agoMs: 3 * 3600000 + 5000),
        ]),
      );
      await tester.idle();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Ayla K. sent you Rose x3, now'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Someone sent you Hat, 3h'),
        findsOneWidget,
      );
      handle.dispose();
      await finish(tester);
    });

    testWidgets('Show more is a button', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInbox(tester, reducedMotion: true);
      await answer(
        tester,
        page(<InboxItem>[item('g1')], hasMore: true, next: 'c1'),
      );
      final more = tester.getSemantics(find.bySemanticsLabel('Show more'));
      expect(
        isSemantics(isButton: true).matches(more, <dynamic, dynamic>{}),
        isTrue,
      );
      handle.dispose();
      await finish(tester);
    });

    testWidgets('labels translate every text', (tester) async {
      await pumpInbox(
        tester,
        reducedMotion: true,
        labels: const GiftLabels(
          inboxEmpty: 'Hic hediye yok',
          inboxError: 'Yuklenemedi',
          inboxShowMore: 'Daha fazla',
          inboxSent: '{name} sana {gift} gonderdi',
          inboxQuantity: '{n} adet',
        ),
      );
      await answer(
        tester,
        page(
          <InboxItem>[item('g1', quantity: 2)],
          hasMore: true,
          next: 'c1',
        ),
      );
      expect(
        inRow('g1', find.text('ayla sana Rose gonderdi 2 adet')),
        findsOneWidget,
      );
      expect(find.text('Daha fazla'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('theme colors reach the text and the button', (tester) async {
      const theme = GiftingTheme(
        surface: Color(0xFF111111),
        muted: Color(0xFF222222),
        text: Color(0xFF333333),
      );
      await pumpInbox(tester, reducedMotion: true, theme: theme);
      await answer(
        tester,
        page(<InboxItem>[item('g1')], hasMore: true, next: 'c1'),
      );
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GiftInbox),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, theme.surface);
      final text = tester.widget<Text>(find.text('Show more'));
      expect(text.style!.color, theme.text);
      await finish(tester);
    });
  });
}
