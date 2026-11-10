import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/client.dart';
import '../core/recipes.dart';
import '../core/rooms.dart';
import '../core/timers.dart';
import '../core/types.dart';
import 'gift_effect_controller.dart';
import 'room_socket.dart';
import 'theme.dart' show giftColorCss;

export '../core/rooms.dart' show RoomGiftEvent, RoomState, RoomStatus;
export 'room_socket.dart' show RoomWebSocketConnector, ioRoomSocketFactory;

/// The app stays connected this long after it went to the background (design
/// 5.2), then the socket closes. Back in the foreground it reconnects with
/// resume.
const Duration giftRoomPauseAfter = Duration(seconds: 60);

/// The `joinRoom` / `useGiftRoom` equivalent: keeps the screen in a gift room
/// (SPEC 17-18). Every gift sent with this `roomId` (see `GiftTrayNotifier`'s
/// `roomId`) plays in [effects] on every viewer's phone. A `ChangeNotifier`
/// around the pure [RoomClient]: it reconnects, resumes after a drop and
/// refreshes the token by itself, and closes the socket 60 seconds after the
/// app went to the background.
///
/// Create it once per room (in a `State`), call [dispose] when the screen
/// closes (it leaves the room). Your server mints the token with `rooms` and
/// `name` (SPEC 17.2); [getToken] is the same function you give
/// `GiftingClient`.
///
/// ```dart
/// final room = GiftRoom(
///   room: 'live_42',
///   getToken: ({required bool forceRefresh}) => myServer.token(),
///   client: client,
///   effects: fx,
/// );
/// ListenableBuilder(
///   listenable: room,
///   builder: (_, __) => Text('${room.viewers ?? 0} watching'),
/// );
/// ```
class GiftRoom extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates the room and joins it (`autoStart`, default true).
  GiftRoom({
    required String room,
    required TokenProvider getToken,
    GiftingClient? client,
    GiftEffectController? effects,
    void Function(RoomGiftEvent event)? onEvent,
    void Function(int viewers)? onViewers,
    void Function()? onGap,
    void Function(RoomBattle? battle)? onBattle,
    bool skipOwn = true,
    int maxReplayAgeMs = defaultMaxReplayAgeMs,
    EffectTier minTier = EffectTier.small,
    TierThresholds thresholds = const TierThresholds(),
    String? Function(String user)? resolveName,
    List<Color>? sideColors,
    String? url,
    bool allowInsecure = false,
    int heartbeatMs = roomHeartbeatMs,
    this.pauseAfter = giftRoomPauseAfter,
    RoomSocketFactory? socket,
    bool autoStart = true,
    bool observeLifecycle = true,
  }) : _effects = effects {
    _client = RoomClient(
      RoomClientOptions(
        room: room,
        getToken: getToken,
        socket: socket ?? ioRoomSocketFactory(),
        url: url,
        allowInsecure: allowInsecure,
        getCatalog: () => _catalog,
        skipOwn: skipOwn,
        maxReplayAgeMs: maxReplayAgeMs,
        minTier: minTier,
        thresholds: thresholds,
        resolveName: resolveName,
        sideColors: sideColors == null
            ? null
            : <String>[for (final c in sideColors) giftColorCss(c)],
        heartbeatMs: heartbeatMs,
        refreshJitterMs: roomRefreshJitterMs,
        onEvent: (event) {
          _effects?.play(event);
          onEvent?.call(event);
        },
        onViewers: onViewers,
        onGap: onGap,
        onBattle: onBattle,
      ),
    );
    _unsubscribe = _client.subscribe(_changed);
    _unsubscribeBattle = _client.subscribeBattle(_changed);
    if (observeLifecycle) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    if (client != null) {
      unawaited(
        client.getGifts().then<void>(
              (gifts) => _catalog = gifts,
              // Only the icon then: the event carries it.
              onError: (Object _) {},
            ),
      );
    }
    if (autoStart) _client.start();
  }

  /// How long the app may stay in the background before the socket closes.
  final Duration pauseAfter;

  final GiftEffectController? _effects;
  late final RoomClient _client;
  late final void Function() _unsubscribe;
  late final void Function() _unsubscribeBattle;
  List<Gift>? _catalog;
  Object? _pauseTimer;
  bool _observing = false;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The battle side [user] is on now (SPEC 18.4): pass it to the tray as
  /// `receiverOf: room.receiverFor` so your own gift says who got it too. Null
  /// outside a round.
  GiftEffectReceiver? receiverFor(String user) => _client.receiverFor(user);

  /// The pure logic underneath, for apps that need more (`start`, `pause`,
  /// `reconnectNow`, `onEvent`).
  RoomClient get controller => _client;

  /// Where the connection is.
  RoomState get state => _client.state;

  /// `idle` (not started), `connecting`, `open`, `reconnecting`, `paused` or
  /// `closed`.
  RoomStatus get status => _client.state.status;

  /// Approximate viewer count, null before the first `welcome`.
  int? get viewers => _client.state.viewers;

  /// The room's battle round as last received (SPEC 18.6); null when there is
  /// none. Listeners are notified when it changes. Headless: draw your own bar.
  RoomBattle? get battle => _client.getBattle();

  /// [battleView] of the current round at the server's time now, null without
  /// a round. Call it again on a timer while the round is open to count down
  /// (it is a pure read of the clock).
  BattleView? get battleView => _client.getBattleView();

  /// Joins the room, when created with `autoStart: false`.
  void start() => _client.start();

  /// The network is back (or the user asked): skips a pending backoff wait, or
  /// starts again after `closed` with the reason `retries_exhausted` or the code
  /// 4011 (SPEC 18.3).
  void reconnectNow() => _client.reconnectNow();

  /// Leaves the room for good (closes the socket). [dispose] does it too.
  void leave() {
    _cancelPauseTimer();
    _client.leave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pauseTimer ??= startTimer(() {
          _pauseTimer = null;
          _client.pause();
        }, pauseAfter.inMilliseconds);
      case AppLifecycleState.resumed:
        _cancelPauseTimer();
        _client.resume();
        _client.reconnectNow();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _cancelPauseTimer() {
    if (_pauseTimer != null) cancelTimer(_pauseTimer);
    _pauseTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPauseTimer();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _client.leave();
    _unsubscribe();
    _unsubscribeBattle();
    super.dispose();
  }
}
