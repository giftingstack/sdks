import '../core/component_types.dart';

/// Every visible and spoken word of the gift wall, the "while you were away"
/// card and the leaderboard. Pass any of them (translations); the rest keep
/// the English default. `{x}` marks a place a value goes. The same keys and
/// defaults as the web and React Native components.
class GiftLabels {
  /// Creates labels; every one has the English default.
  const GiftLabels({
    this.thousand = 'K',
    this.million = 'M',
    this.someone = 'Someone',
    this.wallSummary = 'Gifts: {list}',
    this.wallMore = 'and {n} more',
    this.wallChip = '{name}, {count}',
    this.plural = 's',
    this.emptyText = '',
    this.awayTitle = 'While you were away',
    this.awaySummary = '{gifts} from {people}',
    this.awayAnnounce = 'You received {summary} while you were away',
    this.giftOne = '{n} gift',
    this.giftOther = '{n} gifts',
    this.personOne = '{n} person',
    this.personOther = '{n} people',
    this.dismiss = 'Dismiss',
    this.tabs = defaultTabs,
    this.empty = defaultEmpty,
    this.metricUnits = '',
    this.metricGifts = 'Gifts',
    this.metricSwitch = 'Ranked by',
    this.giftsWord = 'gifts',
    this.error = 'Could not load the leaderboard.',
    this.tryAgain = 'Try again',
    this.pinned = 'You: {rank}',
    this.pinnedSpoken = 'Your rank: {rank}, {score}',
    this.rowSpoken = 'Rank {rank}, {name}, {score}',
    this.rankOverflow = '1,000+',
    this.loading = 'Loading',
    this.updating = 'Updating',
    this.inboxEmpty = 'No gifts in the last 24 hours',
    this.inboxError = 'Could not load gifts',
    this.inboxShowMore = 'Show more',
    this.inboxSent = '{name} sent you {gift}',
    this.inboxQuantity = 'x{n}',
    this.inboxRowSpoken = '{sentence}, {time}',
  });

  /// Tab labels of the leaderboard.
  static const Map<LeaderboardPeriod, String> defaultTabs =
      <LeaderboardPeriod, String>{
    LeaderboardPeriod.day: 'Today',
    LeaderboardPeriod.week: 'This week',
    LeaderboardPeriod.month: 'This month',
    LeaderboardPeriod.all: 'All time',
  };

  /// Empty-board texts of the leaderboard.
  static const Map<LeaderboardPeriod, String> defaultEmpty =
      <LeaderboardPeriod, String>{
    LeaderboardPeriod.day: 'No gifts yet today',
    LeaderboardPeriod.week: 'No gifts yet this week',
    LeaderboardPeriod.month: 'No gifts yet this month',
    LeaderboardPeriod.all: 'No gifts yet',
  };

  /// Count suffix of `formatCount`.
  final String thousand;

  /// Count suffix of `formatCount`.
  final String million;

  /// A deleted sender.
  final String someone;

  /// Wall: the row as one element. `{list}` = `12 Roses, 3 Hearts`.
  final String wallSummary;

  /// Wall: the end of `{list}` when more gifts exist.
  final String wallMore;

  /// Wall: a tappable chip, for example `Rose, 12`.
  final String wallChip;

  /// Wall: added to a gift name when its count is above 1 (`12 Roses`).
  final String plural;

  /// Wall: text under the chips when nothing was received. Default none.
  final String emptyText;

  /// Away card title.
  final String awayTitle;

  /// `{gifts}` and `{people}` are [giftOne]/[giftOther] and
  /// [personOne]/[personOther].
  final String awaySummary;

  /// Spoken when the card appears. `{summary}` is the [awaySummary] line.
  final String awayAnnounce;

  /// One gift.
  final String giftOne;

  /// Many gifts.
  final String giftOther;

  /// One person.
  final String personOne;

  /// Many people.
  final String personOther;

  /// The close button.
  final String dismiss;

  /// Leaderboard tabs. Missing periods keep the default.
  final Map<LeaderboardPeriod, String> tabs;

  /// Leaderboard empty texts. Missing periods keep the default.
  final Map<LeaderboardPeriod, String> empty;

  /// Metric switch: the units button. Default: the capitalised `coinName`.
  final String metricUnits;

  /// Metric switch: the gifts button.
  final String metricGifts;

  /// Metric switch: its spoken name.
  final String metricSwitch;

  /// The word after a gift count.
  final String giftsWord;

  /// Leaderboard error message.
  final String error;

  /// Leaderboard retry button.
  final String tryAgain;

  /// Pinned row. `{rank}` is `#417` or [rankOverflow].
  final String pinned;

  /// Pinned row, spoken.
  final String pinnedSpoken;

  /// A row, spoken.
  final String rowSpoken;

  /// A rank beyond the top 1,000.
  final String rankOverflow;

  /// Spoken while the board loads.
  final String loading;

  /// Spoken by the refresh spinner.
  final String updating;

  /// Gift inbox: nothing in the last 24 hours.
  final String inboxEmpty;

  /// Gift inbox: the page could not be loaded (the retry button is
  /// [tryAgain]).
  final String inboxError;

  /// Gift inbox: loads the next, older page.
  final String inboxShowMore;

  /// Gift inbox: a row. `{name}` (shown bold) and `{gift}`.
  final String inboxSent;

  /// Gift inbox: added after [inboxSent] when more than one gift was sent.
  /// `{n}` is the quantity.
  final String inboxQuantity;

  /// Gift inbox: a row, spoken. `{sentence}` is [inboxSent] (and the quantity),
  /// `{time}` the time label.
  final String inboxRowSpoken;

  /// Tab label of [period].
  String tab(LeaderboardPeriod period) => tabs[period] ?? defaultTabs[period]!;

  /// Empty text of [period].
  String emptyFor(LeaderboardPeriod period) =>
      empty[period] ?? defaultEmpty[period]!;
}

/// `fill('Rank {rank}', {'rank': 1})`.
String fillLabel(String template, Map<String, Object> values) =>
    template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => values.containsKey(m[1]) ? '${values[m[1]]}' : m[0]!,
    );
