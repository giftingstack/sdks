import '../core/away.dart' show AwayEffectPlayer;
import '../core/tray.dart' show EffectPlayer;
import '../core/types.dart';

/// Implemented by the layer's state; the controller calls into it.
abstract interface class GiftEffectHost {
  /// See [GiftEffectController.play].
  int playEffect(GiftEffectEvent event);

  /// See [GiftEffectController.cancel].
  void cancelEffect(int id);

  /// See [GiftEffectController.clear].
  void clearEffects();
}

/// The handle of a `GiftEffectLayer`: call [play] whenever a gift is sent or
/// received. Create it once (for example in a `State`), pass it to the layer
/// and to `GiftTrayNotifier`.
class GiftEffectController implements EffectPlayer, AwayEffectPlayer {
  GiftEffectHost? _host;

  /// True while a `GiftEffectLayer` uses this controller.
  bool get isAttached => _host != null;

  /// Called by the layer; not for apps.
  // ignore: use_setters_to_change_properties
  void attach(GiftEffectHost host) => _host = host;

  /// Called by the layer; not for apps.
  void detach(GiftEffectHost host) {
    if (identical(_host, host)) _host = null;
  }

  /// Shows a gift. Large gifts wait their turn; small and medium ones play at
  /// once. Returns an id for [cancel] (ids start at 1 and are never reused), or
  /// 0 when no layer is attached (nothing is shown).
  @override
  int play(GiftEffectEvent event) => _host?.playEffect(event) ?? 0;

  /// Takes back a gift shown too early, for example because its send failed.
  @override
  void cancel(int id) => _host?.cancelEffect(id);

  /// Stops everything and forgets the queue and the combo run.
  void clear() => _host?.clearEffects();
}
