import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'component_types.dart';
import 'error.dart';
import 'inbox.dart';
import 'os_detect.dart';
import 'secure_url.dart';
import 'types.dart';
import 'uri_encode.dart';

/// The API host used when no `baseUrl` is given.
const String defaultBaseUrl = 'https://api.giftingstack.com';

/// Default time allowed for one HTTP attempt (SPEC 3.4).
const Duration defaultRequestTimeout = Duration(seconds: 20);

/// Returns a client token for the signed-in user. Your own server creates it
/// with `POST /v1/client-tokens`. Called again with `forceRefresh: true` when a
/// token is rejected.
typedef TokenProvider = Future<String> Function({required bool forceRefresh});

/// The header the app-facing API reads where the app runs from (information
/// only: it never changes or refuses a request).
const String platformHeader = 'X-GiftingStack-Platform';

/// The header with the phone's operating system, `ios` or `android`
/// (information only), sent by cross-platform apps such as Flutter.
const String osHeader = 'X-GiftingStack-OS';

/// A fresh idempotency key: a UUID v4.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Client of the GiftingStack `/v1/client` API.
///
/// Extend or implement it to fake the API in your own tests.
class GiftingClient {
  /// Creates a client. [httpClient] is injectable (tests replace it).
  ///
  /// [platform] and [os] tell the dashboard where gifts are sent from
  /// (information only). The default platform is `flutter`; the default
  /// [os] is the phone's (`ios` or `android`), none on desktop and web.
  ///
  /// [timeout] is the time allowed for one HTTP attempt, from sending the
  /// request to reading the whole response (default 20 s, [Duration.zero] turns
  /// it off). A slower attempt ends the call with the same `network_error` as
  /// a lost connection, never retried (SPEC 3.4).
  ///
  /// A plain `http://` [baseUrl] throws an [ArgumentError] unless its host is
  /// localhost, 127.0.0.1, ::1 or 10.0.2.2 (the Android emulator), or
  /// [allowInsecure] is true (development only, SPEC 3.1).
  GiftingClient({
    required this.getToken,
    String baseUrl = defaultBaseUrl,
    http.Client? httpClient,
    String platform = 'flutter',
    String? os,
    Duration timeout = defaultRequestTimeout,
    bool allowInsecure = false,
  })  : _base = _checkedBase(baseUrl, allowInsecure),
        _http = httpClient ?? http.Client(),
        _platform = platform,
        _os = os ?? detectOs(),
        _timeout = timeout;

  /// Gives the token; see [TokenProvider].
  final TokenProvider getToken;

  static String _checkedBase(String baseUrl, bool allowInsecure) {
    assertSecureUrl(baseUrl, allowInsecure, 'baseUrl');
    return baseUrl.replaceFirst(RegExp(r'/+$'), '');
  }

  final String _base;
  final http.Client _http;
  final String _platform;
  final String? _os;
  final Duration _timeout;

  /// `GET /v1/client/gifts`.
  Future<List<Gift>> getGifts() async {
    return _request<List<Gift>>(
      'GET',
      '/v1/client/gifts',
      decode: (body) =>
          _data(body).map((e) => Gift.fromJson(_asMap(e))).toList(),
    );
  }

  /// `GET /v1/client/me`.
  Future<Me> getMe() => _request<Me>(
        'GET',
        '/v1/client/me',
        decode: (body) => Me.fromJson(_asMap(body)),
      );

  /// `GET /v1/client/users/{user}/received-gifts`: a user's gift counters, the
  /// profile wall, or with [reference] one post's wall (SPEC 14.1).
  Future<List<ReceivedGift>> getReceivedGifts(
    String user, [
    String? reference,
  ]) async {
    final path = '/v1/client/users/${encodeUriComponent(user)}/received-gifts'
        '${_query(<(String, Object?)>[('reference', reference)])}';
    return _request<List<ReceivedGift>>(
      'GET',
      path,
      decode: (body) =>
          _data(body).map((e) => ReceivedGift.fromJson(_asMap(e))).toList(),
    );
  }

  /// `POST /v1/client/gift-transactions`. The same idempotency key is used
  /// for every attempt of one call, so a retry never charges twice.
  Future<GiftTransaction> sendGift(SendGiftInput input) async {
    return _request<GiftTransaction>(
      'POST',
      '/v1/client/gift-transactions',
      body: <String, Object?>{
        'receiver': input.receiver,
        'gift_id': input.giftId,
        if (input.quantity != null) 'quantity': input.quantity,
        if (input.message != null) 'message': input.message,
        if (input.reference != null) 'reference': input.reference,
        if (input.roomId != null) 'room_id': input.roomId,
      },
      idempotencyKey: input.idempotencyKey ?? newIdempotencyKey(),
      decode: (body) => GiftTransaction.fromJson(_asMap(body)),
    );
  }

