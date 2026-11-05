// The loader (SPEC 13.5) with a fake fetch, fake storage and a fake clock, and
// the scheduler reading a recipe set (13.4).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

const String url = 'https://example.test/recipes.json';

String doc({int comboWindowMs = 3000, int largeSparks = 80}) => jsonEncode(
      <String, Object?>{
        'specVersion': '1.0.0',
        'comboWindowMs': comboWindowMs,
        'recipes': <String, Object?>{
          'high': <String, Object?>{
            'large': <String, Object?>{'sparks': largeSparks},
          },
        },
      },
    );

class FakeStorage implements RecipesStorage {
  final Map<String, String> data = <String, String>{};
  bool throws = false;
  int writes = 0;

  @override
  String? read(String key) {
    if (throws) throw StateError('blocked');
    return data[key];
  }

  @override
  void write(String key, String value) {
    if (throws) throw StateError('full');
    writes++;
    data[key] = value;
  }
}

/// A fetch the test scripts: answers in order, or hangs.
class FakeFetch {
  final List<Object> script = <Object>[];
  int calls = 0;
  final List<Future<void>> aborts = <Future<void>>[];

  Future<RecipesResponse> call(Uri u, Future<void> abort) {
    calls++;
    aborts.add(abort);
    final next =
        script.isEmpty ? const RecipesResponse(404, '') : script.removeAt(0);
    if (next is RecipesResponse) return Future<RecipesResponse>.value(next);
    if (next is Completer<RecipesResponse>) return next.future; // hangs
    throw next;
  }
}

class Clock {
  int ms = 1000000;
  int call() => ms;
}

