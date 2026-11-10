package com.giftingstack.demo

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.giftingstack.core.EffectGift
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.InboxItem
import com.giftingstack.core.InboxQuery
import com.giftingstack.core.ScrimTap
import com.giftingstack.core.Timers
import com.giftingstack.core.inboxUnread
import com.giftingstack.core.parseIsoTimeMs
import com.giftingstack.ui.GiftAwaySummary
import com.giftingstack.ui.GiftEffectLayer
import com.giftingstack.ui.GiftTray
import com.giftingstack.ui.GiftWallLoaders
import com.giftingstack.ui.GiftingTheme
import com.giftingstack.ui.formatCoins
import com.giftingstack.ui.rememberGiftAwayHandle
import com.giftingstack.ui.rememberGiftEffectLayerState
import com.giftingstack.ui.rememberGiftInboxHandle
import com.giftingstack.ui.rememberGiftLeaderboardHandle
import com.giftingstack.ui.rememberGiftRoom
import com.giftingstack.ui.rememberGiftTrayHolder
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The demo theme picker (an app passes one `theme` to the tray, the layer and the components). */
internal fun DemoTheme.toTheme(): GiftingTheme =
    when (this) {
        DemoTheme.Default -> GiftingTheme()
        DemoTheme.Dark -> GiftingTheme.Dark
        DemoTheme.Light -> GiftingTheme.Light
        DemoTheme.Pink -> GiftingTheme.fromAccent("#ff4f9a", dark = true)
    }

/**
 * "Pixel": a fake social app around the SDK, on a mock client. What a customer would write: the
 * effect layer, the tray, one `GiftWall` per post, one `GiftAwaySummary` and one `GiftLeaderboard`.
 * Everything else (the feed, the tabs, the developer menu behind the logo) is only the demo's own
 * pretend app.
 */