  /// `POST /v1/client/gift-walls/query`: up to 25 walls in one call, answered
  /// in the same order. An empty list makes no request. A read: no
  /// `Idempotency-Key`.
  Future<List<GiftWallResult>> queryGiftWalls(
    List<GiftWallQueryItem> items,
  ) async {
    if (items.isEmpty) return <GiftWallResult>[];
    return _request<List<GiftWallResult>>(
      'POST',
      '/v1/client/gift-walls/query',
      body: <String, Object?>{
        'items': items.map((i) => i.toJson()).toList(),
      },
      decode: (body) =>
          _data(body).map((e) => GiftWallResult.fromJson(_asMap(e))).toList(),
    );
  }

  /// `GET /v1/client/me/away`: gifts the signed-in user received since they
  /// last looked (SPEC 15.1). [since] is an opaque cursor, [maxGroups] 1 to 10.
  Future<AwaySummary> getAway({String? since, int? maxGroups}) async {
    final path = '/v1/client/me/away'
        '${_query(<(String, Object?)>[
          ('since', since),
          ('max_groups', maxGroups)
        ])}';
    return _request<AwaySummary>(
      'GET',
      path,
      decode: (body) => AwaySummary.fromJson(_asMap(body)),
    );
  }

  /// `PUT /v1/client/me/away/cursor`: marks a summary as seen (send its
  /// `cursor` once it was shown). The answer is 204 with no body; nothing is
  /// parsed. The server never moves the cursor back.
  Future<void> ackAway(String cursor) async {
    await _request<void>(
      'PUT',
      '/v1/client/me/away/cursor',
      body: <String, Object?>{'cursor': cursor},
      decode: (_) {},
    );
  }

  /// `GET /v1/client/me/inbox` (SPEC 19.1): gifts the signed-in user received
  /// in the last 24 hours, newest first. [cursor] is the previous page's
  /// `nextCursor`, [limit] 1 to 100 (server default 20).
  Future<Inbox> getInbox({String? cursor, int? limit}) async {
    final path = '/v1/client/me/inbox'
        '${_query(<(String, Object?)>[('cursor', cursor), ('limit', limit)])}';
    return _request<Inbox>(
      'GET',
      path,
      decode: (body) => Inbox.fromJson(_asMap(body)),
    );
  }

  /// `GET /v1/client/leaderboards/{board}` (SPEC 16.1). Query order: period,
  /// metric, at, limit, include_me; [includeMe] is sent only when false.
  Future<Leaderboard> getLeaderboard(
    LeaderboardBoard board, {
    LeaderboardPeriod? period,
    LeaderboardMetric? metric,
    String? at,
    int? limit,
    bool? includeMe,
  }) async {
    final path = '/v1/client/leaderboards/${encodeUriComponent(board.name)}'
        '${_query(<(String, Object?)>[
          ('period', period?.name),
          ('metric', metric?.name),
          ('at', at),
          ('limit', limit),
          ('include_me', includeMe == false ? 'false' : null),
        ])}';
    return _request<Leaderboard>(
      'GET',
      path,
      decode: (body) => Leaderboard.fromJson(_asMap(body)),
    );
  }

  /// `?a=1&b=2` from the pairs whose value is given, in order, values encoded
  /// like `encodeURIComponent`. Empty when nothing is given.
  static String _query(List<(String, Object?)> pairs) {
    final parts = <String>[
      for (final (k, v) in pairs)
        if (v != null) '$k=${encodeUriComponent('$v')}',
    ];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  /// Closes the underlying `http.Client`.
  void close() => _http.close();

  static Map<String, Object?> _asMap(Object? v) {
    if (v is Map<dynamic, dynamic>) return v.cast<String, Object?>();
    throw FormatException('Expected a JSON object, got ${v.runtimeType}.');
  }

  static List<Object?> _data(Object? body) {
    final data = _asMap(body)['data'];
    if (data is List<dynamic>) return data.cast<Object?>();
    throw const FormatException('Expected a "data" array.');
  }

  Future<http.Response> _once(
    String method,
    String path,
    String token,
    Object? body,
    String? idempotencyKey,
    _Attempt attempt,
  ) async {
    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers[platformHeader] = _platform;
    final os = _os;
    if (os != null) request.headers[osHeader] = os;
    if (body != null) {
      // bodyBytes, not body: the `body` setter would append "; charset=utf-8".
      request
        ..headers['Content-Type'] = 'application/json'
        ..bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    try {
      Future<http.Response> go() async =>
          http.Response.fromStream(await _http.send(request));
      // The time covers sending and reading the whole body; a slower attempt
      // (TimeoutException) is a lost connection.
      return _timeout > Duration.zero
          ? await go().timeout(_timeout)
          : await go();
    } on Object catch (e) {
      attempt.timedOut = e is TimeoutException;
      throw const GiftingException(
        0,
        'network_error',
        'Could not reach GiftingStack. Check your connection.',
      );
    }
  }

  static bool _ok(http.Response r) => r.statusCode >= 200 && r.statusCode < 300;

  /// One call (SPEC 3.4). [decode] turns the parsed 2xx body into the typed
  /// answer; a body that is not JSON, or that [decode] cannot read, is
  /// `invalid_response` (SPEC 3.5), never carrying any of the body.
  Future<T> _request<T>(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    required T Function(Object? body) decode,
  }) async {
    // A send (the only call with an idempotency key) that gets no answer at
    // all is repeated once with the same key: if the first one did arrive, the
    // server replays it instead of charging again (SPEC 3.4). A timeout is not
    // repeated.
    var transportRetried = false;
    Future<http.Response> attempt(String token) async {
      final state = _Attempt();
      try {
        return await _once(method, path, token, body, idempotencyKey, state);
      } on GiftingException {
        if (idempotencyKey == null ||
            idempotencyKey.isEmpty ||
            transportRetried ||
            state.timedOut) {
          rethrow;
        }
        transportRetried = true;
        return attempt(token);
      }
    }

    var token = await getToken(forceRefresh: false);
    var res = await attempt(token);
    // A rejected token is usually just an expired one: get a fresh one, once.
    if (res.statusCode == 401) {
      token = await getToken(forceRefresh: true);
      res = await attempt(token);
    }
    // One quiet retry for a server hiccup, same token and same key.
    if (res.statusCode >= 500) {
      res = await attempt(token);
    }
    if (!_ok(res)) throw _errorOf(res);
    // 204 No Content (the away cursor PUT): there is nothing to parse.
    if (res.statusCode == 204) return decode(null);
    try {
      return decode(jsonDecode(utf8.decode(res.bodyBytes)));
    } on Object {
      // Not JSON (a proxy's HTML page, a cut-off body) or not the shape of the
      // model: never show its text.
      throw GiftingException(
        res.statusCode,
        'invalid_response',
        'Invalid response (${res.statusCode}).',
        _header(res, 'x-request-id'),
      );
    }
  }

  /// Header lookup that ignores case (a custom `http.Client` may not lowercase).
  static String? _header(http.Response res, String name) {
    for (final e in res.headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  static GiftingException _errorOf(http.Response res) {
    Map<String, Object?>? error;
    try {
      final parsed = jsonDecode(utf8.decode(res.bodyBytes));
      if (parsed is Map<dynamic, dynamic> &&
          parsed['error'] is Map<dynamic, dynamic>) {
        error =
            (parsed['error'] as Map<dynamic, dynamic>).cast<String, Object?>();
      }
    } on FormatException {
      error = null;
    }
    String? text(String key) {
      final v = error?[key];
      return v is String ? v : null;
    }

    return GiftingException(
      res.statusCode,
      text('type') ?? 'unknown_error',
      text('message') ?? 'Request failed (${res.statusCode}).',
      text('request_id') ?? _header(res, 'x-request-id'),
    );
  }
}

/// What one HTTP attempt learned about its own failure.
class _Attempt {
  bool timedOut = false;
}

/// Same as the [GiftingClient] constructor; the name the other SDKs use.
GiftingClient createGiftingClient({
  required TokenProvider getToken,
  String baseUrl = defaultBaseUrl,
  http.Client? httpClient,
  Duration timeout = defaultRequestTimeout,
  bool allowInsecure = false,
}) =>
    GiftingClient(
      getToken: getToken,
      baseUrl: baseUrl,
      httpClient: httpClient,
      timeout: timeout,
      allowInsecure: allowInsecure,
    );