void main() {
  late FakeFetch fetch;
  late FakeStorage storage;
  late Clock clock;
  RecipesLoader make({RecipesStorage? s}) => RecipesLoader(
        url: url,
        fetch: fetch.call,
        storage: s ?? storage,
        now: clock.call,
      );

  setUp(() {
    fetch = FakeFetch();
    storage = FakeStorage();
    clock = Clock();
    RecipesLoader.resetShared();
  });

  test('a fetched document is used at once and cached', () async {
    fetch.script.add(RecipesResponse(200, doc()));
    final loader = make();
    expect(loader.current(), isNull);
    await loader.refresh();
    expect(loader.current()!.comboWindowMs, 3000);
    expect(
        loader
            .current()!
            .recipes[EffectQuality.high]![EffectTier.large]!
            .sparks,
        80);
    expect(storage.writes, 1);
    expect(storage.data.keys.single, 'giftingstack:recipes:$url');
  });

  test('uses the cached copy at once and re-validates it', () async {
    fetch.script.add(RecipesResponse(200, doc(largeSparks: 500)));
    final first = make();
    await first.refresh();
    // A new process: new loader, same storage, nothing fetched yet.
    final second = make();
    // The copy is parsed again on read: the new limits apply to old copies.
    expect(
        second
            .current()!
            .recipes[EffectQuality.high]![EffectTier.large]!
            .sparks,
        120);
    expect(fetch.calls, 1);
  });

  test('refreshes at most once per 6 hours', () async {
    fetch.script
      ..add(RecipesResponse(200, doc()))
      ..add(RecipesResponse(200, doc(comboWindowMs: 4000)));
    final loader = make();
    await loader.refresh();
    clock.ms += const Duration(hours: 6).inMilliseconds - 1;
    await loader.refresh();
    expect(fetch.calls, 1);
    clock.ms += 1;
    await loader.refresh();
    expect(fetch.calls, 2);
    expect(loader.current()!.comboWindowMs, 4000);
  });

  test('a clock that went back counts as due', () async {
    fetch.script
      ..add(RecipesResponse(200, doc()))
      ..add(RecipesResponse(200, doc()));
    final loader = make();
    await loader.refresh();
    clock.ms -= 5000;
    await loader.refresh();
    expect(fetch.calls, 2);
  });

  test('backs off after failures: 1 min, 2 min, 4 min ... capped at 6 hours',
      () async {
    final loader = make();
    var expectedWait = const Duration(minutes: 1);
    var calls = 0;
    for (var n = 1; n <= 12; n++) {
      fetch.script.add(const RecipesResponse(500, ''));
      await loader.refresh();
      calls++;
      expect(fetch.calls, calls, reason: 'attempt $n runs');
      final wait = expectedWait > const Duration(hours: 6)
          ? const Duration(hours: 6)
          : expectedWait;
      clock.ms += wait.inMilliseconds - 1;
      await loader.refresh();
      expect(fetch.calls, calls, reason: 'still backing off after failure $n');
      clock.ms += 1;
      expectedWait *= 2;
    }
  });

  test('a success resets the backoff', () async {
    fetch.script.add(const RecipesResponse(500, ''));
    final loader = make();
    await loader.refresh();
    clock.ms += const Duration(minutes: 1).inMilliseconds;
    fetch.script.add(RecipesResponse(200, doc()));
    await loader.refresh();
    expect(loader.current(), isNotNull);
    clock.ms += const Duration(hours: 6).inMilliseconds;
    fetch.script.add(const RecipesResponse(500, ''));
    await loader.refresh();
    // The next failure waits one minute again, not four.
    clock.ms += const Duration(minutes: 1).inMilliseconds;
    fetch.script.add(RecipesResponse(200, doc(comboWindowMs: 5000)));
    await loader.refresh();
    expect(loader.current()!.comboWindowMs, 5000);
  });

  test('not 2xx, not JSON, or an ignored document leave everything as it was',
      () async {
    final loader = make();
    for (final bad in <RecipesResponse>[
      const RecipesResponse(404, ''),
      const RecipesResponse(200, 'not json'),
      const RecipesResponse(200, '{"specVersion":"2.0.0"}'),
      const RecipesResponse(200, '[]'),
    ]) {
      fetch.script.add(bad);
      await loader.refresh();
      clock.ms += const Duration(hours: 7).inMilliseconds;
    }
    expect(fetch.calls, 4);
    expect(loader.current(), isNull);
    expect(storage.writes, 0);
  });

  test('a fetch that throws is a failure, never an error for the app',
      () async {
    fetch.script.add(StateError('offline'));
    await make().refresh();
  });

  testWidgets('gives up after 3 s and aborts the request', (tester) async {
    fetch.script.add(Completer<RecipesResponse>());
    final loader = make();
    var done = false;
    unawaited(loader.refresh().then((_) => done = true));
    await tester.pump(const Duration(milliseconds: 2999));
    expect(done, isFalse);
    var aborted = false;
    unawaited(fetch.aborts.single.then((_) => aborted = true));
    await tester.pump();
    expect(aborted, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(done, isTrue);
    expect(aborted, isTrue);
    expect(loader.current(), isNull);
  });

  test('concurrent refreshes share one request', () async {
    final hang = Completer<RecipesResponse>();
    fetch.script.add(hang);
    final loader = make();
    final a = loader.refresh();
    final b = loader.refresh();
    expect(identical(a, b), isTrue);
    hang.complete(RecipesResponse(200, doc()));
    await Future.wait(<Future<void>>[a, b]);
    expect(fetch.calls, 1);
  });

  test('storage that throws means memory only, and does not break anything',
      () async {
    storage.throws = true;
    fetch.script.add(RecipesResponse(200, doc()));
    final loader = make();
    expect(loader.current(), isNull);
    await loader.refresh();
    expect(loader.current()!.comboWindowMs, 3000);
  });

  test('a broken cache entry is the same as none', () {
    storage.data['giftingstack:recipes:$url'] = '{broken';
    expect(make().current(), isNull);
    storage.data['giftingstack:recipes:$url'] =
        jsonEncode(<String, Object?>{'fetchedAt': 1, 'doc': <Object?>[]});
    expect(make().current(), isNull);
  });

  group('startRemoteRecipes', () {
    test('remoteRecipes: false makes no request, no cache read or write', () {
      final loader = make();
      final started = startRemoteRecipes(
        RemoteRecipesOptions(remoteRecipes: false, loader: loader),
      );
      expect(started, isNull);
      expect(fetch.calls, 0);
      expect(storage.writes, 0);
    });

    test('a version outside the alphabet turns it off (no network)', () {
      expect(
        startRemoteRecipes(
          RemoteRecipesOptions(recipesVersion: '1/0', loader: make()),
        ),
        isNull,
      );
      expect(fetch.calls, 0);
    });

    test('a layer starts one refresh on the given loader', () async {
      fetch.script.add(RecipesResponse(200, doc()));
      final loader = make();
      final started = startRemoteRecipes(RemoteRecipesOptions(loader: loader));
      expect(identical(started, loader), isTrue);
      await loader.refresh(); // shares the request already running
      expect(fetch.calls, 1);
    });

    test('the shared loader of one URL is one object', () {
      expect(
        identical(RecipesLoader.shared(url), RecipesLoader.shared(url)),
        isTrue,
      );
    });
  });

  group('scheduler with a recipe set', () {
    GiftEffectEvent ev(String id, int price, {String sender = 'a'}) =>
        GiftEffectEvent(
          gift: GiftEffectGift(id: id, name: id, price: price),
          sender: sender,
        );

    RemoteRecipeSet remote(Map<String, Object?> json) =>
        parseRemoteRecipes(<String, Object?>{'specVersion': '1.0.0', ...json})!;

    test('remote beats embedded, app thresholds beat remote', () {
      final s = EffectScheduler(now: () => 0)
        ..setOptions(
          EffectSchedulerOptions(
            recipes: remote(<String, Object?>{
              'thresholds': <String, Object?>{
                'mediumFrom': 50,
                'largeFrom': 5000,
              },
              'recipes': <String, Object?>{
                'high': <String, Object?>{
                  'medium': <String, Object?>{'sparks': 7},
                },
              },
            }),
          ),
        );
      final tiers = <EffectTier>[];
      s.listener = EffectSchedulerListener(
        enter: (e) => tiers.add(e.recipe.tier),
      );
      s.play(ev('g', 60)); // medium from 50 (embedded: small)
      s.play(ev('h', 6000, sender: 'b')); // large from 5000
      expect(tiers, <EffectTier>[EffectTier.medium, EffectTier.large]);
      expect(s.active().first.recipe.sparks, 7);

      final s2 = EffectScheduler(now: () => 0)
        ..setOptions(
          EffectSchedulerOptions(
            thresholds: const TierThresholds(mediumFrom: 70),
            recipes: remote(<String, Object?>{
              'thresholds': <String, Object?>{
                'mediumFrom': 50,
                'largeFrom': 5000,
              },
            }),
          ),
        );
      final t2 = <EffectTier>[];
      s2.listener =
          EffectSchedulerListener(enter: (e) => t2.add(e.recipe.tier));
      s2.play(ev('g', 60)); // the app's 70 wins over the remote 50
      s2.play(ev('h', 6000, sender: 'b')); // largeFrom still the remote 5000
      expect(t2, <EffectTier>[EffectTier.small, EffectTier.large]);
    });

    test('effects already running or queued keep their recipe', () {
      final s = EffectScheduler(now: () => 0);
      final before = remote(<String, Object?>{
        'recipes': <String, Object?>{
          'high': <String, Object?>{
            'large': <String, Object?>{'sparks': 10},
          },
        },
      });
      final after = remote(<String, Object?>{
        'recipes': <String, Object?>{
          'high': <String, Object?>{
            'large': <String, Object?>{'sparks': 99},
          },
        },
      });
      s.setOptions(EffectSchedulerOptions(recipes: before));
      final running = s.play(ev('big', 20000)); // starts
      final waiting = s.play(ev('big2', 20000, sender: 'b')); // queued
      s.setOptions(EffectSchedulerOptions(recipes: after));
      s.play(ev('big3', 20000, sender: 'c')); // queued with the new numbers
      expect(s.active().single.id, running);
      expect(s.active().single.recipe.sparks, 10);
      expect(s.queued().map((e) => e.recipe.sparks), <int>[10, 99]);
      expect(s.queued().first.id, waiting);
    });

    test('the combo window is the set\'s unless the app gave one', () {
      var t = 0;
      final s = EffectScheduler(now: () => t);
      s.setOptions(
        EffectSchedulerOptions(
          recipes: remote(<String, Object?>{'comboWindowMs': 1000}),
        ),
      );
      final counts = <int>[];
      s.listener =
          EffectSchedulerListener(notice: (n, _) => counts.add(n.count));
      s.started(s.play(ev('g', 5)));
      t = 1500; // outside 1000, inside the embedded 2500
      s.started(s.play(ev('g', 5)));
      expect(counts, <int>[1, 1]);

      t = 0;
      final app = EffectScheduler(comboWindowMs: 3000, now: () => t);
      app.setOptions(
        EffectSchedulerOptions(
          recipes: remote(<String, Object?>{'comboWindowMs': 1000}),
        ),
      );
      final c2 = <int>[];
      app.listener = EffectSchedulerListener(notice: (n, _) => c2.add(n.count));
      app.started(app.play(ev('g', 5)));
      t = 1500;
      app.started(app.play(ev('g', 5)));
      expect(c2, <int>[1, 2]);
      expect(app.comboWindowMs, 3000);
    });

    test('without a set the embedded values apply, as before', () {
      final s = EffectScheduler(now: () => 0);
      s.play(ev('g', 20000));
      expect(s.active().single.recipe.sparks, 50);
      expect(s.comboWindowMs, 2500);
    });
  });
}
