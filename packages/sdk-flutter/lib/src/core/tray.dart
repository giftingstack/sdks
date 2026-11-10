/// Everything a gift tray does besides drawing: loads the catalog and the
/// balance, sends gifts, keeps the balance right while the person taps fast
/// (combos) and plays the effect for each gift.
/// Port of `packages/sdk-js/src/core/tray.ts` (SPEC section 8).
library;

import 'dart:async';

import 'client.dart';
import 'error.dart';
import 'types.dart';

/// The part of an effect layer the tray needs.
abstract interface class EffectPlayer {
  /// Shows a gift; returns an id for [cancel].
  int play(GiftEffectEvent event);

  /// Takes back a gift shown too early.
  void cancel(int id);
}

/// When the effect starts.
enum PlayOn {
  /// Play at the tap, take back on failure (default).
  tap,

  /// Play after the server accepted the gift.
  success,
}

/// Settings of a [GiftTrayController]; read again at every use.
class GiftTrayOptions {
  /// Creates options.
  const GiftTrayOptions({
    required this.client,
    required this.receiver,
    this.effects,
    this.playOn = PlayOn.tap,
    this.reference,
    this.roomId,
    this.receiverOf,
    this.onSent,
    this.onError,
    this.prefetch,
  });

  /// The API client.
  final GiftingClient client;

  /// Who gets the gifts: the owner of the post or profile on screen.
  final String receiver;

  /// The effect layer that shows each gift, if there is one right now.
  final EffectPlayer? Function()? effects;

  /// When the effect starts.
  final PlayOn playOn;

  /// Your own context id, for example the post id. Saved with each gift.
  final String? reference;

  /// Room on screen (SPEC 17.1): every send names it, so the room's viewers
  /// see the gift. Null or empty: no room.
  final String? roomId;

  /// In a battle, the side a receiver is on (`room.receiverFor`, SPEC 18.4):
  /// the user's own gift then says who got it, like the room's gifts of the
  /// others. Returns null outside a battle.
  final GiftEffectReceiver? Function(String receiver)? receiverOf;

  /// Called after a successful send.
  final void Function(GiftTransaction transaction)? onSent;

  /// Called for every failed send.
  final void Function(GiftingException error)? onError;

  /// Starts downloading a picture.
  final void Function(String url)? prefetch;
}

/// What a tray shows.
class GiftTrayState {
  /// Creates a state.
  const GiftTrayState({
    this.gifts = const <Gift>[],
    this.balance = 0,
    this.user,
    this.loading = true,
    this.error,
    this.testMode = false,
  });

  /// The catalog, sorted by `sortOrder`.
  final List<Gift> gifts;

  /// Coins (optimistic while sends are in flight).
  final int balance;

  /// The signed-in user as named by the token.
  final String? user;

  /// True until the first refresh ends.
  final bool loading;

  /// The last problem; cleared by the next success.
  final GiftingException? error;

  /// The server said the token is a test token (`me.livemode == false`):
  /// show "Test mode" (`GiftTray.testMode`).
  final bool testMode;
}

/// Any failure as a [GiftingException]. Anything else becomes status 0,
/// `unknown_error`.
GiftingException asGiftingError(Object err) {
  if (err is GiftingException) return err;
  return GiftingException(0, 'unknown_error', _messageOf(err));
}

String _messageOf(Object err) {
  final String text;
  if (err is StateError) {
    text = err.message;
  } else if (err is FormatException) {
    text = err.message;
  } else if (err is ArgumentError) {
    text = '${err.message ?? ''}';
  } else {
    text = err.toString().replaceFirst(RegExp(r'^(Exception|Error): '), '');
  }
  return text.isEmpty ? 'Something went wrong.' : text;
}

/// The tray's logic without any Flutter code. [GiftTrayNotifier] (UI layer)
/// wraps it in a `ChangeNotifier`.
class GiftTrayController {
  /// Creates a controller.
  GiftTrayController(GiftTrayOptions options) : _options = options;

  GiftTrayOptions _options;
  GiftTrayState _state = const GiftTrayState();
  final List<void Function()> _listeners = <void Function()>[];
  int _pending = 0;
  bool _alive = true;

  /// Callbacks and settings are read when used, so they can change.
  // ignore: use_setters_to_change_properties
  void setOptions(GiftTrayOptions options) => _options = options;

  /// The current state.
  GiftTrayState get state => _state;

  /// Calls [listener] after every state change. Returns a function that stops it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The screen is (back) on.
  void attach() => _alive = true;

  /// The screen is gone: answers that arrive later change nothing.
  void dispose() => _alive = false;

