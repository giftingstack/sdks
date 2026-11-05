import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:giftingstack/giftingstack.dart';

import 'art.dart';
import 'catalog.dart';
import 'coin_store.dart';
import 'demo_data.dart';
import 'dev_menu.dart';
import 'fake_room.dart';
import 'incoming.dart';
import 'mock_client.dart';

/// "Pixel": a fake social app around the Flutter SDK, on a mock client. What a
/// customer would write is the effect layer, the tray, one `GiftWall` per post,
/// one `GiftAwaySummary` and one `GiftLeaderboard`. Everything else (the feed,
/// the tabs, the developer menu behind the logo, the incoming gifts) is only
/// this demo's own pretend app.
void main() => runApp(DemoApp(gifts: loadGifts()));

/// Gifts from other people arrive by themselves (every 20-40 s) when `true`.
/// Off by default: a gift that arrives on its own surprises a test or a
/// screenshot. The developer menu plays them instead.
const bool liveFeed = false;

/// The away card shows the first time after install only. A real app keeps
/// this on disk (and shows the card again when new gifts exist); this demo
/// keeps it in memory, and the developer menu can show it again.
bool demoAwaySeen = false;

const List<String> _senders = [
  'zoe',
  'caleb',
  'elise',
  'mateo',
  'dana',
  'sofia',
  'ben',
  'emma',
];

GiftingTheme _themeOf(DemoTheme t) => switch (t) {
      DemoTheme.dark => darkTheme,
      DemoTheme.light => lightTheme,
      DemoTheme.pink => themeFromAccent('#ff4f9a'),
    };

/// The demo app. [gifts] is the catalog (default: the live library, with the
/// small list as fallback); tests pass their own.
class DemoApp extends StatefulWidget {
  const DemoApp({required this.gifts, super.key});

  final Future<List<Gift>> gifts;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  DemoTheme _theme = DemoTheme.dark;

  @override
  Widget build(BuildContext context) {
    final t = _themeOf(_theme);
    final dark = t.background.computeLuminance() < 0.5;
    return MaterialApp(
      title: 'Pixel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        scaffoldBackgroundColor: t.background,
      ),
      home: DemoScreen(
        gifts: widget.gifts,
        theme: _theme,
        onTheme: (v) => setState(() => _theme = v),
      ),
    );
  }
}

/// The room of the Live tab.
const String liveRoomId = 'live_demo';

/// What a gift sent in the Live tab is addressed to: one of the two sides of the battle.
Post _livePostOf(String id) => Post(
      'live_demo',
      id,
      '${nameOf(id)} is live',
      PostArt.aurora,
      'now',
      0,
    );

/// The height of the bottom navigation bar the live tray stays above.
const double _navHeight = 54;

enum _Tab { feed, top, live, inbox, me }

class DemoScreen extends StatefulWidget {
  const DemoScreen({
    required this.gifts,
    required this.theme,
    required this.onTheme,
    super.key,
  });

  final Future<List<Gift>> gifts;
  final DemoTheme theme;
  final ValueChanged<DemoTheme> onTheme;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  late final MockGiftingClient _client = MockGiftingClient(widget.gifts);
  final GiftEffectController _effects = GiftEffectController();
  final GlobalKey<GiftAwaySummaryState> _awayKey = GlobalKey();
  final GlobalKey<GiftLeaderboardState> _boardKey = GlobalKey();
  final Random _random = Random();
  late final DevMenuModel _menu = DevMenuModel(
    onPlay: (m) => _deliver(Incoming(_chosen(m), _randomSender(), 1)),
    onCombo: _combo,
    onAway: _awayAgain,
    onWallPlus: _wallPlus,
    onReset: _reset,
    onOffline: _setOffline,
    onChanged: () {
      widget.onTheme(_menu.theme);
      if (mounted) setState(() {});
    },
  );

  final List<Timer> _timers = [];
  Timer? _live;

  /// The Live tab's room, joined while the tab is open.
  GiftRoom? _room;

  List<Gift> _catalog = const [];
  String _selectedId = 'sun-dragon';
  GiftTrayNotifier? _tray;
  // The page stays in sight: picking a gift lowers the sheet (collapseOnSelect),
  // the SDK's scrim goes away while it is low, a tap on the scrim closes the
  // tray (scrimTap: dismiss) and the Gift button is tray.toggle().
  bool _trayLive = false;
  String? _trayTo;
  double? _inset;

