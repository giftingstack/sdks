// Unit tests of the pure component core beyond the fixtures: edge cases of
// formatCount, the models, the 204 of the cursor PUT, and the loader's small
// rules. The fixtures (components_conformance_test.dart) are the contract; these
// are the places the fixtures do not look.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/component_harness.dart';

void main() {
  group('formatCount', () {
    test('floors, never rounds up', () {
      expect(formatCount(1999), '1.9K');
      expect(formatCount(1099), '1K');
      expect(formatCount(9999), '9.9K');
      expect(formatCount(999999), '999K');
      expect(formatCount(1999999), '1.9M');
      expect(formatCount(9999999), '9.9M');
      expect(formatCount(10000000), '10M');
      expect(formatCount(12345678), '12M');
    });

    test('fractions are truncated, non-finite is 0, negatives are as is', () {
      expect(formatCount(1999.9), '1.9K');
      expect(formatCount(double.nan), '0');
      expect(formatCount(double.infinity), '0');
      expect(formatCount(-5), '-5');
      expect(formatCount(-1500), '-1500');
      expect(formatCount(0.9), '0');
    });

    test('labels: suffixes and decimal mark', () {
      const l = CountLabels(thousand: 'b', million: ' Mn', decimal: ',');
      expect(formatCount(1500, l), '1,5b');
      expect(formatCount(2500000, l), '2,5 Mn');
      expect(formatCount(12000, l), '12b');
    });
  });

  group('wallChips', () {
    test('does not change its input and keeps the catalog order on ties', () {
      final items = <ReceivedGift>[
        received('a', 3),
        received('b', 3),
        received('c', 5),
        received('d', 3),
      ];
      final ids = items.map((i) => i.gift.id).toList();
      final chips = wallChips(items);
      expect(items.map((i) => i.gift.id).toList(), ids);
      expect(
        chips.map((c) => (c as WallGiftChip).gift.id).toList(),
        <String>['c', 'a', 'b', 'd'],
      );
    });

    test('many equal counts keep the input order (the sort is stable)', () {
      final items = <ReceivedGift>[
        for (var i = 0; i < 40; i++) received('g$i', 7),
      ];
      final chips = wallChips(items, max: 40);
      expect(
        chips.map((c) => (c as WallGiftChip).gift.id).toList(),
        items.map((i) => i.gift.id).toList(),
      );
    });

    test('the overflow is the SUM of the counts, hidden is the kinds', () {
      final chips = wallChips(
        <ReceivedGift>[
          received('a', 10),
          received('b', 20),
          received('c', 30),
          received('d', 40),
        ],
        max: 2,
      );
      final overflow = chips.last as WallOverflowChip;
      expect(overflow.count, 10 + 20 + 30);
      expect(overflow.hidden, 3);
      expect(chips.length, 2);
    });

    test('exactly max items: no overflow chip', () {
      final chips = wallChips(
        <ReceivedGift>[received('a', 1), received('b', 2)],
        max: 2,
      );
      expect(chips.every((c) => c is WallGiftChip), isTrue);
    });
  });

  group('groupThousands and rank labels', () {
    test('separators', () {
      expect(groupThousands(0), '0');
      expect(groupThousands(999), '999');
      expect(groupThousands(1000), '1,000');
      expect(groupThousands(1234567), '1,234,567');
      expect(groupThousands(-1234567), '-1,234,567');
      expect(groupThousands(1234567, '.'), '1.234.567');
    });

    test('rank labels', () {
      expect(leaderboardRankLabel(417), '#417');
      expect(leaderboardRankLabel(1000), '#1,000');
      expect(leaderboardRankLabel(null), '1,000+');
      expect(leaderboardRankLabel(null, overflow: 'x'), 'x');
    });
  });

  group('away', () {
    test('effect durations are SPEC 7.3: 1600, 2100, 3850, low 3050', () {
      expect(effectDurationMs(recipeFor(EffectTier.small)), 1600);
      expect(effectDurationMs(recipeFor(EffectTier.medium)), 2100);
      expect(effectDurationMs(recipeFor(EffectTier.large)), 3850);
      expect(
        effectDurationMs(recipeFor(EffectTier.large, EffectQuality.low)),
        3050,
      );
    });

    test('no groups, maxEffects 0 or below: an empty plan', () {
      expect(planAwayReplay(const <AwayGroup>[]).items, isEmpty);
      expect(planAwayReplay(const <AwayGroup>[]).endMs, 0);
      final groups = workedSummary().groups;
      expect(planAwayReplay(groups, maxEffects: 0).items, isEmpty);
      expect(planAwayReplay(groups, maxEffects: -3).items, isEmpty);
    });

    test('the plan does not change the groups it was given', () {
      final groups = workedSummary().groups;
      final before = groups.map((g) => g.gift.id).toList();
      planAwayReplay(groups);
      expect(groups.map((g) => g.gift.id).toList(), before);
    });

    test('the plan never ends after budgetMs, an end equal to it fits', () {
      final groups = <AwayGroup>[
        for (var i = 0; i < 5; i++) awayGroup('m$i', 350, 100 - i * 10),
      ];
      for (final budget in <int>[2100, 3200, 4300, 6500, 8000]) {
        final plan = planAwayReplay(groups, budgetMs: budget);
        expect(plan.endMs, lessThanOrEqualTo(budget), reason: '$budget');
      }
      expect(planAwayReplay(groups, budgetMs: 6500).items.length, 5);
      expect(planAwayReplay(groups, budgetMs: 6499).items.length, 4);
      expect(planAwayReplay(groups, budgetMs: 2099).items, isEmpty);
    });

    test('sender labels with custom texts', () {
      const l = AwaySenderLabels(
        pair: '{a} & {b}',
        oneOther: '{a} + biri',
        others: '{a} + {n}',
      );
      expect(awaySenderLabel(<String>['a', 'b'], 2, l), 'a & b');
      expect(awaySenderLabel(<String>['a', 'b', 'c'], 3, l), 'a + 2');
      expect(awaySenderLabel(<String>['a', 'b'], 2, l), 'a & b');
      expect(awaySenderLabel(<String>['a'], 2, l), 'a + biri',
          reason: 'one name, two people: "and 1 other"');
      expect(awaySenderLabel(const <String>[], 1), 'Someone');
    });
  });

  group('models', () {
    test('AwaySummary and Leaderboard round-trip their wire JSON', () {
      final away = workedSummary();
      expect(
        jsonEncode(AwaySummary.fromJson(away.toJson()).toJson()),
        jsonEncode(away.toJson()),
      );
      expect(away.groups[1].senders[1].user, isNull);
      final board = standardBoard();
      expect(
        jsonEncode(Leaderboard.fromJson(board.toJson()).toJson()),
        jsonEncode(board.toJson()),
      );
      final none = standardBoard(me: null);
      expect(Leaderboard.fromJson(none.toJson()).me, isNull);
    });

    test('a body that does not fit is a FormatException', () {
      expect(
        () => AwaySummary.fromJson(<String, Object?>{'user': 'x'}),
        throwsFormatException,
      );
      expect(
        () => GiftWallResult.fromJson(<String, Object?>{
          'receiver': 'x',
          'gifts': 'no',
        }),
        throwsFormatException,
      );
      expect(
        () => LeaderboardEntry.fromJson(<String, Object?>{
          'rank': 'one',
          'user': 'x',
          'gifts': 1,
          'units': 1,
        }),
        throwsFormatException,
      );
    });

    test('GiftWallQueryItem leaves a null reference out', () {
      expect(
        const GiftWallQueryItem(receiver: 'a').toJson(),
        <String, Object?>{'receiver': 'a'},
      );
      expect(
        const GiftWallQueryItem(receiver: 'a', reference: 'p').toJson(),
        <String, Object?>{'receiver': 'a', 'reference': 'p'},
      );
    });
  });

  group('client details the fixtures do not pin', () {
    GiftingClient clientFor(http.Client c) => GiftingClient(
          getToken: ({required bool forceRefresh}) async => 't',
          httpClient: c,
        );

    test('ackAway: a 204 is never parsed, whatever it carries', () async {
      final seen = <http.Request>[];
      final client = clientFor(
        MockClient((req) async {
          seen.add(req);
          return http.Response('this is not json', 204);
        }),
      );
      await client.ackAway('aw1.X');
      expect(seen.single.method, 'PUT');
      expect(seen.single.url.path, '/v1/client/me/away/cursor');
      expect(
          jsonDecode(seen.single.body), <String, Object?>{'cursor': 'aw1.X'});
      expect(seen.single.headers.containsKey('Idempotency-Key'), isFalse);
      expect(seen.single.headers['Content-Type'], 'application/json');
    });

    test('says where it runs: platform flutter, the phone OS when given',
        () async {
      final seen = <Map<String, String>>[];
      http.Client recorder() => MockClient((req) async {
            seen.add(req.headers);
            return http.Response('{"data": []}', 200);
          });
      await clientFor(recorder()).getGifts();
      // Tests run on a desktop or a server: no OS header there.
      expect(seen.last['X-GiftingStack-Platform'], 'flutter');
      expect(seen.last.containsKey('X-GiftingStack-OS'), isFalse);
      final android = GiftingClient(
        getToken: ({required bool forceRefresh}) async => 't',
        httpClient: recorder(),
        os: 'android',
      );
      await android.getGifts();
      expect(seen.last['X-GiftingStack-OS'], 'android');
      final other = GiftingClient(
        getToken: ({required bool forceRefresh}) async => 't',
        httpClient: recorder(),
        platform: 'web',
      );
      await other.getGifts();
      expect(seen.last['X-GiftingStack-Platform'], 'web');
    });

    test('queryGiftWalls: no Idempotency-Key, no request for an empty list',
        () async {
      var calls = 0;
      Map<String, String>? headers;
      final client = clientFor(
        MockClient((req) async {
          calls++;
          headers = req.headers;
          return http.Response('{"data": []}', 200);
        }),
      );
      expect(await client.queryGiftWalls(const <GiftWallQueryItem>[]), isEmpty);
      expect(calls, 0);
      await client.queryGiftWalls(
        const <GiftWallQueryItem>[GiftWallQueryItem(receiver: 'a')],
      );
      expect(calls, 1);
      expect(headers!.containsKey('Idempotency-Key'), isFalse);
    });

    test('getLeaderboard: includeMe true is left out, false is sent', () async {
      final urls = <String>[];
      final client = clientFor(
        MockClient((req) async {
          urls.add(req.url.toString());
          return http.Response(
            jsonEncode(standardBoard(me: null).toJson()),
            200,
          );
        }),
      );
      await client.getLeaderboard(LeaderboardBoard.senders, includeMe: true);
      await client.getLeaderboard(LeaderboardBoard.senders, includeMe: false);
      expect(urls, <String>[
        'https://api.giftingstack.com/v1/client/leaderboards/senders',
        'https://api.giftingstack.com/v1/client/leaderboards/senders?include_me=false',
      ]);
    });
  });

  group('GiftWallLoader details', () {
    test('peek: fresh answers only; clear forgets them', () async {
      var now = 0;
      final asked = <List<GiftWallQueryItem>>[];
      final loader = GiftWallLoader(
        now: () => now,
        setTimeout: (fn, ms) {
          scheduleMicrotask(fn);
          return null;
        },
        query: (items) async {
          asked.add(items);
          return <GiftWallResult>[
            for (final i in items)
              GiftWallResult(
                receiver: i.receiver,
                gifts: <ReceivedGift>[received('rose', 1)],
              ),
          ];
        },
      );
      expect(loader.peek('a'), isNull);
      await loader.load('a');
      expect(loader.peek('a'), isNotNull);
      now = 59999;
      expect(loader.peek('a'), isNotNull);
      now = 60000;
      expect(loader.peek('a'), isNull, reason: '60,000 ms is no longer fresh');
      await loader.load('a');
      expect(asked.length, 2);
      loader.clear();
      expect(loader.peek('a'), isNull);
    });

    test('a failure is not cached: the next load asks again', () async {
      var n = 0;
      final loader = GiftWallLoader(
        setTimeout: (fn, ms) {
          scheduleMicrotask(fn);
          return null;
        },
        query: (items) async {
          if (++n == 1) throw const GiftingException(500, 'x', 'x');
          return <GiftWallResult>[
            GiftWallResult(receiver: 'a', gifts: <ReceivedGift>[]),
          ];
        },
      );
      await expectLater(loader.load('a'), throwsA(isA<GiftingException>()));
      expect(await loader.load('a'), isEmpty);
      expect(n, 2);
    });

    test('batchSize: a custom size cuts the calls', () async {
      final sizes = <int>[];
      final loader = GiftWallLoader(
        batchSize: 2,
        setTimeout: (fn, ms) {
          scheduleMicrotask(fn);
          return null;
        },
        query: (items) async {
          sizes.add(items.length);
          return <GiftWallResult>[
            for (final i in items)
              GiftWallResult(receiver: i.receiver, gifts: <ReceivedGift>[]),
          ];
        },
      );
      await Future.wait(<Future<List<ReceivedGift>>>[
        for (final u in <String>['a', 'b', 'c', 'd', 'e']) loader.load(u),
      ]);
      expect(sizes, <int>[2, 2, 1]);
    });
  });

  group('LeaderboardController options', () {
    test('an empty periods list is the default four tabs', () {
      final c = LeaderboardController(
        LeaderboardControllerOptions(
          client: _NoClient(),
          periods: const <LeaderboardPeriod>[],
        ),
      );
      expect(c.state.periods, leaderboardPeriods);
      expect(c.state.period, LeaderboardPeriod.week);
      expect(c.state.status, LeaderboardStatus.loading);
    });
  });
}

class _NoClient extends GiftingClient {
  _NoClient() : super(getToken: ({required bool forceRefresh}) async => '');
}
