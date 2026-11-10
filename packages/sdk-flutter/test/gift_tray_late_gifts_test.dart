// The tray opens before its gifts arrive (the app fetches the catalog when the tray is made):
// the sheet's box grows when they do. The sheet must settle at its default place without ever
// being drawn above it (it used to flash at the top, then drop: the spring started from an
// offset that belonged to the old, shorter box).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/ui_harness.dart';

List<Gift> catalog(int n) => <Gift>[
      for (var i = 0; i < n; i++)
        Gift(
          id: 'g$i',
          name: 'Gift $i',
          price: 10 + i,
          sortOrder: i,
          iconUrl: 'https://assets.test/g$i/256.webp',
        ),
    ];

void main() {
  for (final lateFrames in <int>[1, 3, 10]) {
    testWidgets(
      'gifts arriving $lateFrames frames after the tray never push the sheet above its place',
      (tester) async {
        final images = ControlledImages();
        await images.init(tester);
        tester.view.physicalSize = const Size(400, 800);
        final gifts = ValueNotifier<List<Gift>>(<Gift>[]);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(400, 800)),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ValueListenableBuilder<List<Gift>>(
                      valueListenable: gifts,
                      builder: (context, list, _) => GiftTray(
                        gifts: list,
                        balance: 100000,
                        onSend: (g) {},
                        scrim: true,
                        collapseOnSelect: true,
                        imageProvider: images.call,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        const trayKey = ValueKey<String>('gift-tray');
        final tops = <double>[];
        for (var f = 0; f < 90; f++) {
          if (f == lateFrames) gifts.value = catalog(15);
          await tester.pump(const Duration(milliseconds: 16));
          final finder = find.byKey(trayKey);
          if (finder.evaluate().isNotEmpty) tops.add(tester.getTopLeft(finder).dy);
        }
        final settled = tops.last;
        expect(settled, lessThan(600), reason: 'the grid is open at its default place');
        for (final t in tops) {
          expect(t, greaterThanOrEqualTo(settled - 1), reason: 'drawn above its place: $tops');
        }
        // And it only ever moves down once the gifts are in (no bounce back up).
        final fromGifts = tops.skip(lateFrames + 1).toList();
        for (var i = 1; i < fromGifts.length; i++) {
          expect(fromGifts[i], lessThanOrEqualTo(fromGifts[i - 1] + 0.5), reason: '$fromGifts');
        }
      },
    );
  }
}
