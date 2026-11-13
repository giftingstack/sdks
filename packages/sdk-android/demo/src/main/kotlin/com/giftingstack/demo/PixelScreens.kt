package com.giftingstack.demo

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.giftingstack.core.GiftRef
import com.giftingstack.core.InboxItem
import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.RoomState
import com.giftingstack.ui.AwayUser
import com.giftingstack.ui.BattleBarUser
import com.giftingstack.ui.GiftBattleBar
import com.giftingstack.ui.GiftInbox
import com.giftingstack.ui.GiftInboxHandle
import com.giftingstack.ui.GiftRoom
import com.giftingstack.ui.GiftLeaderboard
import com.giftingstack.ui.GiftLeaderboardHandle
import com.giftingstack.ui.GiftWall
import com.giftingstack.ui.GiftingTheme
import com.giftingstack.ui.GiftTrayHolder
import com.giftingstack.ui.LeaderboardUser
import kotlinx.coroutines.delay

private fun fmt(n: Int): String = com.giftingstack.ui.formatCoins(n)

private fun fmt(n: Long): String = java.lang.String.format(java.util.Locale.US, "%,d", n)

/** What your app would answer from its own user table. */
internal suspend fun resolveLeaderboardUsers(ids: List<String>): Map<String, LeaderboardUser> {
    delay(150)
    return ids.associateWith { LeaderboardUser(displayName(it)) }
}

internal suspend fun resolveAwayUsers(ids: List<String>): Map<String, AwayUser> {
    delay(120)
    return ids.associateWith { AwayUser(displayName(it)) }
}

@Composable
private fun TabColumn(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { content() }
}

/** The feed: posts with a Gift button each and the post's gift wall underneath. */
@Composable
internal fun FeedScreen(client: MockClient, theme: GiftingTheme, wallKey: Int, reduced: Boolean?, onGift: (Post) -> Unit, onChip: (Post, GiftRef) -> Unit) {
    TabColumn {
        for (post in POSTS) PostCard(post, client, theme, wallKey, reduced, onGift, onChip)
    }
}

@Composable
private fun PostCard(post: Post, client: MockClient, theme: GiftingTheme, wallKey: Int, reduced: Boolean?, onGift: (Post) -> Unit, onChip: (Post, GiftRef) -> Unit) {
    var liked by remember { mutableStateOf(false) }
    Card(theme) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Avatar(post.author, 40.dp)
                Column {
                    Txt(displayName(post.author), theme.text, 15f, bold = true)
                    Txt(post.ago, theme.muted, 12f)
                }
            }
            Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(RoundedCornerShape(12.dp))) { PostArt(post.art) }
            Txt(post.text, theme.text, 15f)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill(fmtLikes(post.likes + if (liked) 1 else 0), theme, icon = { HeartIcon(if (liked) theme.danger else it, liked) }) { liked = !liked }
                Pill("Gift", theme, filled = true, icon = { GiftIcon(it) }) { onGift(post) }
            }
            // The gifts this post received. Pressing a chip opens the tray with that gift picked.
            GiftWall(
                client = client,
                user = post.author,
                reference = post.id,
                refreshKey = wallKey,
                max = 6,
                onPressChip = { onChip(post, it) },
                reducedMotion = reduced,
                theme = theme,
            )
        }
    }
}

private fun fmtLikes(n: Int): String = fmt(n)

/** The Live tab's streams: a plain room, a two-host battle, a four-host battle. */
enum class LiveMode { Room, Battle, Battle4 }

/**
 * The live room: other viewers' gifts arrive as effects (the real rememberGiftRoom against the
 * pretend rooms server FakeRoomServer), and a gift sent here carries the room id, so everyone in the room sees it.
 */
