// conformance/sheet.json against the pure TraySheetController and
// resolveSheetHeights (SPEC 9.1). Format: conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

double? _d(Object? v) => v == null ? null : (v as num).toDouble();

SheetLayout layoutOf(Object? json, Map<String, Object?> named) {
  final m = json is String ? asMap(named[json]) : asMap(json);
  final snaps = <SheetSnap, double?>{};
  if (m['snaps'] != null) {
    asMap(m['snaps']).forEach((k, v) {
      snaps[SheetSnapName.fromWireName(k)!] = _d(v);
    });
  }
  return SheetLayout(
    containerHeight: _d(m['containerHeight'])!,
    snaps: snaps,
    peekMinHeight: _d(m['peekMinHeight']),
    defaultMinHeight: _d(m['defaultMinHeight']),
    contentHeight: _d(m['contentHeight']),
  );
}

Map<String, Object?> heightsJson(SheetHeights h) => <String, Object?>{
      'peek': h.peek,
      'default': h.standard,
      'expanded': h.expanded,
    };

void main() {
  final f = readFixture('conformance/sheet.json');
  final layouts = asMap(f['layouts']);

  test('sheet.json has cases (nothing is silently skipped)', () {
    expect(asList(f['heights']).length, greaterThan(8));
    expect(asList(f['scenarios']).length, greaterThan(15));
  });

  group('resolveSheetHeights', () {
    for (final c in asList(f['heights']).map(asMap)) {
      test(c['name'] as String, () {
        final got = resolveSheetHeights(layoutOf(c['layout'], layouts));
        expect(
          jsonEquals(heightsJson(got), c['expect']),
          isTrue,
          reason: 'got ${heightsJson(got)}, want ${c['expect']}',
        );
      });
    }
  });

  group('TraySheetController', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name'] as String, () {
        final changes = <String>[];
        final sheet = TraySheetController(
          initialSnap: s['initialSnap'] == null
              ? SheetSnap.standard
              : SheetSnapName.fromWireName(s['initialSnap']! as String)!,
          layout: layoutOf(s['layout'], layouts),
          onSnapChange: (snap) => changes.add(snap.wireName),
        );
        var n = 0;
        for (final step in asList(s['steps']).map(asMap)) {
          n++;
          final at = '${s['name']} step $n';
          void returns(Object? got) {
            if (!step.containsKey('returns')) return;
            final want = step['returns'];
            final shown = got is SheetSnap
                ? got.wireName
                : got is ScrollOwner
                    ? got.name
                    : got;
            expect(shown, want, reason: '$at: returns');
          }

          if (step.containsKey('dragStart')) {
            sheet.dragStart();
          } else if (step.containsKey('drag')) {
            sheet.drag(_d(step['drag'])!);
          } else if (step.containsKey('release')) {
            returns(sheet.release(_d(step['release'])!));
          } else if (step.containsKey('cancel')) {
            sheet.cancel();
          } else if (step.containsKey('snapTo')) {
            sheet
                .snapTo(SheetSnapName.fromWireName(step['snapTo']! as String)!);
          } else if (step.containsKey('toggle')) {
            returns(sheet.toggle());
          } else if (step.containsKey('step')) {
            returns(sheet.step(step['step']! as int));
          } else if (step.containsKey('layout')) {
            sheet.setLayout(layoutOf(step['layout'], layouts));
          } else if (step.containsKey('scrollOwner')) {
            final o = asMap(step['scrollOwner']);
            returns(
              sheet.scrollOwner(_d(o['dy'])!, _d(o['gridScrollTop'])!),
            );
          } else if (step.containsKey('expect')) {
            final e = asMap(step['expect']);
            final st = sheet.state;
            final actual = <String, Object?>{
              'snap': st.snap.wireName,
              'offset': st.offset,
              'visibleHeight': st.visibleHeight,
              'dragging': st.dragging,
              'gridScrollable': st.gridScrollable,
              'heights': heightsJson(st.heights),
              'snapChanges': changes,
            };
            e.forEach((k, v) {
              expect(
                jsonEquals(actual[k], v),
                isTrue,
                reason: '$at: $k: got ${actual[k]}, want $v',
              );
            });
          } else {
            fail('$at: unknown step $step');
          }
        }
      });
    }
  });

  test('observers are told only when a field changes', () {
    final sheet = TraySheetController(
      layout: const SheetLayout(
        containerHeight: 800,
        peekMinHeight: 150,
        defaultMinHeight: 330,
        contentHeight: 900,
      ),
    );
    var calls = 0;
    final stop = sheet.subscribe(() => calls++);
    sheet.snapTo(SheetSnap.standard); // already there, nothing moves
    expect(calls, 0);
    sheet.drag(-10); // the drag starts (1) and moves (2)
    expect(calls, 2);
    stop();
    sheet.drag(-10);
    expect(calls, 2);
  });
}
