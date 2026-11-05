import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';

/// Pictures that load or fail when the test says so (on the fake clock), so no
/// test touches the network or the real image decoder.
class ControlledImages {
  ControlledImages({this.autoLoad = false});

  /// Every picture is already there when asked for (a cached picture): the
  /// stream reports synchronously, during the build.
  final bool autoLoad;

  /// URLs the app asked a provider to load, in order.
  final List<String> requested = <String>[];

  ui.Image? _image;
  final Map<String, _Completer> _completers = <String, _Completer>{};

  /// Creates the one test bitmap. Call once at the start of a test.
  Future<void> init(WidgetTester tester) async {
    // A phone-sized screen (400 x 800 dp).
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _image = await tester.runAsync(() => createTestImage(width: 4, height: 4));
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  /// The builder to pass to widgets.
  ImageProvider call(String url) => _Provider(this, url);

  _Completer _completerFor(String url) => _completers.putIfAbsent(url, () {
        requested.add(url);
        final c = _Completer();
        if (autoLoad) c.succeed(_image!);
        return c;
      });

  /// The picture finishes loading now.
  void load(String url) => _completerFor(url).succeed(_image!);

  /// The picture fails to load now.
  void fail(String url) => _completerFor(url).failWith();
}

class _Completer extends ImageStreamCompleter {
  void succeed(ui.Image image) => setImage(ImageInfo(image: image.clone()));

  void failWith() => reportError(
        exception: Exception('picture failed'),
        stack: StackTrace.empty,
        silent: true,
      );
}

class _Provider extends ImageProvider<_Provider> {
  const _Provider(this.owner, this.url);

  final ControlledImages owner;
  final String url;

  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_Provider>(this);

  @override
  ImageStreamCompleter loadImage(_Provider key, ImageDecoderCallback decode) =>
      owner._completerFor(url);

  @override
  bool operator ==(Object other) =>
      other is _Provider && other.url == url && identical(other.owner, owner);

  @override
  int get hashCode => Object.hash(url, identityHashCode(owner));
}

/// A screen with a content area under a full-size layer, like an app.
Widget layerApp({
  required GiftEffectController controller,
  required ControlledImages images,
  bool disableAnimations = false,
  Size size = const Size(400, 800),
  Widget? under,
  EffectQuality quality = EffectQuality.high,
  bool? reducedMotion,
  int Function()? now,
  int pictureWaitMs = 300,
  void Function(GiftEffectEvent, EffectTier)? onEffectEnd,
  Key? layerKey,
  // Tests never touch the network: remote recipes are off unless a test gives
  // a loader with a fake fetch.
  RecipesLoader? recipesLoader,
  int? comboWindowMs,
  GiftingTheme theme = const GiftingTheme(),
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: under ?? const SizedBox.shrink()),
            Positioned.fill(
              child: GiftEffectLayer(
                key: layerKey,
                controller: controller,
                imageProvider: images.call,
                quality: quality,
                reducedMotion: reducedMotion,
                now: now,
                pictureWaitMs: pictureWaitMs,
                onEffectEnd: onEffectEnd,
                remoteRecipes: recipesLoader != null,
                recipesLoader: recipesLoader,
                comboWindowMs: comboWindowMs,
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );

/// A gift event of the given price.
GiftEffectEvent giftEvent(
  String id,
  int price, {
  String? sender,
  int? quantity,
  String? image,
  String? icon,
}) =>
    GiftEffectEvent(
      gift: GiftEffectGift(
        id: id,
        name: id,
        price: price,
        image: image,
        icon: icon,
      ),
      sender: sender,
      quantity: quantity,
    );

/// The tiers of the effects now on screen, in order.
List<EffectTier> tiersOnScreen(WidgetTester tester) => tester
    .widgetList<EffectItem>(find.byType(EffectItem))
    .map((e) => e.recipe.tier)
    .toList();
