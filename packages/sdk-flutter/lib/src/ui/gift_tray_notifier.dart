import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/client.dart';
import '../core/error.dart';
import '../core/scrim.dart';
import '../core/tray.dart';
import '../core/types.dart';
import 'gift_effect_controller.dart';
import 'images.dart';

/// The `useGiftTray` equivalent: a `ChangeNotifier` around the pure
/// [GiftTrayController]. Create it in a `State` (or with a provider), pass
/// [GiftEffectController] as [effects], call [refresh] once when the screen
/// opens and [dispose] when it closes.
///
/// ```dart
/// final tray = GiftTrayNotifier(client: client, receiver: 'mert', effects: fx);
/// GiftTray(tray: tray); // gifts, balance, send and the "Test mode" badge
/// // Or wire it yourself:
/// ListenableBuilder(
///   listenable: tray,
///   builder: (_, __) => GiftTray(
///     gifts: tray.gifts, balance: tray.balance, onSend: tray.send,
///     testMode: tray.testMode),
/// );
/// ```
class GiftTrayNotifier extends ChangeNotifier {
  /// Creates the notifier and starts loading (`autoRefresh`, default true).
  GiftTrayNotifier({
    required GiftingClient client,
    required String receiver,
    GiftEffectController? effects,
    PlayOn playOn = PlayOn.tap,
    String? reference,
    String? roomId,
    void Function(GiftTransaction transaction)? onSent,
    void Function(GiftingException error)? onError,
    void Function(String url)? prefetch,
    GiftImageProviderBuilder imageProvider = defaultGiftImageProvider,
    bool autoRefresh = true,
    bool open = true,
    void Function(bool open)? onOpenChange,
  })  : _openState = TrayOpenState(open: open, onChange: onOpenChange),
        _controller = GiftTrayController(
          GiftTrayOptions(
            client: client,
            receiver: receiver,
            effects: effects == null
                ? null
                : () => effects.isAttached ? effects : null,
            playOn: playOn,
            reference: reference,
            roomId: roomId,
            onSent: onSent,
            onError: onError,
            prefetch: prefetch ?? (url) => warmUpImage(url, imageProvider),
          ),
        ) {
    _unsubscribe = _controller.subscribe(_changed);
    _unsubscribeOpen = _openState.subscribe(_changed);
    if (autoRefresh) unawaited(refresh());
  }

  final GiftTrayController _controller;
  final TrayOpenState _openState;
  late final void Function() _unsubscribe;
  late final void Function() _unsubscribeOpen;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The pure logic underneath, for apps that need more.
  GiftTrayController get controller => _controller;

  /// The catalog, sorted.
  List<Gift> get gifts => _controller.state.gifts;

  /// Coins; optimistic while sends are in flight.
  int get balance => _controller.state.balance;

  /// The signed-in user as named by the token.
  String? get user => _controller.state.user;

  /// True until the first refresh ends.
  bool get loading => _controller.state.loading;

  /// The last problem; cleared by the next success.
  GiftingException? get error => _controller.state.error;

  /// The token was made with a test key (`me.livemode == false`). `GiftTray(tray: this)`
  /// shows the "Test mode" badge from it by itself.
  bool get testMode => _controller.state.testMode;

  /// Whether the tray is open. `GiftTray(tray: this)` shows itself only while
  /// this is true (SPEC 9.4). Starts true unless you passed `open: false`.
  bool get isOpen => _openState.isOpen;

  /// Shows the tray (the sheet comes back at its `initialSnap`).
  void open() => _openState.open();

  /// Hides the tray.
  void close() => _openState.close();

  /// Open if closed, close if open: the host's Gift button is `tray.toggle()`.
  void toggle() => _openState.toggle();

  /// Reloads the catalog and the balance, for example after buying coins.
  Future<void> refresh() => _controller.refresh();

  /// Sends a gift (optimistic balance, plays the effect).
  Future<void> send(Gift gift) => _controller.send(gift);

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _unsubscribe();
    _unsubscribeOpen();
    super.dispose();
  }
}
