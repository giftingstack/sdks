import 'dart:convert';
import 'dart:io';

/// The shared contract lives next to this package: `packages/sdk-spec`.
const String specDir = '../sdk-spec';

/// Reads a JSON file of the shared contract. Throws (loudly) when it is
/// missing: a conformance suite that finds no fixtures must never pass.
Map<String, Object?> readFixture(String relative) {
  final file = File('$specDir/$relative');
  if (!file.existsSync()) {
    throw StateError(
      'Missing ${file.absolute.path}. The conformance fixtures must be at '
      '$specDir (a sibling of packages/sdk-flutter). Run tests from '
      'packages/sdk-flutter.',
    );
  }
  final parsed = jsonDecode(file.readAsStringSync());
  return (parsed as Map<dynamic, dynamic>).cast<String, Object?>();
}

/// Typed helpers for untyped fixture JSON.
Map<String, Object?> asMap(Object? v) =>
    (v! as Map<dynamic, dynamic>).cast<String, Object?>();

/// A JSON list.
List<Object?> asList(Object? v) => (v! as List<dynamic>).cast<Object?>();

/// Deep equality of JSON values: same type, same keys, same values; maps
/// ignore key order, lists do not. Null and a missing key differ.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map<dynamic, dynamic> && b is Map<dynamic, dynamic>) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List<dynamic> && b is List<dynamic>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