  _Tab _tab = _Tab.feed;
  final Set<_Tab> _visited = {_Tab.feed};
  LeaderboardBoard _board = LeaderboardBoard.senders;
  int _balance = 0;
  int _received = 214;
  int _wallRefresh = 0;
  int _unread = 0;
  bool _offline = false;
  bool _hidden = false;
  final GlobalKey<GiftInboxState> _inboxKey = GlobalKey();
  List<InboxItem> _inboxItems = const [];

  /// The time of the newest gift the person has seen in the Inbox tab. A real
  /// app keeps it on disk; this demo starts "now" (the seeded gifts count as
  /// seen) and moves it when the tab is viewed.
  int _seenAtMs = DateTime.now().millisecondsSinceEpoch;

  GiftingTheme get _theme => _themeOf(widget.theme);
  bool? get _reduced => _menu.reducedMotion ? true : null;

  @override
  void initState() {
    super.initState();
    widget.gifts.then((gifts) {
      if (!mounted) return;
      setState(() {
        _catalog = gifts;
        if (!gifts.any((g) => g.id == _selectedId) && gifts.isNotEmpty) {
          _selectedId = gifts.first.id;
        }
      });
    });
    unawaited(_syncBalance());
    if (liveFeed) {
      _live = startIncoming(
        gifts: () => _catalog,
        senders: _senders,
        onGift: (i) {
          if (!_offline) _deliver(i);
        },
      );
    }
  }

  @override
  void dispose() {
    _live?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _tray?.dispose();
    _room?.dispose();
    _menu.dispose();
    super.dispose();
  }

  String _randomSender() => _senders[_random.nextInt(_senders.length)];

  Future<void> _syncBalance() async {
    try {
      final me = await _client.getMe();
      if (mounted) setState(() => _balance = me.balance);
    } on GiftingException {
      // Offline: keep the last number.
    }
  }

  // ---- the gift tray: made when a Gift button is pressed, gone after a send