@Composable
fun PixelApp(awayOnce: AwayOnce) {
    // The catalog comes from the live library (about 90 gifts) with the small built-in list as the fallback.
    val client = remember { MockClient(catalog = { loadGifts() }) }
    val effects = rememberGiftEffectLayerState()
    val scope = rememberCoroutineScope()
    var dev by remember { mutableStateOf(DevMenuState()) }
    val settings = dev.settings
    val theme = remember(settings.theme) { settings.theme.toTheme() }
    val reduced = settings.motion.reduced
    var tab by remember { mutableStateOf(PixelTab.Feed) }
    // The badge on the Inbox tab: gifts newer than the newest row shown when the tab was last viewed.
    var inboxItems by remember { mutableStateOf<List<InboxItem>>(emptyList()) }
    var lastSeenMs by remember { mutableStateOf<Long?>(System.currentTimeMillis()) }
    var inboxTick by remember { mutableIntStateOf(0) }
    val inboxHandle = rememberGiftInboxHandle()
    val unread = inboxUnread(inboxItems, lastSeenMs)
    fun markInboxSeen(items: List<InboxItem>) {
        val newest = items.filter { it.completed }.mapNotNull { parseIsoTimeMs(it.createdAt) }.maxOrNull() ?: return
        lastSeenMs = maxOf(lastSeenMs ?: 0L, newest)
    }
    var trayPost by remember { mutableStateOf<Post?>(null) }
    var trayGift by remember { mutableStateOf<String?>(null) }
    var trayOpens by remember { mutableIntStateOf(0) }
    // The SDK does the rest (SPEC 9.4): picking a gift lowers the sheet (collapseOnSelect) and the dim goes away
    // while it is low, a tap on the dim closes the tray (scrimTap = Dismiss), and the Gift button toggles it.
    var selected by remember { mutableStateOf<Gift?>(null) }
    var store by remember { mutableStateOf(false) }
    var wallKey by remember { mutableIntStateOf(0) }
    var inset by remember { mutableStateOf(0.dp) }
    var received by remember { mutableIntStateOf(START_RECEIVED) }
    var hidden by remember { mutableStateOf(false) }
    val away = rememberGiftAwayHandle()
    val board = rememberGiftLeaderboardHandle()
    val navBar = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

    // Walls ask the server again: the shared loader forgets what it has, and every wall's key moves.
    fun refreshWalls() {
        GiftWallLoaders.forClient(client).clear()
        wallKey++
    }

    // The pretend rooms server, made before the tray: a live send is published into it, which is what
    // the API does for a send with `room_id`. A real app passes no socket and has no such step.
    val giftsRef = remember { mutableStateOf(demoGifts) }
    val roomForTray = remember { arrayOfNulls<com.giftingstack.ui.GiftRoom>(1) }
    val fakeRoom = remember { FakeRoomServer(gifts = { giftsRef.value }, timers = Timers.forScope(scope)) }
    // "Battle 4+": the same pretend server with four hosts in every round (a free-for-all).
    val fakeRoom4 = remember { FakeRoomServer(gifts = { giftsRef.value }, timers = Timers.forScope(scope), sides = 4) }
    var battle4 by remember { mutableStateOf(false) }
    val liveRoomId = if (battle4) LIVE_ROOM_4 else LIVE_ROOM
    val liveServer = if (battle4) fakeRoom4 else fakeRoom

    // The tray belongs to the post whose Gift button was pressed (the post id is the gift's `reference`).
    val forPost = trayPost ?: POSTS.first()
    val tray =
        rememberGiftTrayHolder(
            client = client,
            receiver = forPost.author,
            // In a battle your own gift says who got it too (the room, made below, knows the sides).
            receiverOf = { roomForTray[0]?.receiverFor(it) },
            effects = effects,
            reference = forPost.id,
            // Closed until a Gift button opens it.
            open = false,
            // On the Live tab every gift goes into the room, so the other viewers see it.
            roomId = if (tab == PixelTab.Live) liveRoomId else null,
            onSent = { tx ->
                refreshWalls()
                if (tab == PixelTab.Live) {
                    giftsRef.value.firstOrNull { it.id == tx.gift.id }?.let { liveServer.publish(DEMO_VIEWER, it, tx.quantity, tx.receiver) }
                }
                // The tray stays open after a send, like a live app: tap again for a combo, the Gift button
                // again to close it.
            },
        )
    val state by tray.state.collectAsState()
    val gifts = state.gifts.ifEmpty { demoGifts }

    // The Live tab joins a room while it is shown: room gifts play on the effect layer, the socket closes
    // when the app goes to the background. The server is pretend (FakeRoomServer); a real app passes no socket.
    SideEffect { giftsRef.value = gifts }
    val room =
        rememberGiftRoom(
            room = if (tab == PixelTab.Live) liveRoomId else null,
            getToken = { demoRoomToken(DEMO_VIEWER) },
            client = client,
            effects = effects,
            resolveName = ::displayName,
            socket = liveServer.factory,
        )
    val roomState by room.state.collectAsState()

    roomForTray[0] = room

    // A gift somebody else sent: the effect over whatever is open, a notification, the profile wall.
    fun deliver(inc: Incoming) {
        val g = inc.gift
        effects.play(
            GiftEffectEvent(EffectGift(g.id, g.name, g.price, image = g.animationUrl, icon = g.iconUrl), sender = displayName(inc.sender), quantity = inc.quantity),
        )
        client.addToWall(DEMO_VIEWER, g.id, inc.quantity)
        received += inc.quantity
        client.addToInbox(g, inc.sender, inc.quantity)
        inboxTick++
        inboxHandle.refresh()
        refreshWalls()
    }

    // The tab bar badge reads the inbox from the client (the Inbox tab itself shows it through GiftInbox).
    LaunchedEffect(inboxTick) {
        try {
            val items = client.getInbox(InboxQuery(limit = 100)).data
            inboxItems = items
            if (tab == PixelTab.Inbox) markInboxSeen(items)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Offline: the badge keeps its last count.
        }
    }

    // Off unless LIVE_FEED is switched on: a gift that arrives by itself confuses a test.
    if (LIVE_FEED) {
        LaunchedEffect(Unit) {
            while (true) {
                delay(nextDelayMs(Random))
                if (!client.offline) pickIncoming(gifts, SENDERS, Random)?.let { deliver(it) }
            }
        }
    }

    fun change(f: (DevSettings) -> DevSettings) {
        val before = dev.settings
        dev = dev.with(f)
        val after = dev.settings
        if (after.offline != before.offline) {
            client.offline = after.offline
            if (!after.offline) {
                tray.refresh()
                refreshWalls()
                board.refresh()
                inboxTick++
                inboxHandle.refresh()
            }
        }
    }

    fun openTray(post: Post, giftId: String? = null) {
        // A Gift button for another post (or a wall chip): a fresh tray for that person, at its first state.
        trayGift = giftId
        trayPost = post
        trayOpens++
        tray.open()
    }

    val actions =
        DevActions(
            playIncoming = {
                pickIncoming(gifts, SENDERS, Random)?.let { base ->
                    giftFor(settings.incoming, gifts, selected, Random)?.let { deliver(Incoming(it, base.sender, 1)) }
                }
            },
            combo = {
                pickIncoming(gifts, SENDERS, Random)?.let { base ->
                    giftFor(settings.incoming, gifts, selected, Random)?.let { g ->
                        scope.launch { repeat(5) { deliver(Incoming(g, base.sender, 1)); delay(250) } }
                    }
                }
            },
            awayAgain = {
                client.newAwayGifts()
                away.check()
            },
            wallPlus = {
                for (p in POSTS) client.addToWall(p.author, gifts[Random.nextInt(gifts.size)].id, 5, p.id)
                client.addToWall(DEMO_VIEWER, gifts[Random.nextInt(gifts.size)].id, 5)
                refreshWalls()
            },
            reset = {
                tray.close()
                client.reset()
                tray.refresh()
                received = START_RECEIVED
                hidden = false
                inboxItems = emptyList()
                lastSeenMs = System.currentTimeMillis()
                inboxTick++
                inboxHandle.refresh()
                refreshWalls()
                board.refresh()
                away.check()
            },
            change = ::change,
        )

    val noticeBottom = if (tray.isOpen) inset + 12.dp else TAB_BAR_HEIGHT + navBar + 12.dp

    Box(Modifier.fillMaxSize().background(theme.background)) {
        Column(Modifier.fillMaxSize()) {
            PixelHeader(theme, state.balance, onLogoHold = { dev = dev.opened() }, onCoins = { store = true })
            if (settings.offline) OfflineBanner(theme)
            Box(Modifier.weight(1f)) {
                when (tab) {
                    PixelTab.Feed -> FeedScreen(client, theme, wallKey, reduced, onGift = { if (trayPost?.id == it.id) tray.toggle() else openTray(it) }, onChip = { p, g -> openTray(p, g.id) })
                    PixelTab.Live -> LiveScreen(room, roomState, theme, reduced, battle4, onBattle4 = { battle4 = it; tray.close() }, onGift = { post -> if (trayPost?.author == post.author) tray.toggle() else openTray(post) })
                    PixelTab.Top -> TopScreen(client, theme, reduced, board)
                    PixelTab.Inbox ->
                        InboxScreen(client, theme, inboxHandle) { items ->
                            inboxItems = items
                            markInboxSeen(items)
                        }
                    PixelTab.Me ->
                        MeScreen(
                            client, theme, wallKey, reduced, state.balance, received, hidden,
                            onHidden = {
                                hidden = it
                                client.hidden = it
                                board.refresh()
                            },
                            onGetCoins = { store = true },
                        )
                }
            }
            Column(Modifier.background(theme.surface)) {
                PixelTabBar(tab, unread, theme) {
                    tab = it
                    if (it == PixelTab.Inbox) markInboxSeen(inboxItems)
                }
                Box(Modifier.fillMaxWidth().height(navBar))
            }
        }


        // "While you were away": the first time after install only (AwayOnce), then from the developer menu.
        GiftAwaySummary(
            client = client,
            effects = effects,
            autoCheck = awayOnce.autoCheck,
            handle = away,
            quality = settings.quality,
            reducedMotion = reduced,
            theme = theme,
            onShow = { awayOnce.onShown() },
            resolveUsers = ::resolveAwayUsers,
        )

        // The tray is a bottom sheet over the app, the tab bar included: pull it up for more gifts, down for more screen.
        run {
            BackHandler(enabled = tray.isOpen) { tray.close() }
            key(trayOpens) {
                GiftTray(
                    // Gifts, balance, Send, the open state and the "Test mode" badge (the mock answers livemode false)
                    // come from the holder.
                    tray = tray,
                    // The dim behind the sheet (it fades in with the sheet, goes away at peek); a tap on it closes the tray.
                    scrim = true,
                    scrimTap = ScrimTap.Dismiss,
                    // A real app opens ITS coin store here; the demo's pretend store ADDS the coins.
                    onTopUp = { store = true },
                    title = "Send a gift",
                    defaultSelectedId = trayGift ?: selected?.id ?: "sun-dragon",
                    theme = theme,
                    onSelectedChange = { selected = it },
                    onInsetChange = { inset = it },
                    // The tab bar stays in view and in reach below the tray.
                    bottomInset = navBar + TAB_BAR_HEIGHT,
                    collapseOnSelect = true,
                )
            }
            // The tab bar stays above the dim and the tray while the tray is open.
            if (tray.isOpen) {
                Column(Modifier.align(Alignment.BottomCenter).background(theme.surface)) {
                    PixelTabBar(tab, unread, theme) {
                        tray.close()
                        tab = it
                        if (it == PixelTab.Inbox) markInboxSeen(inboxItems)
                    }
                    Box(Modifier.fillMaxWidth().height(navBar))
                }
            }
        }

        GiftEffectLayer(
            state = effects,
            quality = settings.quality,
            reducedMotion = reduced,
            theme = theme,
            noticeBottom = noticeBottom,
        )

        if (store) {
            CoinStoreSheet(
                theme,
                onBuy = { coins ->
                    store = false
                    client.credit(coins)
                    tray.refresh()
                },
                onClose = { store = false },
            )
        }

        if (dev.open) DevMenuSheet(settings, theme, actions, onClose = { dev = dev.closed() })
    }
}

