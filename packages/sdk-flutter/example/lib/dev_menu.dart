import 'dart:async';

import 'package:flutter/material.dart';
import 'package:giftingstack/giftingstack.dart';

/// The hidden developer menu of the demo: the only debug surface. Not part of
/// the SDK. Opened by a 1 s long-press on the Pixel logo; never open on
/// launch.

/// Which gift "Play gift" shows.
enum IncomingMode { tray, random, cheapest, priciest }

/// The demo themes.
enum DemoTheme { dark, light, pink }

/// What the menu shows and does. The app owns one and passes it in.
class DevMenuModel extends ChangeNotifier {
  /// Creates the model; the app fills in the callbacks.
  DevMenuModel({
    required this.onPlay,
    required this.onCombo,
    required this.onAway,
    required this.onWallPlus,
    required this.onReset,
    required this.onOffline,
    required this.onChanged,
  });

  /// "Play gift" with the chosen [mode].
  final void Function(IncomingMode mode) onPlay;

  /// "x5 combo".
  final void Function(IncomingMode mode) onCombo;

  /// "Away summary again".
  final VoidCallback onAway;

  /// "Wall +5".
  final VoidCallback onWallPlus;

  /// "Reset demo".
  final VoidCallback onReset;

  /// The mock failure switch.
  final void Function(bool offline) onOffline;

  /// Quality, theme or motion changed (read them from the model).
  final VoidCallback onChanged;

  /// The gift "Play gift" shows.
  IncomingMode mode = IncomingMode.tray;

  /// Effect quality.
  EffectQuality quality = EffectQuality.high;

  /// The theme.
  DemoTheme theme = DemoTheme.dark;

  /// `true`: reduced motion; `false`: follow the system.
  bool reducedMotion = false;

  /// The mock failure switch.
  bool offline = false;

  /// Changes a setting and tells the app.
  void set({
    IncomingMode? mode,
    EffectQuality? quality,
    DemoTheme? theme,
    bool? reducedMotion,
    bool? offline,
  }) {
    this.mode = mode ?? this.mode;
    this.quality = quality ?? this.quality;
    this.theme = theme ?? this.theme;
    this.reducedMotion = reducedMotion ?? this.reducedMotion;
    if (offline != null && offline != this.offline) {
      this.offline = offline;
      onOffline(offline);
    }
    notifyListeners();
    onChanged();
  }
}

/// Wraps [child]: holding a finger on it for [hold] (1 s) calls [onOpen]. A
/// short tap does nothing.
class DevTrigger extends StatefulWidget {
  /// Creates the trigger.
  const DevTrigger({
    required this.child,
    required this.onOpen,
    this.hold = const Duration(seconds: 1),
    super.key,
  });

  /// The logo.
  final Widget child;

  /// Called after the hold.
  final VoidCallback onOpen;

  /// How long to hold.
  final Duration hold;

  @override
  State<DevTrigger> createState() => _DevTriggerState();
}

class _DevTriggerState extends State<DevTrigger> {
  Timer? _timer;

  void _down(PointerDownEvent _) {
    _timer?.cancel();
    _timer = Timer(widget.hold, () {
      _timer = null;
      widget.onOpen();
    });
  }

  void _end(PointerEvent _) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _end,
        onPointerCancel: _end,
        child: widget.child,
      );
}

/// Opens the menu as a modal bottom sheet.
Future<void> showDevMenu(
  BuildContext context,
  DevMenuModel model,
  GiftingTheme Function() theme,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _DevSheet(model: model, themeOf: theme),
    );

class _DevSheet extends StatelessWidget {
  const _DevSheet({required this.model, required this.themeOf});

  final DevMenuModel model;
  final GiftingTheme Function() themeOf;

  GiftingTheme get theme => themeOf();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    // The action buttons close the menu so the effect is not hidden behind it.
    void run(VoidCallback f) {
      Navigator.of(context).pop();
      f();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.85),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: theme.border),
        ),
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Developer menu (not part of the SDK)',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey<String>('dev-done'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  _label('Incoming gift'),
                  _choices<IncomingMode>(
                    const {
                      IncomingMode.tray: 'Same as tray',
                      IncomingMode.random: 'Random',
                      IncomingMode.cheapest: 'Cheapest',
                      IncomingMode.priciest: 'Priciest',
                    },
                    model.mode,
                    (v) => model.set(mode: v),
                  ),
                  _label('Play'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _button(
                        'Play gift',
                        () => run(() => model.onPlay(model.mode)),
                      ),
                      _button(
                        'x5 combo',
                        () => run(() => model.onCombo(model.mode)),
                      ),
                      _button(
                        'Away summary again',
                        () => run(model.onAway),
                      ),
                      _button('Wall +5', model.onWallPlus),
                    ],
                  ),
                  _label('Quality'),
                  _choices<EffectQuality>(
                    const {
                      EffectQuality.high: 'High',
                      EffectQuality.low: 'Low',
                    },
                    model.quality,
                    (v) => model.set(quality: v),
                  ),
                  _label('Theme'),
                  _choices<DemoTheme>(
                    const {
                      DemoTheme.dark: 'Dark',
                      DemoTheme.light: 'Light',
                      DemoTheme.pink: 'Pink',
                    },
                    model.theme,
                    (v) => model.set(theme: v),
                  ),
                  _label('Motion'),
                  _choices<bool>(
                    const {false: 'System', true: 'Reduced'},
                    model.reducedMotion,
                    (v) => model.set(reducedMotion: v),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mock failure: go offline',
                          style: TextStyle(color: theme.text, fontSize: 14),
                        ),
                      ),
                      Switch(
                        key: const ValueKey<String>('dev-offline'),
                        activeThumbColor: theme.accent,
                        value: model.offline,
                        onChanged: (v) => model.set(offline: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _button('Reset demo', () => run(model.onReset)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            color: theme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _choices<T>(Map<T, String> options, T value, ValueChanged<T> on) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in options.entries)
            _pill(e.value, e.key == value, () => on(e.key)),
        ],
      );

  Widget _pill(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? theme.accent : theme.background,
            border: Border.all(color: on ? theme.accent : theme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? theme.accentText : theme.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  Widget _button(String label, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.selected,
            border: Border.all(color: theme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: theme.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