@Composable
internal fun LiveScreen(
    room: GiftRoom,
    state: RoomState,
    theme: GiftingTheme,
    reduced: Boolean?,
    mode: LiveMode,
    onMode: (LiveMode) -> Unit,
    sideColors: List<Color>,
    onPressSide: (String) -> Unit,
    tray: GiftTrayHolder,
    comments: List<ChatMessage>,
    trayInset: Dp,
    below: Dp,
    onComment: (String) -> Unit,
) {
    val hosts = when (mode) { LiveMode.Room -> LIVE_HOSTS.take(1); LiveMode.Battle -> LIVE_HOSTS.take(2); LiveMode.Battle4 -> LIVE_HOSTS }
    Column(Modifier.fillMaxSize()) {
    Box(Modifier.weight(1f)) {
    TabColumn {
        // (The stream and the battle scroll; the comment bar below stays put.)
        // The three modes: "Live room" (one host, the default), "Battle" (two hosts) and "Battle 4+" (four hosts in every round).
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("Live room", theme, filled = mode == LiveMode.Room, modifier = Modifier.testTag("live-mode-room")) { onMode(LiveMode.Room) }
            Pill("Battle", theme, filled = mode == LiveMode.Battle, modifier = Modifier.testTag("live-mode-battle")) { onMode(LiveMode.Battle) }
            Pill("Battle 4+", theme, filled = mode == LiveMode.Battle4, modifier = Modifier.testTag("live-mode-battle4")) { onMode(LiveMode.Battle4) }
        }
        Card(theme) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Avatar(LIVE_HOST, 40.dp)
                    Column {
                        Txt(hosts.joinToString(if (mode == LiveMode.Battle4) ", " else " vs ") { firstName(it) }, theme.text, 15f, bold = true)
                        if (mode == LiveMode.Room) Txt("Evening stream", theme.muted, 12f)
                        Txt(liveStatusLine(state), theme.muted, 12f, modifier = Modifier.testTag("live-status"))
                    }
                }
                // The SDK's battle bar, driven by the room: a round between two hosts, nothing drawn between rounds.
                if (mode != LiveMode.Room) GiftBattleBar(
                    room,
                    users = LIVE_HOSTS.associateWith { BattleBarUser(displayName(it)) },
                    reducedMotion = reduced,
                    theme = theme,
                    // The bar's colours, the tray's "Send to" row and the comment column share one list (SPEC 21.5).
                    sideColors = sideColors,
                    // A tap on a side picks it in the tray and opens the tray (SPEC 21.4).
                    onPressSide = onPressSide,
                )
                Box(Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(RoundedCornerShape(12.dp))) {
                    PostArt(LIVE_POST.art)
                    // The stream's own comment column (the app's, not GiftingStack's): comments and gifts in one column;
                    // a gift line takes the colour of the side that got it.
                    LiveComments(comments, Modifier.align(Alignment.BottomStart).padding(10.dp), sideColor = { liveSideColor(it, sideColors) })
                }
                Txt(if (mode == LiveMode.Room) "Gifts that other viewers send show up here as effects and in the comment column. Send one yourself with the gift button of the comment bar: it goes to the host." else "Gifts that other viewers send show up here as effects. Send one yourself with the gift button of the comment bar (its \"Send to\" row picks the host), or tap a host on the bar.", theme.text, 15f)
            }
        }
    }
    }
        // The comment bar under the stream: type a comment, or the gift button for the tray (it takes the
        // keyboard's place, as on the Chat tab). The field is bound to the tray with Modifier.giftTrayInput.
        MessageBar(tray, theme, "Say something...", "live", onComment)
        Spacer(Modifier.height(barLift(tray.isOpen, trayInset, imeHeight(), below)))
    }
}

