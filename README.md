# GiftingStack SDKs

Client libraries for [GiftingStack](https://giftingstack.com), a virtual gifting API for apps: your
users send each other gifts, and everyone sees them. Version 0.1.4.

Gifts are a virtual currency inside your app. No real money moves through GiftingStack, and a
received gift never becomes spendable balance.

| Platform | Package | Folder |
| --- | --- | --- |
| Web, React Native, Expo | `@giftingstack/sdk` (npm) | [packages/sdk-js](packages/sdk-js) |
| Flutter | `giftingstack` (pub.dev) | [packages/sdk-flutter](packages/sdk-flutter) |
| Android (Kotlin, Jetpack Compose) | `com.giftingstack:giftingstack` (Maven Central) | [packages/sdk-android](packages/sdk-android) |
| iOS (Swift, SwiftUI) | `GiftingStack` (Swift Package Manager, this repository) | [packages/sdk-ios](packages/sdk-ios) |
| Shared contract (not an SDK, nothing to install) | the spec and the conformance fixtures every SDK tests against | [packages/sdk-spec](packages/sdk-spec) |

## What is in it

- **Gift tray.** A bottom sheet with the user's balance, a grid of gifts with pictures and a Send
  button. Three heights (peek, default, expanded), an optional dim behind it, and open, close and
  toggle calls so your own Gift button controls it. On the web it can also be a popover or sit inline.
- **Gift effects.** What the receiver sees depends on the price: a small gift floats up with a
  combo counter, a medium one flies to the middle and bursts, a large one dims the screen with light
  rays, coin rain and a golden notice. Quality levels, reduced-motion support, and effect numbers
  you can tune from outside the app without a release.
- **Gift wall.** The gifts a user has received, as chips with counts and a "+37" overflow chip.
- **Gift inbox.** Who sent the signed-in user which gift and when, over the last 24 hours, newest
  first, with an unread count for a badge.
- **"While you were away" card.** When the receiver opens the app, a summary of the gifts that
  arrived since they last looked, replayed as one short sequence of effects.
- **Leaderboard.** Top senders or receivers, by coins or by gift count, for today, this week, this
  month or all time. The viewer's own row is highlighted or pinned under the list.
- **Gift rooms.** Everyone watching the same room sees a gift on their screen a fraction of a second
  after it was sent, over one WebSocket that reconnects and resumes by itself. Gift events only: no
  chat and no media. Includes a battle bar for versus rounds.
- **Make it yours.** Theme colors and shapes, every text as a label you can translate, render slots
  to draw the inside of a chip, a row or a card yourself, and headless controllers when you want to
  draw everything.
- **Careful by default.** The app only ever holds a short-lived client token minted by your server:
  it can send gifts as the signed-in user and read, never credit coins. Test-mode apps show a
  TEST MODE badge. Pictures are limited to safe URLs. The iOS package ships a privacy manifest with
  no tracking and no collected data.

All four SDKs implement the same contract, [packages/sdk-spec](packages/sdk-spec): a written spec
and conformance fixtures that every SDK replays in its own tests, so a gift looks and behaves the
same on every platform.

## Start here

Your server mints a client token for the signed-in user; the app uses it. The documentation walks
through both ends: https://giftingstack.com/docs/. Each folder's README has the install and
usage for its platform.

Licensed under the MIT license (see `LICENSE`). This repository is a read-only mirror of the SDK
sources, published with each release: we do not accept pull requests (see `CONTRIBUTING.md`).
Report security issues to support@giftingstack.com.
