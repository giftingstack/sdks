# GiftingStack Flutter example

"Pixel": a fake social app that shows ONE example integration of the `giftingstack` package (tray, effect
layer, gift wall, away summary, leaderboard) on a mock client (250 ms of fake delay, 60,000 coins, the real
gift pictures from `assets.giftingstack.com`). Tabs: Feed, Top, Inbox, Me. There are no debug buttons on
screen: long-press the Pixel logo for 1 s to open the "Developer menu (not part of the SDK)" (incoming gift,
x5 combo, away summary again, wall +5, quality, theme, motion, reset, mock failure).

```bash
flutter pub get
flutter run
flutter test
```

The `android/` and `ios/` platform folders are included.
See `../README.md` for the package itself and what has been verified.
