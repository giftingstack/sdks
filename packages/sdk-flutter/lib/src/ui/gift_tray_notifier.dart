import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;

import '../core/client.dart';
import '../core/error.dart';
import '../core/input_swap.dart';
import '../core/receivers.dart';
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
    GiftEffectReceiver? Function(String receiver)? receiverOf,
    void Function(GiftTransaction transaction)? onSent,
    void Function(GiftingException error)? onError,
    void Function(String url)? prefetch,
    GiftImageProviderBuilder imageProvider = defaultGiftImageProvider,
    bool autoRefresh = true,
    bool? open,
    void Function(bool open)? onOpenChange,
    FocusNode? input,
    List<TrayReceiver> receivers = const <TrayReceiver>[],
    this.onReceiverChange,
  })  : _input = input,
        _fallback = receiver,
        _receivers = List<TrayReceiver>.unmodifiable(receivers),
        _openState = TrayOpenState(
          // A bound text field: the tray starts closed (SPEC 20.3).
          open: open ?? input == null,
          onChange: onOpenChange,
        ),
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
            receiverOf: receiverOf,
            onSent: onSent,
            onError: onError,
            prefetch: prefetch ?? (url) => warmUpImage(url, imageProvider),
          ),
        ) {
    _unsubscribe = _controller.subscribe(_changed);
    _unsubscribeOpen = _openState.subscribe(_changed);
    _input?.addListener(_inputChanged);
    if (autoRefresh) unawaited(refresh());
  }

  final FocusNode? _input;
  double? _keyboardHeight;

  final String _fallback;
  List<TrayReceiver> _receivers;
  String? _selected;
  String? _last;

  /// The resolved receiver changed (a tap on a side of the "Send to" row,
  /// [selectReceiver], or new [receivers]); SPEC 21.
  void Function(String id)? onReceiverChange;

  /// The sides the tray's "Send to" row picks from (SPEC 21). Empty (the
  /// default): no row, every gift goes to the plain `receiver`. A new list
  /// keeps the pick when it is still in it, else resolves again.
  List<TrayReceiver> get receivers => _receivers;

  set receivers(List<TrayReceiver> value) {
    if (listEquals(value, _receivers)) return;
    final before = receiver;
    _receivers = List<TrayReceiver>.unmodifiable(value);
    _receiverMaybeChanged(before);
    _changed();
  }

  /// Who the next gift goes to (SPEC 21.2): the pick, else the side this
  /// tray gifted last, else the plain `receiver` if it is a side, else the
  /// first side. Without [receivers]: the plain `receiver`.
  String get receiver =>
      resolveReceiver(
        <String>[for (final r in _receivers) r.id],
        selected: _selected,
        last: _last,
        fallback: _fallback,
      ) ??
      _fallback;

  /// Picks the side the next gift goes to (an id not in [receivers] is
  /// ignored). Does not open the tray: the battle bar's `onPressSide` is
  /// `tray..selectReceiver(id)..open()`.
  void selectReceiver(String id) {
    if (!_receivers.any((r) => r.id == id)) return;
    if (_selected == id) return;
    final before = receiver;
    _selected = id;
    _receiverMaybeChanged(before);
    _changed();
  }

  void _receiverMaybeChanged(String before) {
    final now = receiver;
    if (now == before) return;
    try {
      onReceiverChange?.call(now);
    } on Object {
      // App code: never let it break the tray.
    }
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
  /// this is true (SPEC 9.4). Starts true unless you passed `open: false`, or
  /// false when you bound a text field ([inputBound]) and passed no `open`.
  bool get isOpen => _openState.isOpen;

  /// A text field is bound (`GiftTrayNotifier(input: focusNode)`, SPEC 20):
  /// the tray takes the keyboard's place and [toggle] swaps the two.
  bool get inputBound => _input != null;

  /// The last keyboard height seen (logical pixels, at least
  /// [kKeyboardMinHeight]), or null before any. `GiftTray` records it from
  /// `MediaQuery.viewInsetsOf(context).bottom` while a field is bound; it is
  /// kept when the keyboard goes down.
  double? get keyboardHeight => _keyboardHeight;

  /// Records a keyboard height (`GiftTray` calls this). Values below
  /// [kKeyboardMinHeight] are not a keyboard and are ignored. Returns whether
  /// the value changed. Does not notify listeners (it runs during a build).
  bool recordKeyboardHeight(double height) {
    if (!height.isFinite || height < kKeyboardMinHeight) return false;
    if (height == _keyboardHeight) return false;
    _keyboardHeight = height;
    return true;
  }

  /// Shows the tray (the sheet comes back at its `initialSnap`). With a bound
  /// text field the field loses focus first, so the keyboard and the tray are
  /// never up together.
  void open() {
    if (!_openState.isOpen) _blurInput();
    _openState.open();
  }

  /// Hides the tray. Never moves the focus.
  void close() => _openState.close();

  /// Open if closed, close if open: the host's Gift button is `tray.toggle()`.
  /// With a bound text field this is the keyboard swap (SPEC 20.2): opening
  /// takes the focus from the field first; closing gives it back after.
  void toggle() {
    if (_input == null) {
      _openState.toggle();
      return;
    }
    _apply(inputSwapStep(_openState.isOpen, InputSwapEvent.button));
  }

  /// The bound field got focus (a tap on it, or the app focused it): an open
  /// tray closes, the focus stays where it is.
  void _inputChanged() {
    final input = _input;
    if (_disposed || input == null || !input.hasFocus) return;
    _apply(inputSwapStep(_openState.isOpen, InputSwapEvent.inputFocus));
  }

  /// Runs a step in the SPEC's order: blur before open, close before focus.
  void _apply(InputSwapStep step) {
    if (step.input == InputSwapInput.blur) _blurInput();
    if (step.tray == InputSwapTray.open) _openState.open();
    if (step.tray == InputSwapTray.close) _openState.close();
    final input = _input;
    // A node that is not attached to a field (gone, or disposed: dispose
    // detaches it) is never focused.
    if (step.input == InputSwapInput.focus &&
        !_disposed &&
        input != null &&
        input.context != null) {
      input.requestFocus();
    }
  }

  void _blurInput() {
    final input = _input;
    if (input != null && input.hasFocus) input.unfocus();
  }

  /// Reloads the catalog and the balance, for example after buying coins.
  Future<void> refresh() => _controller.refresh();

  /// Sends a gift (optimistic balance, plays the effect) to [receiver]. With
  /// [receivers], a successful send makes its side the default for the next
  /// ones (SPEC 21.2).
  Future<void> send(Gift gift) async {
    final to = receiver;
    final ok = await _controller.send(gift, receiver: to);
    if (!ok || _disposed || _receivers.isEmpty || _last == to) return;
    final before = receiver;
    _last = to;
    _receiverMaybeChanged(before);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _input?.removeListener(_inputChanged);
    _controller.dispose();
    _unsubscribe();
    _unsubscribeOpen();
    super.dispose();
  }
}
