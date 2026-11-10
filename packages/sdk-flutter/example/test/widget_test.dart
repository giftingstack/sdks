import 'dart:math';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack_example/catalog.dart';
import 'package:giftingstack_example/incoming.dart';
import 'package:giftingstack_example/main.dart';
import 'package:giftingstack_example/mock_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A library like the live one: `n` ordinary gifts of rising price and 108
/// country hearts of one price.
String libraryJson({int ordinary = 200}) => jsonEncode({
      'version': 1,
      'gifts': [
        for (final id in pick)
          {'id': id, 'name': id.toUpperCase(), 'suggested_price': 50},
        for (var i = 0; i < ordinary; i++)
          {'id': 'gift-$i', 'name': 'Gift $i', 'suggested_price': 10 + i * 7},
        for (var i = 0; i < 108; i++)
          {'id': 'heart-c$i', 'name': 'Heart $i', 'suggested_price': 30},
        {'id': 'heart-turkey', 'name': 'Heart Turkey', 'suggested_price': 30},
      ],
    });

void main() {
  group('catalog', () {
    test('about ninety gifts: the twelve chosen first, then a spread', () {
      final lib = parseLibrary(libraryJson())!;
      final gifts = selectGifts(lib);
      expect(gifts.length, inInclusiveRange(85, 95));
      expect(gifts.take(12).map((g) => g.id), pick);
      // Spread from cheap to grand, and sort_order follows the list.
      final rest = gifts.skip(12).toList();
      expect(rest.first.price, lessThan(rest.last.price));
      expect(
        rest.map((g) => g.price).toList(),
        [...rest.map((g) => g.price)]..sort(),
      );
      expect(
          gifts.map((g) => g.sortOrder), List.generate(gifts.length, (i) => i));
      // The 108 country hearts share one price: only the two chosen hearts stay.
      expect(
        gifts.where((g) => g.id.startsWith('heart-')).map((g) => g.id),
        ['heart-latte', 'heart-turkey'],
      );
      // Pictures come from the library host.
      expect(gifts.first.iconUrl, '$assetsHost/gifts/pink-tulip/256.webp');
      expect(gifts.first.animationUrl, '$assetsHost/gifts/pink-tulip/512.webp');
    });

    test('loadGifts reads the live library address and selects from it',
        () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(libraryJson(), 200);
      });
      final gifts = await loadGifts(client: client);
      expect(asked.toString(), 'https://assets.giftingstack.com/library.json');
      expect(gifts.length, greaterThan(50));
    });

    test('the small list is the fallback: offline, 404, or broken JSON',
        () async {
      for (final client in <http.Client>[
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient((_) async => http.Response('nope', 404)),
        MockClient((_) async => http.Response('{broken', 200)),
        MockClient((_) async => http.Response('{"gifts": 3}', 200)),
      ]) {
        final gifts = await loadGifts(client: client);
        expect(gifts.map((g) => g.id), fallbackGifts.map((g) => g.id));
      }
      expect(fallbackGifts, hasLength(12));
    });
  });

  group('mock client', () {
    test('credit ADDS coins; reset goes back to 60 000', () async {
      final client = MockGiftingClient(Future.value(fallbackGifts));
      expect((await client.getMe()).balance, 60000);
      client.credit(5000);
      expect((await client.getMe()).balance, 65000);
      client.credit(1000);
      expect((await client.getMe()).balance, 66000);
      client.reset();
      expect((await client.getMe()).balance, 60000);
    });
  });

  group('incoming gifts (demo logic)', () {
    test('tiers follow the layer thresholds; rolls are 78/19/3', () {
      expect(tierOf(99), Tier.small);
      expect(tierOf(100), Tier.medium);
      expect(tierOf(9999), Tier.medium);
      expect(tierOf(10000), Tier.large);
      expect(rollTier(0.5), Tier.small);
      expect(rollTier(0.9), Tier.medium);
      expect(rollTier(0.99), Tier.large);
    });

    test('a pick is a catalog gift, a known sender and a small quantity', () {
      final rand = Random(5);
      for (var i = 0; i < 200; i++) {
        final inc = pickIncoming(fallbackGifts, ['zoe', 'caleb'], rand);
        expect(fallbackGifts.map((g) => g.id), contains(inc.gift.id));
        expect(['zoe', 'caleb'], contains(inc.sender));
        expect(inc.quantity, inInclusiveRange(1, 3));
        if (tierOf(inc.gift.price) == Tier.large) expect(inc.quantity, 1);
      }
      final d = nextDelay(rand);
      expect(d.inSeconds, inInclusiveRange(20, 40));
    });

    test('the live feed ticks with fake time and stops', () {
      fakeAsync((async) {
        final seen = <Incoming>[];
        final timer = startIncoming(
          gifts: () => fallbackGifts,
          senders: const ['caleb'],
          onGift: seen.add,
          random: Random(1),
        );
        async.elapse(const Duration(seconds: 41));
        expect(seen, hasLength(1));
        async.elapse(const Duration(seconds: 41));
        expect(seen, hasLength(2));
        timer.cancel();
        async.elapse(const Duration(minutes: 5));
        expect(seen, hasLength(2));
      });
    });

    test('gifts from others do not arrive by themselves by default', () {
      expect(liveFeed, isFalse);
    });
  });

  group('Pixel app', () {
    setUp(() => demoAwaySeen = true);

    Future<void> openDemo(
      WidgetTester tester, {
      Size logical = const Size(432, 960),
    }) async {
      tester.view.physicalSize = logical * 2.5;
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(DemoApp(gifts: Future.value(fallbackGifts)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    /// Time passes in steps so the mock's 250 ms latency and the wall loader's
    /// 50 ms window both run.
    Future<void> settleFor(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openMenu(WidgetTester tester) async {
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('pixel-logo'))),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await g.up();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      final f = find.text(text);
      await tester.ensureVisible(f);
      await tester.tap(f);
    }

    Future<void> tab(WidgetTester tester, String name) async {
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey<String>('nav-bar')),
        matching: find.text(name),
      ));
      await settleFor(tester, 900);
    }

    String chip(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey<String>('coin-chip-text')))
        .data!;

    Finder inWall(String post, Finder f) => find.descendant(
          of: find.byKey(ValueKey<String>('wall-$post')),
          matching: f,
        );

    List<String> wallTexts(WidgetTester tester, String post) => tester
        .widgetList<Text>(inWall(post, find.byType(Text)))
        .map((t) => t.data!)
        .toList();

    Future<void> openTray(WidgetTester tester, String post) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>('gift-$post')));
      await tester.tap(find.byKey(ValueKey<String>('gift-$post')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets(
        'live room: a pick lowers the tray and the SDK scrim goes, a tap on the '
        'scrim closes it, the Gift button (toggle) closes it', (tester) async {
      await openDemo(tester);
      await tab(tester, 'Live');
      final scrim = find.byKey(const ValueKey<String>('tray-scrim'));
      final liveGift = find.byKey(const ValueKey<String>('live-gift'));
      await tester.tap(liveGift);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsOneWidget);
      double dim() => tester
          .widget<AnimatedOpacity>(find.descendant(
            of: scrim,
            matching: find.byType(AnimatedOpacity),
          ))
          .opacity;
      expect(dim(), kScrimOpacity);
      // A pick lowers the sheet to peek and the dim goes away.
      await tester.tap(
          find.byKey(ValueKey<String>('gift-${fallbackGifts[2].id}')).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsOneWidget);
      expect(dim(), 0);
      // The Gift button closes it.
      await tester.tap(liveGift);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsNothing);
      // A tap on the dim of an open sheet closes it too.
      await tester.tap(liveGift);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsOneWidget);
      await tester.tapAt(const Offset(200, 120));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsNothing);
    });

    testWidgets(
        'live room: both sides can be gifted and the bar stays in reach under '
        'the tray', (tester) async {
      await openDemo(tester);
      await tab(tester, 'Live');
      await tester.tap(find.byKey(const ValueKey<String>('live-gift')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Gift Mira'), findsWidgets);
      // A pick lowers the sheet to peek (the dim goes), so the page is in reach.
      await tester.tap(
          find.byKey(ValueKey<String>('gift-${fallbackGifts[2].id}')).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // The tray is at peek and the scrim takes the tap there (SPEC 9.4): the
      // first tap on the other side's button closes the tray, the next one
      // reopens it for that side.
      await tester.tap(find.byKey(const ValueKey<String>('live-gift-noor')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('live-gift-noor')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsOneWidget);
      // The bar is above the tray: a tap on Top leaves Live and closes it.
      await tester.tap(find.text('Top').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsNothing);
    });

    testWidgets('live room: Battle 4+ has four sides, a Gift button for each',
        (tester) async {
      await openDemo(tester);
      await tab(tester, 'Live');
      expect(
          find.byKey(const ValueKey<String>('live-gift-lina')), findsNothing);
      await tester.tap(find.text('Battle 4+'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      for (final id in [
        'live-gift',
        'live-gift-noor',
        'live-gift-lina',
        'live-gift-owen'
      ]) {
        expect(find.byKey(ValueKey<String>(id)), findsOneWidget, reason: id);
      }
      // On a small phone (320 wide) the four buttons are two columns and stay on screen.
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final mira =
          tester.getRect(find.byKey(const ValueKey<String>('live-gift')));
      final noor =
          tester.getRect(find.byKey(const ValueKey<String>('live-gift-noor')));
      final lina =
          tester.getRect(find.byKey(const ValueKey<String>('live-gift-lina')));
      expect(mira.top, noor.top, reason: 'two columns');
      expect(lina.top, greaterThan(mira.top), reason: 'the second row');
      expect(noor.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      // Back to the two-sided battle.
      await tester.tap(find.text('Battle').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
          find.byKey(const ValueKey<String>('live-gift-owen')), findsNothing);
    });

    testWidgets('no debug surface on screen: tabs, posts and a Gift button',
        (tester) async {
      await openDemo(tester);
      for (final l in ['Feed', 'Top', 'Live', 'Inbox', 'Me']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('Pixel'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gift-post_42')), findsOne);
      for (final l in [
        'Incoming gift',
        'x5 combo',
        'Reset demo',
        'Developer menu (not part of the SDK)',
        'Demo controls (not part of the SDK)',
      ]) {
        expect(find.text(l), findsNothing, reason: l);
      }
      // Nothing of the tray until a Gift button is pressed.
      expect(find.byType(GiftTray), findsNothing);
      expect(chip(tester), '60,000');
    });

    testWidgets(
        'the developer menu is folded: a tap does not open it, a 1 s '
        'long-press does, with every control', (tester) async {
      await openDemo(tester);
      await tester.tap(find.byKey(const ValueKey<String>('pixel-logo')));
      await tester.pumpAndSettle();
      expect(find.text('Developer menu (not part of the SDK)'), findsNothing);
      // Half a second is not enough.
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('pixel-logo'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Developer menu (not part of the SDK)'), findsNothing);
      await openMenu(tester);
      expect(find.text('Developer menu (not part of the SDK)'), findsOne);
      for (final l in [
        'Same as tray',
        'Random',
        'Cheapest',
        'Priciest',
        'Play gift',
        'x5 combo',
        'Away summary again',
        'Wall +5',
        'High',
        'Low',
        'Dark',
        'Light',
        'Pink',
        'System',
        'Reduced',
        'Mock failure: go offline',
        'Reset demo',
      ]) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      await tester.tap(find.byKey(const ValueKey<String>('dev-done')));
      await tester.pumpAndSettle();
      expect(find.text('Developer menu (not part of the SDK)'), findsNothing);
    });

    testWidgets(
        'Gift opens the tray at the bottom of the screen, also when '
        'the page is shorter than the screen', (tester) async {
      await openDemo(tester, logical: const Size(432, 5000));
      expect(find.byType(GiftTray), findsNothing);
      await openTray(tester, 'post_42');
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      // The tray ends where the navigation bar starts.
      expect(tester.getRect(find.byType(GiftTray)).bottom,
          lessThanOrEqualTo(screen.height));
      expect(
        tester.getRect(find.text('Send')).bottom,
        greaterThan(screen.height - 200),
      );
    });

    testWidgets('the scrim closes the tray without sending', (tester) async {
      await openDemo(tester);
      await openTray(tester, 'post_43');
      expect(find.byType(GiftTray), findsOneWidget);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(find.byType(GiftTray), findsNothing);
      expect(chip(tester), '60,000');
    });

    testWidgets(
        'sending keeps the tray open, the wall counts it, balance drops',
        (tester) async {
      await openDemo(tester);
      await settleFor(tester, 600);
      // 12 3 1 27 8 5 2 9 4 6: the five biggest and the sum of the other five.
      expect(wallTexts(tester, 'post_42'), ['27', '12', '9', '8', '6', '+15']);
      await openTray(tester, 'post_42');
      // Sun dragon (40 000 coins) is selected and is outside the first ten.
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await settleFor(tester, 1600);
      expect(find.byType(GiftTray), findsOneWidget);
      expect(wallTexts(tester, 'post_42').last, '+16');
      expect(chip(tester), '20,000');
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('a wall chip opens the tray for that post', (tester) async {
      await openDemo(tester);
      await settleFor(tester, 600);
      tester
          .widget<GestureDetector>(
            inWall('post_42', find.byType(GestureDetector)).first,
          )
          .onTap!();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(GiftTray), findsOneWidget);
    });

    testWidgets('the coin store ADDS coins (header chip, Me, tray)',
        (tester) async {
      await openDemo(tester);
      await tester.tap(find.byKey(const ValueKey<String>('coin-chip')));
      await tester.pumpAndSettle();
      expect(find.text('Demo store: nothing is charged.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('pack-5000')));
      await settleFor(tester, 1500);
      expect(chip(tester), '65,000'); // not reset to 60 000
      await tab(tester, 'Me');
      await tester.tap(find.byKey(const ValueKey<String>('get-coins')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('pack-1000')));
      await settleFor(tester, 1500);
      expect(chip(tester), '66,000');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('me-balance')))
            .data,
        '66,000',
      );
      await tab(tester, 'Feed');
      await openTray(tester, 'post_43');
      await tester.tap(find.byKey(const ValueKey<String>('gift-topup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('pack-20000')));
      await settleFor(tester, 1500);
      expect(chip(tester), '86,000');
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey<String>('gift-balance-text')))
            .data,
        '86,000',
      );
    });

    testWidgets('the away card shows the first time only; the menu re-shows it',
        (tester) async {
      demoAwaySeen = false;
      await openDemo(tester);
      await settleFor(tester, 700);
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.text('80 gifts from 9 people'), findsOneWidget);
      expect(find.text('Elise'), findsWidgets);
      expect(find.text('Someone'), findsWidgets);
      expect(demoAwaySeen, isTrue);
      await tester.tap(find.byKey(const ValueKey<String>('gift-away-dismiss')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey<String>('gift-away-card')),
        findsNothing,
      );
      await openMenu(tester);
      await tapText(tester, 'Away summary again');
      await settleFor(tester, 900);
      expect(
        find.byKey(const ValueKey<String>('gift-away-card')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('gift-away-dismiss')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('a second launch does not show the away card', (tester) async {
      demoAwaySeen = true;
      await openDemo(tester);
      await settleFor(tester, 700);
      expect(
          find.byKey(const ValueKey<String>('gift-away-card')), findsNothing);
    });

    testWidgets('Top: leaderboard with ties, you pinned outside, both boards',
        (tester) async {
      await openDemo(tester);
      await tab(tester, 'Top');
      expect(find.text('Zoe Lambert'), findsOneWidget);
      for (final u in ['zoe', 'caleb', 'elise', 'daphne', 'bruno']) {
        expect(
          find.byKey(ValueKey<String>('gift-lb-row-$u')),
          findsOneWidget,
          reason: u,
        );
      }
      Finder rank(String user, String n) => find.descendant(
            of: find.byKey(ValueKey<String>('gift-lb-row-$user')),
            matching: find.text(n),
          );
      expect(rank('caleb', '2'), findsOneWidget);
      expect(rank('elise', '2'), findsOneWidget);
      expect(rank('mateo', '4'), findsOneWidget);
      expect(find.text('You: #417'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('gift-lb-tab-all')));
      await settleFor(tester, 800);
      expect(find.text('You: 1,000+'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('gift-lb-metric-gifts')),
      );
      await settleFor(tester, 800);
      expect(find.text('gifts'), findsWidgets);
      await tapText(tester, 'Top creators');
      await settleFor(tester, 900);
      expect(find.byKey(const ValueKey<String>('gift-lb-row-caleb')), findsOne);
    });

    testWidgets(
        'Live: joins a pretend room, shows viewers, plays other people\x27s gifts, '
        'leaves when you go elsewhere', (tester) async {
      await openDemo(tester);
      await tab(tester, 'Live');
      Text status() => tester
          .widget<Text>(find.byKey(const ValueKey<String>('live-status')));
      expect(status().data, contains('watching'));
      await settleFor(tester, 500);
      expect(status().data, endsWith('open'));
      bool playing() => find
          .byWidgetPredicate((w) => w.runtimeType.toString() == 'EffectItem')
          .evaluate()
          .isNotEmpty;
      // The pretend room sends a gift every 8 to 16 seconds.
      var seen = false;
      for (var t = 0; t < 20000 && !seen; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        seen = playing();
      }
      expect(seen, isTrue, reason: 'a room gift played in the effect layer');
      await tab(tester, 'Feed');
      expect(find.byKey(const ValueKey<String>('live-status')), findsNothing);
      await settleFor(tester, 4000);
    });

    testWidgets('Me: profile wall, received count, hide switch',
        (tester) async {
      await openDemo(tester);
      await tab(tester, 'Me');
      expect(find.text('Ava Carter'), findsOneWidget);
      expect(find.text('214'), findsOneWidget);
      expect(wallTexts(tester, 'profile').length, greaterThan(2));
      final sw = find.byKey(const ValueKey<String>('hide-switch'));
      expect(tester.widget<Switch>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pump();
      expect(tester.widget<Switch>(sw).value, isTrue);
    });

    testWidgets('developer menu: Play gift (same as tray) reaches the inbox',
        (tester) async {
      await openDemo(tester);
      await openMenu(tester);
      await tapText(tester, 'Play gift');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Sun dragon is a large gift: its notice names it.
      expect(find.textContaining('Sun dragon'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('inbox-badge')), findsOne);
      await tester.pumpAndSettle(const Duration(seconds: 8));
      await tab(tester, 'Inbox');
      expect(find.textContaining('sent you Sun dragon'), findsOneWidget);
    });

    testWidgets('developer menu: Cheapest and x5 combo', (tester) async {
      await openDemo(tester);
      await openMenu(tester);
      await tapText(tester, 'Cheapest');
      await tapText(tester, 'x5 combo');
      await settleFor(tester, 1500);
      await tester.pumpAndSettle(const Duration(seconds: 8));
      await tab(tester, 'Inbox');
      expect(find.textContaining('sent you Pink tulip'), findsNWidgets(5));
    });

    testWidgets('developer menu: Wall +5 changes the walls', (tester) async {
      await openDemo(tester);
      await settleFor(tester, 600);
      final before = wallTexts(tester, 'post_42');
      await openMenu(tester);
      await tapText(tester, 'Wall +5');
      await tester.tap(find.byKey(const ValueKey<String>('dev-done')));
      await settleFor(tester, 1200);
      expect(wallTexts(tester, 'post_42'), isNot(before));
    });

    testWidgets('developer menu: theme light changes the app', (tester) async {
      await openDemo(tester);
      Color? bg() =>
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
      expect(bg(), darkTheme.background);
      await openMenu(tester);
      await tapText(tester, 'Light');
      await tester.pumpAndSettle();
      expect(bg(), lightTheme.background);
    });

    testWidgets('developer menu: the mock failure switch shows the banner',
        (tester) async {
      await openDemo(tester);
      expect(
        find.byKey(const ValueKey<String>('offline-banner')),
        findsNothing,
      );
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey<String>('dev-offline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('dev-done')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('offline-banner')),
        findsOneWidget,
      );
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey<String>('dev-offline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('dev-done')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('offline-banner')),
        findsNothing,
      );
    });

    testWidgets('developer menu: Reset demo puts balance and inbox back',
        (tester) async {
      await openDemo(tester);
      await tester.tap(find.byKey(const ValueKey<String>('coin-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('pack-20000')));
      await settleFor(tester, 1500);
      expect(chip(tester), '80,000');
      await openMenu(tester);
      await tapText(tester, 'Reset demo');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await settleFor(tester, 1500);
      expect(chip(tester), '60,000');
    });
  });
}
