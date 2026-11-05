// Runs one client scenario (conformance/README.md, "client.json") against the
// Dart client. Shared by client.json and the `client` sections of wall.json,
// away.json and leaderboard.json. Reference: packages/sdk-js/test/client-runner.ts.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';
import 'package:http/http.dart' as http;

import 'fixtures.dart';

/// The six error fields the fixtures compare.
Map<String, Object?> errorFields(GiftingException e) => <String, Object?>{
      'status': e.status,
      'type': e.type,
      'message': e.message,
      'requestId': e.requestId,
      'retryable': e.retryable,
      'insufficientBalance': e.insufficientBalance,
    };

final RegExp _uuidLike = RegExp(r'^[0-9A-Fa-f-]{16,255}$');

/// Answers requests from the fixture. A mismatch cannot be thrown from here
/// (the client turns any exception into a network error), so it is recorded in
/// [problems] and checked after the call.
class ScriptedHttp extends http.BaseClient {
  ScriptedHttp(this.exchanges);

  final List<Map<String, Object?>> exchanges;

  final List<String> problems = <String>[];
  final List<Map<String, String>> seen = <Map<String, String>>[];
  int count = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final n = count++;
    final at = 'request ${n + 1}';
    if (n >= exchanges.length) {
      problems.add('unexpected $at: ${request.method} ${request.url}');
      throw http.ClientException('unexpected request');
    }
    final ex = exchanges[n];
    final want = asMap(ex['request']);
    if (request.method != want['method']) {
      problems.add('$at method ${request.method} != ${want['method']}');
    }
    if (request.url.toString() != want['url']) {
      problems.add('$at url ${request.url} != ${want['url']}');
    }
    final headers = <String, String>{
      for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
    };
    seen.add(headers);
    asMap(want['headers']).forEach((k, v) {
      final got = headers[k.toLowerCase()];
      final value = v! as String;
      final same = RegExp(r'^<same-as-request:(\d+)>$').firstMatch(value);
      if (value == '<any-uuid-like>') {
        if (got == null || !_uuidLike.hasMatch(got)) {
          problems.add('$at header $k: "$got" is not uuid-like');
        }
      } else if (same != null) {
        final other = seen[int.parse(same.group(1)!) - 1][k.toLowerCase()];
        if (got == null || got != other) {
          problems.add(
              '$at header $k: "$got" != request ${same.group(1)} "$other"');
        }
      } else if (got != value) {
        problems.add('$at header $k: "$got" != "$value"');
      }
    });
    for (final k in asList(want['absentHeaders']).cast<String>()) {
      if (headers.containsKey(k.toLowerCase())) {
        problems.add('$at header $k must be absent');
      }
    }
    final bytes = request is http.Request ? request.bodyBytes : <int>[];
    if (want['body'] == null) {
      if (bytes.isNotEmpty) problems.add('$at body must be empty');
    } else {
      Object? parsed;
      try {
        parsed = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        problems.add('$at body is not JSON');
      }
      if (!jsonEquals(parsed, want['body'])) {
        problems.add('$at body $parsed != ${want['body']}');
      }
    }
    if (ex['networkError'] == true) throw http.ClientException('offline');
    final r = asMap(ex['response']);
    final String text;
    if (r.containsKey('bodyText')) {
      text = r['bodyText']! as String;
    } else {
      text = jsonEncode(r['body']);
    }
    final status = r['status']! as int;
    return http.StreamedResponse(
      // A 204 has no body: build the response without one.
      status == 204
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(text)),
      status,
      headers: asMap(r['headers']).cast<String, String>(),
    );
  }
}