  void _openTray(Post post, {String? giftId, String? roomId}) {
    final old = _tray;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final notifier = GiftTrayNotifier(
      client: _client,
      receiver: post.author,
      effects: _effects,
      reference: post.id,
      roomId: roomId,
      // A tap on the scrim or the Gift button (toggle) closes the tray: let go of it.
      onOpenChange: (open) {
        if (!open) _closeTray();
      },
      onSent: (tx) {
        if (!mounted) return;
        setState(() {
          _balance = tx.senderBalanceAfter;
          _wallRefresh++;
        });
        // The tray stays open after a send, like a live app: tap again for a
        // combo, the Gift button again to close it.
      },
      onError: (e) {
        if (!mounted || e.insufficientBalance) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                e.retryable
                    ? 'Could not send. Check your connection.'
                    : 'Could not send the gift.',
              ),
            ),
          );
      },
    );
    setState(() {
      _tray = notifier;
      _trayLive = roomId != null;
      _trayTo = post.author;
      if (giftId != null) _selectedId = giftId;
    });
  }

  void _closeTray() {
    final n = _tray;
    if (n == null) return;
    setState(() {
      _tray = null;
      _inset = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
  }

  /// "Get coins" opens the (pretend) store; a pack ADDS its coins.
  Future<void> _store() async {
    final coins = await showCoinStore(context, theme: _theme);
    if (coins == null || !mounted) return;
    _client.credit(coins);
    await _syncBalance();
    await _tray?.refresh();
  }

  // ---- incoming gifts

  Gift _chosen(IncomingMode mode) {
    final byPrice = [..._catalog]..sort((a, b) => a.price.compareTo(b.price));
    return switch (mode) {
      IncomingMode.cheapest => byPrice.first,
      IncomingMode.priciest => byPrice.last,
      IncomingMode.random => _catalog[_random.nextInt(_catalog.length)],
      IncomingMode.tray => _catalog.firstWhere(
          (g) => g.id == _selectedId,
          orElse: () => _catalog.first,
        ),
    };
  }

  void _deliver(Incoming inc) {
    if (_catalog.isEmpty) return;
    final g = inc.gift;
    _effects.play(
      GiftEffectEvent(
        gift: GiftEffectGift(
          id: g.id,
          name: g.name,
          price: g.price,
          image: g.animationUrl,
          icon: g.iconUrl,
        ),
        sender: nameOf(inc.sender),
        quantity: inc.quantity,
      ),
    );
    _client.addToWall('ava', g.id, inc.quantity);
    _client.receive(g, inc.sender, inc.quantity);
    setState(() {
      _received += inc.quantity;
      _wallRefresh++;
    });
    _syncInbox();
  }

  /// The Inbox tab asks again once it exists (its `onLoaded` then updates the
  /// badge); before the first visit the app asks for the badge itself.
  void _syncInbox() {
    final shown = _inboxKey.currentState;
    if (shown != null) {
      shown.refresh();
    } else {
      unawaited(_countInbox());
    }
  }

  Future<void> _countInbox() async {
    try {
      final page = await _client.getInbox(limit: 100);
      if (mounted) _inboxLoaded(page.data);
    } on Object catch (_) {
      // The badge stays as it was; the next gift asks again.
    }
  }

  /// A page of the inbox arrived: in the tab it counts as seen, elsewhere it
  /// feeds the badge (`inboxUnread`).
  void _inboxLoaded(List<InboxItem> items) {
    _inboxItems = items;
    if (!mounted) return;
    setState(() {
      if (_tab == _Tab.inbox) {
        _markInboxSeen();
      } else {
        _unread = inboxUnread(items, _seenAtMs);
      }
    });
  }

  void _markInboxSeen() {
    for (final i in _inboxItems) {
      if (i.status != inboxStatusCompleted) continue;
      final at = DateTime.tryParse(i.createdAt)?.millisecondsSinceEpoch;
      if (at != null && at > _seenAtMs) _seenAtMs = at;
    }
    _unread = 0;
  }

  void _combo(IncomingMode mode) {
    if (_catalog.isEmpty) return;
    final inc = Incoming(_chosen(mode), _randomSender(), 1);
    for (var i = 0; i < 5; i++) {
      _timers.add(
        Timer(Duration(milliseconds: i * 250), () {
          if (mounted) _deliver(inc);
        }),
      );
    }
  }

  void _awayAgain() {
    _client.resetAway();
    unawaited(_awayKey.currentState?.check());
  }

  void _wallPlus() {
    if (_catalog.isEmpty) return;
    for (final p in demoPosts) {
      _client.addToWall(
        p.author,
        _chosen(IncomingMode.random).id,
        5,
        p.id,
      );
    }
    _client.addToWall('ava', _chosen(IncomingMode.random).id, 5);
    setState(() => _wallRefresh++);
  }

  void _setOffline(bool on) {
    _client.offline = on;
    setState(() => _offline = on);
    if (!on) {
      setState(() => _wallRefresh++);
      _boardKey.currentState?.refresh();
      unawaited(_syncBalance());
      unawaited(_tray?.refresh());
    }
  }

  void _reset() {
    _closeTray();
    _client.reset();
    _client.resetAway();
    setState(() {
      _received = 214;
      _inboxItems = const [];
      _seenAtMs = DateTime.now().millisecondsSinceEpoch;
      _unread = 0;
      _hidden = false;
      _wallRefresh++;
    });
    _boardKey.currentState?.refresh();
    _inboxKey.currentState?.refresh();
    unawaited(_syncBalance());
    unawaited(_awayKey.currentState?.check());
  }

  // ---- layout

  double _baseNotice(EdgeInsets insets) => 88 + insets.bottom;

  void _select(_Tab t) {
    // The tray stays above the bar, so a tap on the bar closes it.
    if (_tray != null && t != _tab) _closeTray();
    _selectTab(t);
  }

  void _selectTab(_Tab t) {
    setState(() {
      _tab = t;
      _visited.add(t);
      if (t == _Tab.inbox) _markInboxSeen();
      // Joined while the Live tab is open, left when you go elsewhere.
      if (t == _Tab.live) {
        _room ??= _joinRoom();
      } else {
        _room?.dispose();
        _room = null;
      }
    });
    // Opened again: ask again (the first visit loads by itself).
    if (t == _Tab.inbox) _inboxKey.currentState?.refresh();
  }

  /// A real [GiftRoom] on a pretend server: a real app passes no `socket:`
  /// and its own `getToken` (the token carries `rooms` and `name`).
  GiftRoom _joinRoom() => GiftRoom(
        room: liveRoomId,
        getToken: ({required bool forceRefresh}) async => demoRoomToken('ava'),
        client: _client,
        effects: _effects,
        socket: fakeRoomSocketFactory(
          gifts: () => _catalog,
          senders: _senders,
          nameOf: nameOf,
        ),
      );

  /// The bottom bar, flat like the iOS one: icon over label, 50 high plus the
  /// bottom inset (not the tall Material 3 bar).
  Widget _nav(GiftingTheme t, double bottomInset) {
    Widget item(_Tab tab, IconData icon, IconData selectedIcon, String label) {
      final selected = _tab == tab;
      final color = selected ? t.accent : t.muted;
      Widget glyph =
          Icon(selected ? selectedIcon : icon, size: 22, color: color);
      if (tab == _Tab.inbox) {
        glyph = Badge(
          key: const ValueKey<String>('inbox-badge'),
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          child: glyph,
        );
      }
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(tab),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                glyph,
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('nav-bar'),
      height: _navHeight + bottomInset,
      padding: EdgeInsets.only(top: 4, bottom: bottomInset),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          item(_Tab.feed, Icons.home_outlined, Icons.home, 'Feed'),
          item(
              _Tab.top, Icons.emoji_events_outlined, Icons.emoji_events, 'Top'),
          item(_Tab.live, Icons.sensors_outlined, Icons.sensors, 'Live'),
          item(
            _Tab.inbox,
            Icons.notifications_none,
            Icons.notifications,
            'Inbox',
          ),
          item(_Tab.me, Icons.person_outline, Icons.person, 'Me'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final t = _theme;
    final tray = _tray;
    return Scaffold(
      backgroundColor: t.background,
      // `expand`: a tab can be shorter than the screen, and a loose Stack
      // would shrink to it and leave the tray's `Positioned.fill` area short of
      // the bottom.
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              _Header(
                top: insets.top,
                theme: t,
                balance: _balance,
                onLogoHold: () => showDevMenu(context, _menu, () => _theme),
                onCoins: _store,
              ),
              if (_offline)
                Container(
                  key: const ValueKey<String>('offline-banner'),
                  width: double.infinity,
                  color: t.danger.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'You are offline. Showing what was loaded last.',
                    style: TextStyle(color: t.danger, fontSize: 13),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _tab.index,
                  children: [
                    for (final tab in _Tab.values)
                      _visited.contains(tab) ? _tabBody(tab) : const SizedBox(),
                  ],
                ),
              ),
              _nav(t, insets.bottom),
            ],
          ),
          // The tray is a bottom sheet over the whole screen, made when a Gift
          // button is pressed. Its scrim (the SDK's) closes it on a tap.
          if (tray != null) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              // The tray ends where the bar starts: the bar stays in view and in reach.
              bottom: _navHeight + insets.bottom,
              // The sheet slides down out of its box: what is below the box is not drawn.
              child: ClipRect(
                child: ListenableBuilder(
                  listenable: tray,
                  builder: (context, _) => GiftTray(
                    collapseOnSelect: true,
                    scrim: true,
                    scrimTap: ScrimTap.dismiss,
                    tray: tray, // gifts, balance, send and the Test mode badge
                    onTopUp: _store,
                    defaultSelectedId: _selectedId,
                    theme: t,
                    reducedMotion: _reduced,
                    onSelect: (g) => _selectedId = g.id,
                    // The notice follows the sheet's top edge.
                    onInsetChange: (px) {
                      if (mounted) {
                        setState(
                          () => _inset = px + 16 + _navHeight + insets.bottom,
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
          // The "while you were away" card sits above the tray and below the
          // effect layer, which plays its replay.
          Positioned.fill(
            child: GiftAwaySummary(
              key: _awayKey,
              client: _client,
              effects: _effects,
              autoCheck: !demoAwaySeen,
              theme: t,
              quality: _menu.quality,
              reducedMotion: _reduced,
              resolveUsers: demoResolveAway,
              onShow: (_) => demoAwaySeen = true,
            ),
          ),
          Positioned.fill(
            child: GiftEffectLayer(
              controller: _effects,
              quality: _menu.quality,
              theme: t,
              reducedMotion: _reduced,
              noticeBottom: tray != null && _inset != null
                  ? _inset!
                  : _baseNotice(insets),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBody(_Tab tab) => switch (tab) {
        _Tab.feed => _feed(),
        _Tab.top => _top(),
        _Tab.live => _liveTab(),
        _Tab.inbox => _inboxTab(),
        _Tab.me => _me(),
      };

  // ---- Feed

  Widget _feed() => SingleChildScrollView(
        key: const PageStorageKey<String>('feed'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Column(
          children: [
            for (final post in demoPosts)
              _PostCard(
                post: post,
                theme: _theme,
                onGift: () =>
                    _tray != null && _trayTo == post.author && !_trayLive
                        ? _tray!.toggle()
                        : _openTray(post),
                wall: GiftWall(
                  key: ValueKey<String>('wall-${post.id}'),
                  client: _client,
                  user: post.author,
                  reference: post.id,
                  max: 6,
                  refreshKey: _wallRefresh,
                  theme: _theme,
                  reducedMotion: _reduced,
                  onPressChip: (g) => _openTray(post, giftId: g.id),
                ),
              ),
          ],
        ),
      );

  // ---- Top

  Widget _top() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Top'),
            const SizedBox(height: 10),
            Row(
              children: [
                _seg('Top gifters', _board == LeaderboardBoard.senders, () {
                  setState(() => _board = LeaderboardBoard.senders);
                }),
                const SizedBox(width: 8),
                _seg('Top creators', _board == LeaderboardBoard.receivers, () {
                  setState(() => _board = LeaderboardBoard.receivers);
                }),
              ],
            ),
            const SizedBox(height: 12),
            _card(
              GiftLeaderboard(
                key: _boardKey,
                client: _client,
                board: _board,
                theme: _theme,
                metricToggle: true,
                limit: 15,
                reducedMotion: _reduced,
                highlightUser: 'ava',
                resolveUsers: demoResolveUsers,
              ),
            ),
          ],
        ),
      );

  Widget _seg(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _theme.accent : _theme.surface,
            border: Border.all(color: on ? _theme.accent : _theme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? _theme.accentText : _theme.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  // ---- Live (a gift room)

  /// One side's Gift button: opens the tray for that side, closes it when it is
  /// already open for the same side.
  Widget _liveGift(String id, Key key) => GestureDetector(
        key: key,
        onTap: () => _tray != null && _trayLive && _trayTo == id
            ? _tray!.toggle()
            : _openTray(_livePostOf(id), roomId: liveRoomId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _theme.accent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            'Gift ${nameOf(id)}',
            style: TextStyle(
              color: _theme.accentText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  Widget _liveTab() {
    final room = _room;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Live'),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 180,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A2A6B), Color(0xFFE0457B)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Mira is live',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (room != null) ...[
                  // The SDK's battle bar, driven by the room.
                  GiftBattleBar(
                    room: room,
                    theme: _theme,
                    users: {
                      for (final id in const ['mira', 'noor'])
                        id: BattleBarUser(name: nameOf(id)),
                    },
                  ),
                  // Each side's Gift button sits under that side of the bar.
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _liveGift('mira', const ValueKey<String>('live-gift')),
                      _liveGift(
                        'noor',
                        const ValueKey<String>('live-gift-noor'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (room == null)
                  const SizedBox.shrink()
                else
                  ListenableBuilder(
                    listenable: room,
                    builder: (_, __) => Text(
                      '${room.viewers ?? 0} watching · ${room.status.name}',
                      key: const ValueKey<String>('live-status'),
                      style: TextStyle(color: _theme.muted, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Pretend room: other people send gifts every few seconds. '
                  'Yours play at once here and reach the room through roomId.',
                  style: TextStyle(color: _theme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Inbox

  Widget _inboxTab() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Inbox'),
            const SizedBox(height: 12),
            _card(
              GiftInbox(
                key: _inboxKey,
                client: _client,
                theme: _theme,
                reducedMotion: _reduced,
                resolveUsers: demoResolveAway,
                onLoaded: _inboxLoaded,
              ),
            ),
          ],
        ),
      );

  // ---- Me

  Widget _me() {
    final t = _theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [t.accent, const Color(0xFFE0457B)],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(14, -26),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: t.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const _Avatar('ava', size: 72),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ava Carter',
                          style: TextStyle(
                            color: t.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '@ava',
                          style: TextStyle(color: t.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -14),
              child: Row(
                children: [
                  _stat(fmt(_received), 'Gifts received', key: 'me-received'),
                  _stat('1.2K', 'Followers'),
                  _stat('318', 'Following'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.background,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your coins',
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                        Text(
                          fmt(_balance),
                          key: const ValueKey<String>('me-balance'),
                          style: TextStyle(
                            color: t.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey<String>('get-coins'),
                    onPressed: _store,
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: t.accentText,
                    ),
                    child: const Text('Get coins'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Gifts received',
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            GiftWall(
              key: const ValueKey<String>('wall-profile'),
              client: _client,
              user: 'ava',
              max: 8,
              refreshKey: _wallRefresh,
              theme: t,
              reducedMotion: _reduced,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hide me from leaderboards',
                        style: TextStyle(color: t.text, fontSize: 14),
                      ),
                      Text(
                        'Others will not see your rank',
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('hide-switch'),
                  value: _hidden,
                  activeThumbColor: t.accent,
                  onChanged: (v) {
                    _client.hidden = v;
                    setState(() => _hidden = v);
                    _boardKey.currentState?.refresh();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, {String? key}) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              key: key == null ? null : ValueKey<String>(key),
              style: TextStyle(
                color: _theme.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: TextStyle(color: _theme.muted, fontSize: 11)),
          ],
        ),
      );

  Widget _title(String text) => Text(
        text,
        style: TextStyle(
          color: _theme.text,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _theme.surface,
          border: Border.all(color: _theme.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.top,
    required this.theme,
    required this.balance,
    required this.onLogoHold,
    required this.onCoins,
  });

  final double top;
  final GiftingTheme theme;
  final int balance;
  final VoidCallback onLogoHold;
  final VoidCallback onCoins;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, top + 8, 12, 8),
        child: Row(
          children: [
            // The only way to the developer menu: hold the logo for 1 s.
            DevTrigger(
              key: const ValueKey<String>('pixel-logo'),
              onOpen: onLogoHold,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: LinearGradient(
                          colors: [theme.accent, const Color(0xFFE0457B)],
                        ),
                      ),
                      child: const Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pixel',
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              key: const ValueKey<String>('coin-chip'),
              onTap: onCoins,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: theme.surface,
                  border: Border.all(color: theme.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.coin,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      fmt(balance),
                      key: const ValueKey<String>('coin-chip-text'),
                      style: TextStyle(
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.add_circle, size: 16, color: theme.accent),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.id, {required this.size});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: demoUserColors[id] ?? const Color(0xFF6B7A8F),
          shape: BoxShape.circle,
        ),
        child: Text(
          nameOf(id).characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.42,
          ),
        ),
      );
}

class _PostCard extends StatefulWidget {
  const _PostCard({
    required this.post,
    required this.theme,
    required this.onGift,
    required this.wall,
  });

  final Post post;
  final GiftingTheme theme;
  final VoidCallback onGift;
  final Widget wall;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final p = widget.post;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(p.author, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nameOf(p.author),
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      p.ago,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: PostArtView(p.art),
            ),
          ),
          const SizedBox(height: 10),
          Text(p.text, style: TextStyle(color: t.text, fontSize: 15)),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(
                Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: _liked ? const Color(0xFFE0457B) : t.muted,
                ),
                fmt(p.likes + (_liked ? 1 : 0)),
                () => setState(() => _liked = !_liked),
                key: ValueKey<String>('like-${p.id}'),
              ),
              const SizedBox(width: 8),
              _pill(
                Icon(Icons.card_giftcard, size: 18, color: t.accent),
                'Gift',
                widget.onGift,
                key: ValueKey<String>('gift-${p.id}'),
                strong: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          widget.wall,
        ],
      ),
    );
  }

  Widget _pill(
    Widget icon,
    String label,
    VoidCallback tap, {
    required Key key,
    bool strong = false,
  }) {
    final t = widget.theme;
    return GestureDetector(
      key: key,
      onTap: tap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: strong ? t.selected : t.background,
          border: Border.all(color: strong ? t.accent : t.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Display names for the demo's external ids (an app asks its own user table).
Future<Map<String, LeaderboardUser>> demoResolveUsers(List<String> ids) async =>
    {
      for (final id in ids)
        if (demoUserNames[id] != null)
          id: LeaderboardUser(name: demoUserNames[id]!),
    };

/// The same for the away card.
Future<Map<String, AwayUser>> demoResolveAway(List<String> ids) async => {
      for (final id in ids)
        if (demoUserNames[id] != null) id: AwayUser(name: demoUserNames[id]!),
    };
