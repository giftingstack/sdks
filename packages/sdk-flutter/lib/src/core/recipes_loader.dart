/// Fetches and caches the remote recipes document (SPEC 13.5). The cached copy
/// is used at once; a refresh runs in the background at most once per 6 hours.
/// Nothing here throws to the app or delays an effect: on any failure the
/// layer keeps the cached or embedded numbers.
///
/// Port of `packages/sdk-js/src/web/recipes-loader.ts`. The network and the
/// storage are injectable. The default storage is memory (no new dependency);
/// pass a [RecipesStorage] backed by your own preferences store to keep the
/// copy between launches.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_recipes.dart';

/// Fetch timeout for the whole response (SPEC 13.5).
const Duration recipesFetchTimeout = Duration(seconds: 3);

/// A successful fetch is reused this long before the next one.
const Duration recipesRefreshAfter = Duration(hours: 6);

/// First wait after a failure; doubles per failure, capped at
/// [recipesRefreshAfter].
const Duration recipesBackoffStart = Duration(seconds: 60);

const String _storagePrefix = 'giftingstack:recipes:';

/// What a fetch answered.
class RecipesResponse {
  /// Creates a response.
  const RecipesResponse(this.statusCode, this.body);

  /// The HTTP status.
  final int statusCode;

  /// The response body text.
  final String body;

  /// 2xx.
  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Does the request. [abort] completes when the loader gave up (timeout): stop
/// the request then. Throwing means failure.
typedef RecipesFetch = Future<RecipesResponse> Function(
  Uri url,
  Future<void> abort,
);

/// The default fetch: `package:http`, one client per request, closed on abort.
Future<RecipesResponse> defaultRecipesFetch(Uri url, Future<void> abort) async {
  final client = http.Client();
  unawaited(abort.then((_) => client.close()));
  try {
    final r = await client.get(url);
    return RecipesResponse(r.statusCode, utf8.decode(r.bodyBytes));
  } finally {
    client.close();
  }
}

/// A tiny key-value store for the cached document. Synchronous on purpose
/// (preferences stores keep an in-memory map). It may throw: the loader then
/// keeps the copy in memory only.
abstract class RecipesStorage {
  /// The value for [key], or null.
  String? read(String key);

  /// Stores [value] under [key].
  void write(String key, String value);
}

/// The default storage: memory only.
class MemoryRecipesStorage implements RecipesStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;
}

/// Loads one remote recipes document and keeps the best copy.
class RecipesLoader {
  /// Creates a loader for [url]. [fetch], [storage] and [now] (ms since the
  /// epoch, wall clock because the copy outlives the process) are injectable.
  RecipesLoader({
    required this.url,
    RecipesFetch? fetch,
    RecipesStorage? storage,
    int Function()? now,
    this.timeout = recipesFetchTimeout,
  })  : _fetch = fetch ?? defaultRecipesFetch,
        _storage = storage ?? MemoryRecipesStorage(),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// The address this loader fetches.
  final String url;

  /// Gives up on a request after this long.
  final Duration timeout;

  final RecipesFetch _fetch;
  final RecipesStorage _storage;
  final int Function() _now;

  bool _loaded = false;
  RemoteRecipeSet? _value;
  int? _fetchedAt;
  int _failures = 0;
  int _backoffUntil = 0;
  Future<void>? _inflight;

  String get _key => '$_storagePrefix$url';

  /// The best document known right now (cached or fetched), or null: use the
  /// embedded set.
  RemoteRecipeSet? current() {
    _load();
    return _value;
  }

  /// Fetches a fresh document when one is due and no attempt is backing off.
  /// Concurrent callers share one request. Never throws.
  Future<void> refresh() {
    _load();
    final running = _inflight;
    if (running != null) return running;
    if (!_due(_now())) return Future<void>.value();
    final attempt = _attempt().whenComplete(() => _inflight = null);
    _inflight = attempt;
    return attempt;
  }

  /// Reads the cache once. The document is parsed again, so new limits apply
  /// to old copies.
  void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = _storage.read(_key);
      if (raw == null || raw.isEmpty) return;
      final entry = jsonDecode(raw);
      if (entry is! Map<String, Object?>) return;
      final parsed = parseRemoteRecipes(entry['doc']);
      final at = entry['fetchedAt'];
      if (parsed != null && at is num) {
        _value = parsed;
        _fetchedAt = at.toInt();
      }
    } on Object {
      // A broken cache entry is the same as none.
    }
  }

  bool _due(int t) {
    if (t < _backoffUntil) return false;
    final at = _fetchedAt;
    if (at == null) return true;
    // A clock that went back counts as due, so a wrong clock cannot pin an
    // old copy forever.
    return t < at || t - at >= recipesRefreshAfter.inMilliseconds;
  }

  Future<void> _attempt() async {
    final abort = Completer<void>();
    try {
      final res = await _fetch(Uri.parse(url), abort.future).timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('recipes: timeout');
        },
      );
      if (!res.ok) throw const FormatException('recipes: http');
      final doc = jsonDecode(res.body);
      final parsed = parseRemoteRecipes(doc);
      if (parsed == null) throw const FormatException('recipes: unusable');
      final t = _now();
      _value = parsed;
      _fetchedAt = t;
      _failures = 0;
      _backoffUntil = 0;
      try {
        _storage.write(
          _key,
          jsonEncode(<String, Object?>{'fetchedAt': t, 'doc': doc}),
        );
      } on Object {
        // Full or blocked storage: keep the copy in memory only.
      }
    } on Object {
      _failures++;
      final waitMs =
          recipesBackoffStart.inMilliseconds * (1 << (_failures - 1));
      final capped =
          waitMs > recipesRefreshAfter.inMilliseconds || _failures > 20
              ? recipesRefreshAfter.inMilliseconds
              : waitMs;
      _backoffUntil = _now() + capped;
    }
  }

  static final Map<String, RecipesLoader> _shared = <String, RecipesLoader>{};

  /// One loader per URL for the whole process, shared by every layer (one
  /// request at a time).
  static RecipesLoader shared(String url) =>
      _shared.putIfAbsent(url, () => RecipesLoader(url: url));

  /// Forget the shared loaders (tests).
  static void resetShared() => _shared.clear();
}

/// The layer options that control remote recipes.
class RemoteRecipesOptions {
  /// Creates the options.
  const RemoteRecipesOptions({
    this.remoteRecipes = true,
    this.recipesVersion,
    this.recipesUrl,
    this.loader,
  });

  /// `false`: no request, no cache read or write, embedded values only.
  final bool remoteRecipes;

  /// Pins the document: `recipes.json` becomes `recipes.<version>.json`.
  final String? recipesVersion;

  /// Default `https://assets.giftingstack.com/recipes.json`.
  final String? recipesUrl;

  /// Use this loader instead of the shared one (tests, your own storage).
  final RecipesLoader? loader;
}

/// The loader for a layer, with its background refresh started, or null when
/// remote recipes are off (`remoteRecipes: false`, or a version that cannot be
/// pinned): no network.
RecipesLoader? startRemoteRecipes(RemoteRecipesOptions options) {
  if (!options.remoteRecipes) return null;
  final url = remoteRecipesUrl(options.recipesUrl, options.recipesVersion);
  if (url == null) return null;
  final loader = options.loader ?? RecipesLoader.shared(url);
  unawaited(loader.refresh());
  return loader;
}
