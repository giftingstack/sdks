// A new fixture file in packages/sdk-spec/conformance must not slip past this
// package unnoticed: every file there is either run by a test of ours or is
// explicitly acknowledged as not for this platform (SPEC section 9.3 says
// placement.json is web only: no popover or inline on native).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Fixture file -> the test file of this package that runs it.
const Map<String, String> runners = <String, String>{
  'tiers.json': 'test/conformance_test.dart',
  'combo.json': 'test/conformance_test.dart',
  'client.json': 'test/conformance_test.dart',
  'effects.json': 'test/conformance_test.dart',
  'tray.json': 'test/conformance_test.dart',
  'sheet.json': 'test/sheet_conformance_test.dart',
  'tray-scrim.json': 'test/tray_scrim_conformance_test.dart',
  'theme.json': 'test/theme_conformance_test.dart',
  'remote-recipes.json': 'test/remote_recipes_conformance_test.dart',
  'wall.json': 'test/components_conformance_test.dart',
  'away.json': 'test/components_conformance_test.dart',
  'leaderboard.json': 'test/components_conformance_test.dart',
  'inbox.json': 'test/inbox_conformance_test.dart',
  'rooms-protocol.json': 'test/rooms_conformance_test.dart',
  'rooms-reconnect.json': 'test/rooms_conformance_test.dart',
  'rooms-filter.json': 'test/rooms_conformance_test.dart',
  'rooms-mapping.json': 'test/rooms_conformance_test.dart',
  'rooms-session.json': 'test/rooms_conformance_test.dart',
  'rooms-battle.json': 'test/rooms_conformance_test.dart',
  'battle-bar.json': 'test/battle_bar_conformance_test.dart',
  'pictures.json': 'test/pictures_conformance_test.dart',
};

/// Web only by the SPEC (9.3): native platforms skip these on purpose.
const Set<String> webOnly = <String>{
  'placement.json',
};

void main() {
  test('every conformance fixture is run here or acknowledged as web only', () {
    final dir = Directory('$specDir/conformance');
    expect(dir.existsSync(), isTrue, reason: 'fixtures missing: $specDir');
    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toSet();
    final known = <String>{...runners.keys, ...webOnly};
    expect(
      files.difference(known),
      isEmpty,
      reason: 'New fixture file(s) with no runner in this package. Port the '
          'logic and add a runner, or (only if the SPEC says web only) '
          'acknowledge it in test/fixture_coverage_test.dart.',
    );
    expect(
      known.difference(files),
      isEmpty,
      reason: 'A fixture this package expects is gone from sdk-spec.',
    );
    for (final entry in runners.entries) {
      expect(
        File(entry.value).existsSync(),
        isTrue,
        reason: '${entry.key} needs ${entry.value}',
      );
    }
  });

  test('placement.json is web only: SPEC 9.3 says native keeps the sheet', () {
    final spec = File('$specDir/SPEC.md').readAsStringSync();
    expect(
      spec,
      contains('**Web only**: React Native, Flutter, Android and iOS keep the'),
    );
    final fixture = readFixture('conformance/placement.json');
    expect(fixture.keys, containsAll(<String>['resolve', 'popover']));
  });
}
