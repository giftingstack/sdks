package com.giftingstack.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.DEFAULT_INBOX_PAGE_SIZE
import com.giftingstack.core.GiftingException
import com.giftingstack.core.InboxApi
import com.giftingstack.core.InboxController
import com.giftingstack.core.InboxItem
import com.giftingstack.core.InboxRow
import com.giftingstack.core.InboxStatus
import com.giftingstack.core.inboxRowText
import com.giftingstack.core.inboxRows
import com.giftingstack.core.inboxTimeSpoken
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/** The words of [GiftInbox]. Change them for another language. */
data class InboxLabels(
    val empty: String = "No gifts in the last 24 hours",
    val error: String = "Could not load gifts",
    val tryAgain: String = "Try again",
    val showMore: String = "Show more",
    val loading: String = "Loading gifts",
    /** Between the name and the gift: "Ayla sent you Rose". */
    val sentYou: String = "sent you",
)

/** For "pull to refresh" and for apps that poll: reaches the controller of an inbox. */
@Stable
class GiftInboxHandle {
    internal var controller: InboxController? = null

    /** Reload from the first page now. */
    fun refresh() {
        controller?.refresh()
    }
}

@Composable
fun rememberGiftInboxHandle(): GiftInboxHandle = remember { GiftInboxHandle() }

/** How often the time labels (`5m`, `3h`) are recomputed while the list stays on screen. */
internal const val INBOX_CLOCK_TICK_MS = 60_000L

/**
 * Who sent the signed-in user which gift, over the last 24 hours (SPEC 19.3): one row per gift,
 * newest first, with the sender's initial, "Name sent you Gift" (and "xN" above one), the gift
 * picture and how long ago. Loads the first page itself, "Show more" appends the next while there
 * is one. A gift that was reversed is not shown. Read only: the server keeps no "read" state; keep
 * the time of the newest row you showed and ask `inboxUnread` for a badge.
 *
 * @param pageSize rows per page, 1 to 100.
 * @param resolveUsers external ids are often not display names: map them here (the shape of the
 *   away card's). Unknown ids keep the id itself; a deleted sender shows "Someone".
 * @param onLoaded every loaded item (all pages so far, reversed ones included) after each page, for
 *   your own badge.
 * @param handle see [rememberGiftInboxHandle].
 * @param nowMs the clock for the time labels (tests pass a fixed one).
 */
@Composable
fun GiftInbox(
    client: InboxApi,
    modifier: Modifier = Modifier,
    pageSize: Int = DEFAULT_INBOX_PAGE_SIZE,
    resolveUsers: (suspend (List<String>) -> Map<String, AwayUser>)? = null,
    onLoaded: ((List<InboxItem>) -> Unit)? = null,
    onError: ((GiftingException) -> Unit)? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: InboxLabels = InboxLabels(),
    handle: GiftInboxHandle? = null,
    nowMs: () -> Long = System::currentTimeMillis,
) {
    val scope = rememberCoroutineScope()
    val imageLoader = currentGiftImageLoader()
    val controller = remember(client, pageSize) { InboxController(client, scope, pageSize) }
    SideEffect {
        controller.onLoaded = onLoaded
        controller.onError = onError
    }
    DisposableEffect(controller, handle) {
        handle?.controller = controller
        controller.start()
        onDispose {
            if (handle?.controller === controller) handle.controller = null
            controller.dispose()
        }
    }
    val state by controller.state.collectAsState()

    // The time labels follow the clock while the list stays open.
    val nowFn by rememberUpdatedState(nowMs)
    var now by remember { mutableLongStateOf(nowFn()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(INBOX_CLOCK_TICK_MS)
            now = nowFn()
        }
    }
    // A fresh page also moves the clock, so "now" is true for a row that just arrived.
    LaunchedEffect(state.items) { now = nowFn() }

    // Names for the senders on screen, asked once per id.
    var users by remember { mutableStateOf<Map<String, AwayUser>>(emptyMap()) }
    val asked = remember { HashSet<String>() }
    val resolveNow by rememberUpdatedState(resolveUsers)
    val ids = state.items.mapNotNull { it.sender }.distinct()
    val idsKey = ids.joinToString("\u0000")
    LaunchedEffect(idsKey) {
        val resolve = resolveNow ?: return@LaunchedEffect
        val fresh = ids.filter { it !in asked }
        if (fresh.isEmpty()) return@LaunchedEffect
        asked.addAll(fresh)
        try {
            users = users + resolve(fresh)
        } catch (e: CancellationException) {
            asked.removeAll(fresh.toSet())
            throw e
        } catch (e: Exception) {
            asked.removeAll(fresh.toSet())
        }
    }

    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.clip(shape).background(theme.surface).border(Dp.Hairline, theme.border, shape).padding(8.dp).testTag("gift-inbox"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        when (state.status) {
            InboxStatus.Loading -> SkeletonRows(theme, labels.loading)
            InboxStatus.Error ->
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp).testTag("gift-inbox-error"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    BasicText(
                        labels.error,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        style = TextStyle(color = theme.danger, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                    )
                    TextButton(labels.tryAgain, theme, 1f, "gift-inbox-retry") { controller.refresh() }
                }
            InboxStatus.Empty ->
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp).testTag("gift-inbox-empty"), contentAlignment = Alignment.Center) {
                    BasicText(
                        labels.empty,
                        style = TextStyle(color = theme.muted, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                    )
                }
            InboxStatus.Ready -> {
                val rows = inboxRows(state.items, now, users.mapValues { it.value.name })
                Column(Modifier.semantics { collectionInfo = CollectionInfo(rowCount = rows.size, columnCount = 1) }.testTag("gift-inbox-list")) {
                    for ((i, row) in rows.withIndex()) {
                        InboxRowView(row, i, row.sender?.let { users[it]?.avatarUrl }, theme, labels, imageLoader)
                    }
                }
                if (state.hasMore) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        TextButton(labels.showMore, theme, if (state.loadingMore) 0.6f else 1f, "gift-inbox-more") { controller.loadMore() }
                    }
                }
            }
        }
    }
}

