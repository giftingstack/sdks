/// GiftingStack for Flutter: gift effects, a gift tray, a gift wall, a "while
/// you were away" card, a leaderboard, a battle bar and a small API client.
///
/// The pure Dart part alone is in `package:giftingstack/giftingstack_core.dart`.
library;

export 'giftingstack_core.dart';
export 'src/ui/gift_away_summary.dart'
    show
        AwaySenderInfo,
        AwaySummaryContext,
        AwayUser,
        GiftAwaySummary,
        GiftAwaySummaryState,
        awayResolveWaitMs,
        awayTexts;
export 'src/ui/gift_battle_bar.dart' show BattleBarUser, GiftBattleBar;
export 'src/ui/gift_button.dart' show GiftButton, GiftButtonSize, GiftGlyphPainter;
export 'src/ui/gift_effect_controller.dart';
export 'src/ui/gift_effect_layer.dart';
export 'src/ui/gift_inbox.dart' show GiftInbox, GiftInboxState;
export 'src/ui/gift_leaderboard.dart'
    show
        GiftLeaderboard,
        GiftLeaderboardState,
        LeaderboardRowContext,
        LeaderboardUser;
export 'src/ui/gift_room.dart'
    show
        GiftRoom,
        giftRoomPauseAfter,
        ioRoomSocketFactory,
        RoomWebSocketConnector;
export 'src/ui/gift_tray.dart';
export 'src/ui/gift_tray_notifier.dart';
export 'src/ui/gift_wall.dart'
    show GiftWall, GiftWallSize, WallChipContext, giftWallLoaderFor;
export 'src/ui/images.dart'
    show
        GiftImageProviderBuilder,
        GiftNetworkImage,
        GiftPictureException,
        defaultGiftImageProvider,
        warmUpImage;
export 'src/ui/labels.dart' show GiftLabels, fillLabel;
export 'src/ui/theme.dart'
    show GiftingTheme, darkTheme, lightTheme, themeFromAccent;
