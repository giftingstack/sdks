import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../core/effects.dart';
import 'effect_timeline.dart';
import 'images.dart';
import 'theme.dart';

/// How many notice lines the layer stacks at most (newest at the bottom).
const int maxNoticeLines = 3;

/// One line of the notice stack: "ayla sent Rose x3". Slides in from the left,
/// stays and slides out; the combo number pops each time it grows.
///
/// The layer keeps one of these per line, keyed by the notice id, so the slide
/// and the pop keep their state while the line is updated in place. The
/// layer's column lays it out; it does not position itself.
class GiftNotice extends StatefulWidget {
  /// Creates the notice.
  const GiftNotice({
    required this.data,
    required this.visible,
    required this.maxWidth,
    required this.theme,
    required this.imageProvider,
    this.onExited,
    super.key,
  });

  /// What to show.
  final NoticeData data;

  /// Slides in when true, out when false.
  final bool visible;

  /// Called once the line has slid out (after [visible] turned false).
  final VoidCallback? onExited;

  /// Largest width (92 % of the layer).
  final double maxWidth;

  /// Colors.
  final GiftingTheme theme;

  /// Makes the provider for the notice picture.
  final GiftImageProviderBuilder imageProvider;

  @override
  State<GiftNotice> createState() => _GiftNoticeState();
}

/// React Native's `Animated.spring` with friction 4 and tension 160, as
/// physical constants (stiffness and damping converted the way React Native
/// does: Origami tension and friction).
const SpringDescription _popSpring = SpringDescription(
  mass: 1,
  stiffness: (160 - 30) * 3.62 + 194,
  damping: (4 - 8) * 3 + 25,
);

class _GiftNoticeState extends State<GiftNotice> with TickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  int? _lastId;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _lastId = d.id;
    _lastCount = d.count;
    _slide.addStatusListener(_onSlideStatus);
    if (widget.visible) _slide.forward();
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.visible) {
      widget.onExited?.call();
    }
  }

  @override
  void didUpdateWidget(GiftNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    final d = widget.data;
    if (widget.visible) {
      // Already fully in: forward() does nothing, no replay (as the reference).
      _slide.forward();
    } else if (oldWidget.visible) {
      _slide.reverse();
    }
    if (d.id == _lastId && d.count > _lastCount && d.count > 1) {
      _pop.animateWith(SpringSimulation(_popSpring, 1.9, 1, 0));
    }
    _lastId = d.id;
    _lastCount = d.count;
  }

  @override
  void dispose() {
    _slide.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = widget.theme;
    final big = data.big;
    final textColor = big ? theme.noticeBigText : theme.noticeText;
    final image = data.image;
    final initial = data.senderName.isEmpty
        ? ''
        : String.fromCharCode(data.senderName.runes.first).toUpperCase();
    final label = '${data.senderName} sent ${data.giftName}'
        '${data.count > 1 ? ' x${data.count}' : ''}';

    final pill = Container(
      padding: EdgeInsets.fromLTRB(5, big ? 7 : 5, 16, big ? 7 : 5),
      decoration: BoxDecoration(
        color: big ? theme.noticeBigBackground : theme.noticeBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: big ? 34 : 28,
            height: big ? 34 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: theme.accentText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 15 / 12.5,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  'sent ${data.giftName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.92 * textColor.a),
                    fontSize: 12.5,
                    height: 15 / 12.5,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          if (image != null) ...<Widget>[
            const SizedBox(width: 8),
            Image(
              // A fresh Image per picture: one reused Image would show the
              // previous gift's bitmap until the next one has loaded.
              key: ValueKey<String>(image),
              image: widget.imageProvider(image),
              width: big ? 46 : 36,
              height: big ? 46 : 36,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => SizedBox(
                width: big ? 46 : 36,
                height: big ? 46 : 36,
              ),
            ),
          ],
          if (data.count > 1) ...<Widget>[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: AnimatedBuilder(
                animation: _pop,
                builder: (context, child) =>
                    Transform.scale(scale: _pop.value, child: child),
                child: Text(
                  'x${data.count}',
                  key: const ValueKey<String>('gift-combo'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: big ? theme.noticeBigText : theme.comboText,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: label,
        excludeSemantics: true,
        child: AnimatedBuilder(
          animation: _slide,
          child: pill,
          builder: (context, child) {
            final v = _slide.isDismissed && !widget.visible
                ? 0.0
                : _eased(_slide, widget.visible);
            return Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset((v - 1) * 260, 0),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Visible: ease-out back(1.2) on the way in; hidden: ease-in quad on the
  /// way out (the controller runs 1 to 0, so mirror the curve).
  static double _eased(AnimationController c, bool visible) {
    final t = c.value;
    return visible ? backOut(t, 1.2) : 1 - inQuad(1 - t);
  }
}