  void _set({
    List<Gift>? gifts,
    int? balance,
    String? user,
    bool? loading,
    Object? error = _keep,
    bool? testMode,
  }) {
    _state = GiftTrayState(
      gifts: gifts ?? _state.gifts,
      balance: balance ?? _state.balance,
      user: user ?? _state.user,
      loading: loading ?? _state.loading,
      error:
          identical(error, _keep) ? _state.error : error as GiftingException?,
      testMode: testMode ?? _state.testMode,
    );
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  static const Object _keep = Object();

  /// Reloads the catalog and the balance, for example after buying coins.
  Future<void> refresh() async {
    final client = _options.client;
    try {
      final results = await Future.wait<Object>(
        <Future<Object>>[client.getGifts(), client.getMe()],
        eagerError: true,
      );
      if (!_alive) return;
      final list = results[0] as List<Gift>;
      final me = results[1] as Me;
      // Download the small icons now, while nobody is waiting. A gift's big
      // picture (animationUrl) is fetched lazily: the tray warms the selected
      // gift's and the effect layer loads the others when they play (SPEC 8,
      // audit R-08).
      for (final g in list) {
        final icon = g.iconUrl;
        if (icon != null) _options.prefetch?.call(icon);
      }
      final sorted = List<Gift>.of(list)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _set(
        gifts: sorted,
        balance: me.balance,
        user: me.user,
        error: null,
        testMode: me.livemode == false,
      );
    } on Object catch (err) {
      if (_alive) _set(error: asGiftingError(err));
    } finally {
      if (_alive) _set(loading: false);
    }
  }

  /// After a burst of taps the server's number is the truth.
  Future<void> _reconcile(GiftingClient client) async {
    try {
      final me = await client.getMe();
      if (_alive && _pending == 0) _set(balance: me.balance);
    } on Object {
      // The optimistic number stays; the next send or refresh corrects it.
    }
  }

  /// Sends [gift] with an optimistic balance and the gift's effect.
  Future<void> send(Gift gift) async {
    final options = _options;
    final client = options.client;
    final user = _state.user;
    _pending++;
    // Take the coins at once so the number moves with every tap.
    _set(balance: _state.balance - gift.price);
    int? show(String sender, int quantity) {
      GiftEffectReceiver? battleReceiver;
      try {
        battleReceiver = options.receiverOf?.call(options.receiver);
      } on Object {
        battleReceiver = null; // app code: never let it break a send
      }
      return options.effects?.call()?.play(
            GiftEffectEvent(
              gift: GiftEffectGift(
                id: gift.id,
                name: gift.name,
                price: gift.price,
                image: gift.animationUrl ?? gift.iconUrl,
                icon: gift.iconUrl,
              ),
              sender: sender,
              quantity: quantity,
              receiver: battleReceiver,
            ),
          );
    }

    final early = options.playOn == PlayOn.tap;
    final int? shownId = early ? show(user ?? 'You', 1) : null;
    try {
      final tx = await client.sendGift(
        SendGiftInput(
          receiver: options.receiver,
          giftId: gift.id,
          reference: options.reference,
          roomId: (options.roomId?.isNotEmpty ?? false) ? options.roomId : null,
        ),
      );
      if (!_alive) return;
      _set(error: null);
      // App code from here on: a throwing callback must never look like a
      // failed send (the coins are spent), so it must not reach the catch below
      // that refunds the optimistic balance.
      if (!early) _safe(() => show(user ?? tx.sender, tx.quantity));
      _safe(() => _options.onSent?.call(tx));
    } on Object catch (err) {
      final e = asGiftingError(err);
      // The gift was shown before the server answered: take it back.
      if (shownId != null) _options.effects?.call()?.cancel(shownId);
      if (_alive) _set(balance: _state.balance + gift.price, error: e);
      _safe(() => _options.onError?.call(e));
    } finally {
      _pending--;
      if (_pending == 0) unawaited(_reconcile(client));
    }
  }
}

/// Runs an app callback; whatever it throws is ignored (SPEC 8).
void _safe(void Function() fn) {
  try {
    fn();
  } on Object {
    // The app's problem, not the send's.
  }
}

/// Label key of the tray's send button.
enum SendButtonLabel { send, getCoins, notEnough }

/// What a press does.
enum SendButtonAction { send, topUp, none }

/// The tray's send button state.
class SendButtonState {
  /// Creates a state.
  const SendButtonState({
    required this.selectedId,
    required this.broke,
    required this.label,
    required this.pressable,
    required this.action,
  });

  /// The gift the tray shows as selected, or null for an empty tray.
  final String? selectedId;

  /// The selected gift costs more than the balance.
  final bool broke;

  /// Which label to show.
  final SendButtonLabel label;

  /// Whether the button reacts.
  final bool pressable;

  /// What a press does.
  final SendButtonAction action;
}

/// The tray's Send button. The selected gift is the one with [selectedId], else
/// the first one. Too expensive: "Get coins" when [canTopUp], else "Not enough
/// coins" (off).
SendButtonState sendButtonState({
  required List<Gift> gifts,
  required int balance,
  String? selectedId,
  bool disabled = false,
  bool canTopUp = false,
}) {
  Gift? selected;
  for (final g in gifts) {
    if (g.id == selectedId) {
      selected = g;
      break;
    }
  }
  selected ??= gifts.isEmpty ? null : gifts.first;
  final broke = selected != null && selected.price > balance;
  final canSend = selected != null && !disabled && !broke;
  final label = broke
      ? (canTopUp ? SendButtonLabel.getCoins : SendButtonLabel.notEnough)
      : SendButtonLabel.send;
  final pressable = canSend || (broke && canTopUp && !disabled);
  return SendButtonState(
    selectedId: selected?.id,
    broke: broke,
    label: label,
    pressable: pressable,
    action: !pressable
        ? SendButtonAction.none
        : broke
            ? SendButtonAction.topUp
            : SendButtonAction.send,
  );
}
