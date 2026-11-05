// The effect layer with remote recipes (SPEC 13): the cached or fetched set is
// used for NEW effects, the app's own options still win, and effects already
// on screen keep the recipe they started with.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';

import 'support/ui_harness.dart';

const String url = 'https://example.test/recipes.json';

class _Storage implements RecipesStorage {
  final Map<String, String> data = <String, String>{};
  @override
  String? read(String key) => data[key];
  @override
  void write(String key, String value) => data[key] = value;
}

String doc(int sparks, {int? medium}) => jsonEncode(<String, Object?>{
      'specVersion': '1.0.0',
      'thresholds': <String, Object?>{
        'mediumFrom': medium ?? 100,
        'largeFrom': 10000,
      },
      'recipes': <String, Object?>{
        'high': <String, Object?>{
          'large': <String, Object?>{'sparks': sparks},
        },
      },
    });

void main() {
  late GiftEffectController fx;
  late ControlledImages images;
  late _Storage storage;
  late List<String> bodies;
  late int clock;

  RecipesLoader loader() => RecipesLoader(
        url: url,
        storage: storage,
        now: () => clock,
        fetch: (uri, abort) async => bodies.isEmpty
            ? const RecipesResponse(404, '')
            : RecipesResponse(200, bodies.removeAt(0)),
      );

  setUp(() {
    fx = GiftEffectController();
    storage = _Storage();
    bodies = <String>[];
    clock = 1000;
  });

  Future<void> start(WidgetTester tester, RecipesLoader? l) async {
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    await tester.pumpWidget(
      layerApp(controller: fx, images: images, recipesLoader: l),
    );
  }

  List<int> sparksOnScreen(WidgetTester tester) => tester
      .widgetList<EffectItem>(find.byType(EffectItem))
      .map((e) => e.recipe.sparks)
      .toList();

  testWidgets('a cached copy is used by the very first effect', (tester) async {
    storage.data['giftingstack:recipes:$url'] = jsonEncode(
        <String, Object?>{'fetchedAt': clock, 'doc': jsonDecode(doc(11))});
    await start(tester, loader());
    fx.play(giftEvent('big', 20000));
    await tester.pump();
    expect(sparksOnScreen(tester), <int>[11]);
  });

  testWidgets('no loader (remoteRecipes: false): the embedded numbers',
      (tester) async {
    await start(tester, null);
    fx.play(giftEvent('big', 20000));
    await tester.pump();
    expect(sparksOnScreen(tester), <int>[50]);
  });

  testWidgets(
      'the first effect never waits for the network; the next one '
      'uses the fetched set, the one on screen keeps its recipe',
      (tester) async {
    final answer = Completer<RecipesResponse>();
    final l = RecipesLoader(
      url: url,
      storage: storage,
      now: () => clock,
      fetch: (uri, abort) => answer.future,
    );
    await start(tester, l);
    fx.play(giftEvent('first', 350)); // medium, embedded: 24 sparks
    await tester.pump();
    expect(sparksOnScreen(tester), <int>[24]);
    answer.complete(
      RecipesResponse(
        200,
        jsonEncode(<String, Object?>{
          'specVersion': '1.0.0',
          'recipes': <String, Object?>{
            'high': <String, Object?>{
              'medium': <String, Object?>{'sparks': 5},
            },
          },
        }),
      ),
    );
    await tester.runAsync(l.refresh);
    fx.play(giftEvent('second', 350, sender: 'b'));
    await tester.pump();
    expect(sparksOnScreen(tester), <int>[24, 5]);
  });

  testWidgets('the app\'s thresholds beat the remote ones', (tester) async {
    storage.data['giftingstack:recipes:$url'] = jsonEncode(
      <String, Object?>{
        'fetchedAt': clock,
        'doc': jsonDecode(doc(11, medium: 50))
      },
    );
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    // Remote says medium from 50: a 60-coin gift is medium.
    await tester.pumpWidget(
      layerApp(controller: fx, images: images, recipesLoader: loader()),
    );
    fx.play(giftEvent('g', 60));
    await tester.pump();
    expect(tiersOnScreen(tester), <EffectTier>[EffectTier.medium]);
  });
}