@Composable
private fun TextButton(label: String, theme: GiftingTheme, alpha: Float, tag: String, onClick: () -> Unit) {
    Box(
        Modifier.heightIn(min = 44.dp)
            .alpha(alpha)
            .clip(CircleShape)
            .background(theme.accent)
            .semantics { role = Role.Button }
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp)
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(label, style = TextStyle(color = theme.accentText, fontSize = 14.sp, fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun InboxRowView(row: InboxRow, index: Int, avatarUrl: String?, theme: GiftingTheme, labels: InboxLabels, imageLoader: GiftImageLoader) {
    val spoken = inboxRowText(row, labels.sentYou) + ", " + inboxTimeSpoken(row.time)
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = INBOX_ROW_DP.dp)
            .clip(RoundedCornerShape(14.dp))
            .clearAndSetSemantics {
                contentDescription = spoken
                collectionItemInfo = CollectionItemInfo(rowIndex = index, rowSpan = 1, columnIndex = 0, columnSpan = 1)
            }
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .testTag("gift-inbox-row-${row.id}"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(row.senderName, avatarUrl, 36.dp, theme, imageLoader)
        BasicText(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = theme.text)) { append(row.senderName) }
                withStyle(SpanStyle(color = theme.muted)) { append(" ${labels.sentYou} ") }
                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = theme.text)) { append(row.giftName) }
                if (row.quantity > 1) withStyle(SpanStyle(fontWeight = FontWeight.ExtraBold, color = theme.text)) { append(" x${row.quantity}") }
            },
            modifier = Modifier.weight(1f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            style = TextStyle(color = theme.text, fontSize = 14.sp),
        )
        GiftChipIcon(row.iconUrl, 32.dp, theme, imageLoader)
        BasicText(
            row.time,
            modifier = Modifier.testTag("gift-inbox-time-${row.id}"),
            style = TextStyle(color = theme.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TABULAR_NUMBERS),
        )
    }
}

/** Minimum row height of the inbox, dp. */
const val INBOX_ROW_DP = 52

@Composable
private fun SkeletonRows(theme: GiftingTheme, loadingLabel: String) {
    Column(
        Modifier.clearAndSetSemantics {
            contentDescription = loadingLabel
            progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
        }.testTag("gift-inbox-skeleton"),
    ) {
        for (i in 0 until 3) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = INBOX_ROW_DP.dp).padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(theme.border))
                Box(Modifier.weight(1f).heightIn(min = 12.dp).clip(RoundedCornerShape(6.dp)).background(theme.border))
            }
        }
    }
}