/** Top gifters and top creators, with the period tabs and the coins / gifts switch of the component. */
@Composable
internal fun TopScreen(client: MockClient, theme: GiftingTheme, reduced: Boolean?, handle: GiftLeaderboardHandle) {
    var board by remember { mutableStateOf(LeaderboardBoard.Senders) }
    TabColumn {
        Txt("Top", theme.text, 22f, bold = true)
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(theme.surface).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for ((b, label) in listOf(LeaderboardBoard.Senders to "Top gifters", LeaderboardBoard.Receivers to "Top creators")) {
                val on = b == board
                Box(
                    Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(9.dp)).background(if (on) theme.accent else Color.Transparent).clickable { board = b }.semantics { role = Role.Tab },
                    contentAlignment = Alignment.Center,
                ) { Txt(label, if (on) theme.accentText else theme.muted, 14f, bold = true) }
            }
        }
        Card(theme) {
            Box(Modifier.padding(8.dp)) {
                GiftLeaderboard(
                    client = client,
                    board = board,
                    metricToggle = true,
                    limit = 10,
                    highlightUser = DEMO_VIEWER,
                    resolveUsers = ::resolveLeaderboardUsers,
                    reducedMotion = reduced,
                    theme = theme,
                    handle = handle,
                    onPressUser = { /* a real app opens the profile here */ },
                )
            }
        }
    }
}

/** The gifts the signed-in user received in the last 24 hours: the SDK's inbox, newest first. */
@Composable
internal fun InboxScreen(client: MockClient, theme: GiftingTheme, handle: GiftInboxHandle, onLoaded: (List<InboxItem>) -> Unit) {
    TabColumn {
        Txt("Inbox", theme.text, 22f, bold = true)
        GiftInbox(
            client = client,
            // A small page, so the demo shows "Show more" with its twelve seeded gifts.
            pageSize = 10,
            resolveUsers = ::resolveAwayUsers,
            onLoaded = onLoaded,
            theme = theme,
            handle = handle,
        )
    }
}

/** The signed-in demo user: balance, coin store, the gifts received, and the leaderboard visibility switch. */
@Composable
internal fun MeScreen(
    client: MockClient,
    theme: GiftingTheme,
    wallKey: Int,
    reduced: Boolean?,
    balance: Long,
    received: Int,
    hidden: Boolean,
    onHidden: (Boolean) -> Unit,
    onGetCoins: () -> Unit,
) {
    TabColumn {
        Card(theme) {
            Box(Modifier.fillMaxWidth().height(90.dp).background(Brush.horizontalGradient(listOf(Color(0xFFE0457B), Color(0xFF7B61FF)))))
            Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(Modifier.padding(top = 0.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.padding(top = 0.dp).size(84.dp).clip(CircleShape).background(theme.surface).padding(4.dp)) { Avatar(DEMO_VIEWER, 76.dp) }
                    Column(Modifier.padding(bottom = 4.dp)) {
                        Txt(displayName(DEMO_VIEWER), theme.text, 20f, bold = true)
                        Txt("@$DEMO_VIEWER", theme.muted, 13f)
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Stat(fmt(received), "Gifts received", theme)
                    Stat("1.2K", "Followers", theme)
                    Stat("318", "Following", theme)
                }
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(theme.background).padding(start = 14.dp, top = 10.dp, end = 10.dp, bottom = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Txt("Your coins", theme.muted, 12f)
                        Txt(fmt(balance), theme.coin, 22f, bold = true)
                    }
                    Pill("Get coins", theme, filled = true, onClick = onGetCoins)
                }
                Txt("Gifts received", theme.text, 15f, bold = true)
                GiftWall(client = client, user = DEMO_VIEWER, refreshKey = wallKey, max = 8, reducedMotion = reduced, theme = theme)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Txt("Hide me from leaderboards", theme.text, 14f)
                        Txt("Others will not see your rank", theme.muted, 12f)
                    }
                    PixelSwitch(hidden, theme, "Hide me from leaderboards", onHidden)
                }
            }
        }
    }
}

@Composable
private fun Stat(value: String, label: String, theme: GiftingTheme) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Txt(value, theme.text, 17f, bold = true)
        Txt(label, theme.muted, 12f)
    }
}