/// Runs the scenario [s] and checks everything (transport, tokens, outcome,
/// the number of requests and token calls).
Future<void> runClientScenario(Map<String, Object?> s) async {
  final tokens = asList(s['tokens']).map(asMap).toList();
  final tokenCalls = <bool>[];
  final tokenProblems = <String>[];
  Future<String> getToken({required bool forceRefresh}) async {
    final k = tokenCalls.length;
    tokenCalls.add(forceRefresh);
    if (k >= tokens.length) {
      tokenProblems.add('unexpected getToken call #${k + 1}');
      return 'unexpected';
    }
    if (tokens[k]['forceRefresh'] != forceRefresh) {
      tokenProblems.add('getToken #${k + 1} forceRefresh=$forceRefresh');
    }
    return tokens[k]['returns']! as String;
  }

  final transport = ScriptedHttp(asList(s['exchanges']).map(asMap).toList());
  final baseUrl = s['baseUrl'] as String?;
  final client = baseUrl == null
      ? GiftingClient(getToken: getToken, httpClient: transport)
      : GiftingClient(
          getToken: getToken,
          baseUrl: baseUrl,
          httpClient: transport,
        );

  final call = asMap(s['call']);
  final args = call['args'] == null ? <String, Object?>{} : asMap(call['args']);
  Future<Object?> run() async {
    switch (call['method']) {
      case 'getGifts':
        return (await client.getGifts()).map((g) => g.toJson()).toList();
      case 'getMe':
        return (await client.getMe()).toJson();
      case 'getReceivedGifts':
        return (await client.getReceivedGifts(
          args['user']! as String,
          args['reference'] as String?,
        ))
            .map((g) => g.toJson())
            .toList();
      case 'sendGift':
        final i = asMap(args['input']);
        return (await client.sendGift(
          SendGiftInput(
            receiver: i['receiver']! as String,
            giftId: i['giftId']! as String,
            quantity: i['quantity'] as int?,
            message: i['message'] as String?,
            reference: i['reference'] as String?,
            idempotencyKey: i['idempotencyKey'] as String?,
          ),
        ))
            .toJson();
      case 'queryGiftWalls':
        return (await client.queryGiftWalls(
          asList(args['items'])
              .map(asMap)
              .map(
                (i) => GiftWallQueryItem(
                  receiver: i['receiver']! as String,
                  reference: i['reference'] as String?,
                ),
              )
              .toList(),
        ))
            .map((w) => w.toJson())
            .toList();
      case 'getAway':
        final q =
            args['query'] == null ? <String, Object?>{} : asMap(args['query']);
        return (await client.getAway(
          since: q['since'] as String?,
          maxGroups: q['maxGroups'] as int?,
        ))
            .toJson();
      case 'ackAway':
        await client.ackAway(args['cursor']! as String);
        return null;
      case 'getInbox':
        final q =
            args['query'] == null ? <String, Object?>{} : asMap(args['query']);
        return (await client.getInbox(
          cursor: q['cursor'] as String?,
          limit: q['limit'] as int?,
        ))
            .toJson();
      case 'getLeaderboard':
        final q =
            args['query'] == null ? <String, Object?>{} : asMap(args['query']);
        return (await client.getLeaderboard(
          LeaderboardBoard.values.byName(args['board']! as String),
          period: q['period'] == null
              ? null
              : LeaderboardPeriod.values.byName(q['period']! as String),
          metric: q['metric'] == null
              ? null
              : LeaderboardMetric.values.byName(q['metric']! as String),
          at: q['at'] as String?,
          limit: q['limit'] as int?,
          includeMe: q['includeMe'] as bool?,
        ))
            .toJson();
    }
    throw StateError('unknown call ${call['method']}');
  }

  Object? result;
  Object? failure;
  try {
    result = await run();
  } on Object catch (e) {
    failure = e;
  }
  expect(transport.problems, isEmpty, reason: 'transport');
  expect(tokenProblems, isEmpty, reason: 'tokens');
  if (s['error'] != null) {
    expect(failure, isA<GiftingException>(), reason: 'expected an error');
    expect(
      jsonEquals(errorFields(failure! as GiftingException), s['error']),
      isTrue,
      reason: '${errorFields(failure as GiftingException)} != ${s['error']}',
    );
  } else {
    if (failure != null) throw failure;
    final want = s['result'];
    expect(
      jsonEquals(result, want),
      isTrue,
      reason: 'result ${jsonEncode(result)} != ${jsonEncode(want)}',
    );
  }
  expect(transport.count, asList(s['exchanges']).length,
      reason: 'requests made');
  expect(tokenCalls.length, tokens.length, reason: 'getToken calls');
}
