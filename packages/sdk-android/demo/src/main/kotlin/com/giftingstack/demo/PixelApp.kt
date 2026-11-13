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
import com.giftingstack.ui.GiftTrayHolder
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
    // The Live tab's side colours: the battle bar, the room's notices, the tray's "Send to" row and the comment column.
    val sideColors = remember(theme) { liveSideColors(theme) }
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
    // "Live room" (one host, no battle bar), the default; "Battle"; "Battle 4+".
    val fakeRoomPlain = remember { FakeRoomServer(gifts = { giftsRef.value }, timers = Timers.forScope(scope), battle = false) }
    var liveMode by remember { mutableStateOf(LiveMode.Room) }
    val liveRoomId = when (liveMode) { LiveMode.Room -> LIVE_ROOM_PLAIN; LiveMode.Battle -> LIVE_ROOM; LiveMode.Battle4 -> LIVE_ROOM_4 }
    val liveServer = when (liveMode) { LiveMode.Room -> fakeRoomPlain; LiveMode.Battle -> fakeRoom; LiveMode.Battle4 -> fakeRoom4 }

    // The Chat tab: the app's own conversation (GiftingStack carries no chat) with a gift button in its message bar.
    var chat by remember { mutableStateOf(CHAT_START) }
    var chatThanks by remember { mutableIntStateOf(0) }
    var chatInset by remember { mutableStateOf(0.dp) }
    // The stream's comment column on the Live tab: your comments, your gifts and the other viewers' gifts.
    var liveComments by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }

    // The main tray, made below: a chat send refreshes its balance (the header shows it).
    val mainTray = remember { arrayOfNulls<GiftTrayHolder>(1) }
    // The chat's own tray: its text field is bound (Modifier.giftTrayInput in ChatScreen), so it starts closed, the
    // gift button swaps the keyboard for it and a tap on the field swaps back (SPEC 20). No dim: the chat stays in sight.
    val chatTray =
        rememberGiftTrayHolder(
            client = client,
            receiver = CHAT_PEER,
            effects = effects,
            reference = CHAT_REFERENCE,
            onSent = { tx ->
                // Quick repeats of the same gift (a combo) add up in one bubble.
                val before = chat
                chat = addGiftLine(chat, null, tx.gift.id, tx.gift.name, tx.gift.iconUrl, tx.quantity.toLong(), moveDown = false)
                if (needsThanks(before, chat)) chatThanks++
                // Two trays, one balance: the header (the main tray's balance) follows the chat's sends.
                mainTray[0]?.refresh()
                refreshWalls()
            },
        )
    // One thank-you after the sending stops, not one per tap.
    LaunchedEffect(chatThanks) {
        if (chatThanks > 0) {
            delay(1800)
            chat = chat + ChatText(CHAT_PEER, CHAT_THANKS)
        }
    }

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
                chatTray.refresh()
                if (tab == PixelTab.Live) {
                    giftsRef.value.firstOrNull { it.id == tx.gift.id }?.let { liveServer.publish(DEMO_VIEWER, it, tx.quantity, tx.receiver) }
                    // Your own gift in the stream's comment column (the room skips your own events).
                    // It names the side that got it and takes its colour (the "Send to" row picked it, SPEC 21).
                    liveComments = keepLast(addGiftLine(liveComments, null, tx.gift.id, tx.gift.name, tx.gift.iconUrl, tx.quantity.toLong(), tx.receiver))
                }
                // The tray stays open after a send, like a live app: tap again for a combo, the Gift button
                // again to close it.
            },
        )
    mainTray[0] = tray
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
            // The other viewers' gifts land in the stream's comment column too.
            onEvent = { e -> liveComments = keepLast(addGiftLine(liveComments, e.senderId, e.gift.id, e.gift.name, e.gift.icon, e.quantity, e.receiverId)) },
            // The notice borders a battle gift in the same colours as the bar and the "Send to" row.
            sideColors = sideColors,
            resolveName = ::displayName,
            socket = liveServer.factory,
        )
    val roomState by room.state.collectAsState()

    // One gift button for the battle (SPEC 21.5): the tray's "Send to" row lists the round's sides (names from the app,
    // colours = the bar's), and every gift goes to the side picked there. Off the Live tab, or between rounds, no row.
    val battle by room.battle.collectAsState()
    val liveSides = remember(battle) { room.battleView()?.sides?.map { it.id }.orEmpty() }
    val trayReceivers = if (tab == PixelTab.Live) liveReceivers(liveSides, sideColors) else emptyList()
    SideEffect { tray.receivers = trayReceivers }

    // Leaving the Chat tab closes its tray (SPEC 20.5). On the Live tab the comment bar's gift button gifts the host.
    LaunchedEffect(tab) {
        if (tab != PixelTab.Chat) chatTray.close()
        if (tab == PixelTab.Live && LIVE_HOST_POSTS.none { it.author == trayPost?.author }) trayPost = LIVE_HOST_POSTS.first()
    }

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
                chatTray.refresh()
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
                chatTray.refresh()
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

    // Below the tab content: the tab bar and the navigation bar (the message bars lift by what is above them).
    val belowContent = TAB_BAR_HEIGHT + navBar
    // The gift notice sits above what covers the bottom: the tray's top edge, else the keyboard, else the tab bar;
    // on the Chat and Live tabs also above their message bar (it rides on the tray or the keyboard), as on the web.
    val ime = imeHeight()
    val barAbove = if (tab == PixelTab.Chat || tab == PixelTab.Live) MESSAGE_BAR_HEIGHT else 0.dp
    val noticeBottom =
        when {
            chatTray.isOpen && tab == PixelTab.Chat -> chatInset
            tray.isOpen -> inset
            else -> maxOf(belowContent, ime)
        } + barAbove + 12.dp

    Box(Modifier.fillMaxSize().background(theme.background)) {
        Column(Modifier.fillMaxSize()) {
            PixelHeader(theme, state.balance, onLogoHold = { dev = dev.opened() }, onCoins = { store = true })
            if (settings.offline) OfflineBanner(theme)
            Box(Modifier.weight(1f)) {
                when (tab) {
                    PixelTab.Feed -> FeedScreen(client, theme, wallKey, reduced, onGift = { if (trayPost?.id == it.id) tray.toggle() else openTray(it) }, onChip = { p, g -> openTray(p, g.id) })
                    PixelTab.Live ->
                        LiveScreen(
                            room, roomState, theme, reduced, liveMode,
                            onMode = { liveMode = it; tray.close() },
                            sideColors = sideColors,
                            // A tap on a host of the bar picks that host in the tray and opens it (SPEC 21.4).
                            onPressSide = { id ->
                                tray.selectReceiver(id)
                                tray.open()
                            },
                            tray = tray,
                            comments = liveComments,
                            trayInset = inset,
                            below = belowContent,
                            onComment = { liveComments = keepLast(liveComments + ChatText(null, it)) },
                        )
                    PixelTab.Chat -> ChatScreen(chat, chatTray, theme, chatInset, belowContent) { chat = chat + ChatText(null, it) }
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
                    // On the Live tab too: a tap on the stream closes the tray (the comment bar's gift button is a SPEC 20.3 host that passes scrim true, so SPEC 9.4 applies). Only the Chat tab's own tray has none.
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
            // The Chat tab's tray takes the keyboard's place: over the tab bar, as the keyboard is.
            if (tab == PixelTab.Chat) {
                BackHandler(enabled = chatTray.isOpen) { chatTray.close() }
                GiftTray(
                    tray = chatTray,
                    onTopUp = { store = true },
                    theme = theme,
                    // Picking a gift lowers the sheet, so the conversation stays in sight; no dim.
                    collapseOnSelect = true,
                    // The message bar sits on the sheet's top edge, as on the keyboard.
                    onInsetChange = { chatInset = it },
                    bottomInset = navBar,
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
                    chatTray.refresh()
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