/** The app bar: the Pixel logo (hold it for 1 s: the developer menu) and the coin balance. */
@Composable
private fun PixelHeader(theme: GiftingTheme, balance: Long, onLogoHold: () -> Unit, onCoins: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(theme.surface).statusBarsPadding().heightIn(min = 56.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.heightIn(min = 48.dp).devTrigger(onLogoHold), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.height(26.dp).clip(RoundedCornerShape(7.dp)).background(theme.accent).padding(horizontal = 7.dp), contentAlignment = Alignment.Center) {
                Txt("P", theme.accentText, 16f, bold = true)
            }
            Txt("Pixel", theme.text, 20f, bold = true)
        }
        Spacer(Modifier.weight(1f))
        Row(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp)).background(theme.background).clickable(onClick = onCoins).padding(horizontal = 14.dp)
                .semantics { contentDescription = "${formatCoins(balance)} coins, get coins" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Txt(formatCoins(balance), theme.coin, 15f, bold = true)
            Txt("+", theme.coin, 16f, bold = true)
        }
    }
}

@Composable
private fun OfflineBanner(theme: GiftingTheme) {
    Box(Modifier.fillMaxWidth().background(theme.danger).padding(horizontal = 16.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        Txt("You are offline. Showing what was loaded before.", Color(0xFF2A0010), 13f, bold = true)
    }
}
