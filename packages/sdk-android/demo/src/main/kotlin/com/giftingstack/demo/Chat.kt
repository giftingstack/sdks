package com.giftingstack.demo

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import com.giftingstack.ui.GiftButton
import com.giftingstack.ui.GiftTrayHolder
import com.giftingstack.ui.GiftingTheme
import com.giftingstack.ui.giftTrayInput

// ---- the app's own chat (GiftingStack carries no chat). What comes from the SDK is the tray, the
// effects, GiftButton and Modifier.giftTrayInput: the gift button puts the tray where the keyboard was.

/** One line of the demo's own conversation or comment column. */
sealed interface ChatMessage

/** A text message; [from] is null for you. */
data class ChatText(val from: String?, val text: String) : ChatMessage

/**
 * A gift line; [from] is null for you. Quick repeats of the same gift by the same person to the same receiver add up in
 * [count]. [receiver] is who got it in a battle (the line takes that side's colour), else null.
 */
data class ChatGift(val from: String?, val giftId: String, val name: String, val icon: String?, val count: Long, val receiver: String? = null, val at: Long = 0L) : ChatMessage

/** How long a gift line stays open for the next gift of its combo (the web demo's window). */
const val COMBO_LINE_MS = 5_000L

/** The one-to-one conversation of the Chat tab. */
const val CHAT_PEER = DEMO_AUTHOR

/** The reference of a gift sent in the chat (a real app might use the conversation id). */
const val CHAT_REFERENCE = "dm_ava_mateo"

val CHAT_START: List<ChatMessage> =
    listOf(
        ChatText(CHAT_PEER, "Did you catch my stream last night?"),
        ChatText(null, "Yes! The ending was wild 😄"),
        ChatText(CHAT_PEER, "Right?? Going live again on Friday"),
    )

const val CHAT_THANKS = "Thank you!! 😍"

/**
 * Adds a gift line. A running combo (the same gift from the same person to the same receiver, its line touched less
 * than [COMBO_LINE_MS] ago) adds [quantity] to its line wherever it is (a comment or a thank-you in between does not
 * cut the count). In a comment column ([moveDown]) the line moves to the bottom; in a conversation it stays where it
 * is, above its thank-you.
 */
fun addGiftLine(
    list: List<ChatMessage>,
    from: String?,
    giftId: String,
    name: String,
    icon: String?,
    quantity: Long,
    receiver: String? = null,
    now: Long = System.currentTimeMillis(),
    moveDown: Boolean = true,
): List<ChatMessage> {
    val i = list.indexOfLast { it is ChatGift && it.from == from && it.giftId == giftId && it.receiver == receiver && now - it.at < COMBO_LINE_MS }
    if (i < 0) return list + ChatGift(from, giftId, name, icon, quantity, receiver, now)
    val running = list[i] as ChatGift
    val updated = running.copy(count = running.count + quantity, at = now)
    return if (moveDown) list.filterIndexed { j, _ -> j != i } + updated else list.mapIndexed { j, m -> if (j == i) updated else m }
}

/**
 * Whether a send in the chat asks for a (new) thank-you: a new bubble does, and so does a combo whose bubble is still
 * the last line (its thank-you is not there yet); a combo that goes on after its thank-you (the bubble stays above it)
 * does not, so one combo gets one thank-you.
 */
fun needsThanks(before: List<ChatMessage>, after: List<ChatMessage>): Boolean = after.size != before.size || after.last() != before.last()

/** "You sent Rose ×3" / "Zoe sent Rose" / in a battle "Zoe sent Rose to Mia". */
fun giftLineText(m: ChatGift): String =
    "${m.from?.let { firstName(it) } ?: "You"} sent ${m.name}" + (m.receiver?.let { " to ${firstName(it)}" } ?: "") + if (m.count > 1) " ×${m.count}" else ""

/** A comment column keeps its last few lines (the stream stays in sight). */
fun keepLast(list: List<ChatMessage>, max: Int = 5): List<ChatMessage> = if (list.size > max) list.takeLast(max) else list

/**
 * How far the message bar is lifted above the bottom of its own box: the tray's top edge when the tray is open, else
 * the keyboard, minus what already sits below the box (the tab bar and the navigation bar).
 */
fun barLift(trayOpen: Boolean, trayInset: Dp, keyboard: Dp, below: Dp): Dp = maxOf(0.dp, (if (trayOpen) trayInset else keyboard) - below)

@Composable
internal fun imeHeight(): Dp {
    val density = LocalDensity.current
    return with(density) { WindowInsets.ime.getBottom(density).toDp() }
}

/**
 * The Chat tab: a conversation the app draws itself and its message bar (text field + GiftButton + Send). The field
 * is bound to [tray] with `Modifier.giftTrayInput`; the tray itself is drawn by the caller over the whole screen.
 */
@Composable
internal fun ChatScreen(messages: List<ChatMessage>, tray: GiftTrayHolder, theme: GiftingTheme, trayInset: Dp, below: Dp, onSend: (String) -> Unit) {
    val list = rememberLazyListState()
    LaunchedEffect(messages) { if (messages.isNotEmpty()) list.animateScrollToItem(messages.size - 1) }
    val lift = barLift(tray.isOpen, trayInset, imeHeight(), below)
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    Column(Modifier.fillMaxSize().testTag("chat-screen")) {
        Row(
            Modifier.fillMaxWidth().background(theme.surface).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(CHAT_PEER, 36.dp)
            Column {
                Txt(displayName(CHAT_PEER), theme.text, 15f, bold = true)
                Txt("online", theme.muted, 12f)
            }
        }
        LazyColumn(
            // A tap on the conversation puts the tray (or the keyboard) away, as chat apps do; no dim over the chat.
            Modifier.weight(1f).fillMaxWidth().testTag("chat-list").pointerInput(tray) {
                detectTapGestures {
                    tray.close()
                    focus.clearFocus()
                }
            },
            state = list,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        ) {
            item {
                Txt(
                    "The conversation is your app's chat. The gift button opens the GiftingStack tray in the keyboard's place.",
                    theme.muted,
                    12f,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                    align = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
            itemsIndexed(messages) { _, m -> Bubble(m, theme) }
        }
        MessageBar(tray, theme, "Message", "chat", onSend)
        Spacer(Modifier.height(lift))
    }
}

@Composable
private fun Bubble(m: ChatMessage, theme: GiftingTheme) {
    val mine = when (m) {
        is ChatText -> m.from == null
        is ChatGift -> m.from == null
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        Box(
            Modifier.widthIn(max = 280.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(if (mine) theme.accent else theme.surface)
                .padding(horizontal = 14.dp, vertical = 9.dp),
        ) {
            val fg = if (mine) theme.accentText else theme.text
            when (m) {
                is ChatText -> Txt(m.text, fg, 15f)
                is ChatGift ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("chat-gift")) {
                        UrlImage(m.icon, 44.dp)
                        Txt(giftLineText(m), fg, 15f, bold = true)
                    }
            }
        }
    }
}

/** The message bar's height: the 44 dp field and Send plus 8 dp above and below. */
internal val MESSAGE_BAR_HEIGHT = 60.dp

/**
 * The app's message bar: its text field with the gift button inside (like an emoji button) and its own Send. The
 * field is bound to the tray, so the gift button swaps the keyboard for the tray and a tap on the field swaps back.
 */
@Composable
internal fun MessageBar(tray: GiftTrayHolder, theme: GiftingTheme, placeholder: String, tag: String, onSend: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    val send = {
        val t = text.trim()
        if (t.isNotEmpty()) {
            onSend(t)
            text = ""
        }
    }
    Row(
        Modifier.fillMaxWidth().background(theme.surface).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp)).background(theme.background).padding(start = 16.dp, end = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = text,
                onValueChange = { text = it },
                // The SDK binding: the tray takes the keyboard's place and gives it back.
                modifier = Modifier.weight(1f).giftTrayInput(tray).testTag("$tag-input").semantics { contentDescription = placeholder },
                singleLine = true,
                textStyle = TextStyle(color = theme.text, fontSize = 15.sp),
                cursorBrush = SolidColor(theme.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { send() }),
                decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (text.isEmpty()) Txt(placeholder, theme.muted, 15f)
                        inner()
                    }
                },
            )
            GiftButton(tray = tray, theme = theme, modifier = Modifier.testTag("$tag-gift"))
        }
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(theme.accent).clickable(onClick = send)
                .semantics {
                    role = Role.Button
                    contentDescription = "Send"
                }
                .testTag("$tag-send"),
            contentAlignment = Alignment.Center,
        ) { SendGlyph(theme.accentText) }
    }
}

/** A paper plane. */
@Composable
private fun SendGlyph(color: androidx.compose.ui.graphics.Color) {
    Canvas(Modifier.size(20.dp)) {
        val k = size.width / 24f
        val p = Path().apply {
            moveTo(4f * k, 12f * k)
            lineTo(20f * k, 4f * k)
            lineTo(14f * k, 20f * k)
            lineTo(11f * k, 13f * k)
            close()
        }
        drawPath(p, color, style = Fill)
        drawPath(p, color, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.5f * k, join = StrokeJoin.Round))
        drawLine(color, Offset(11f * k, 13f * k), Offset(20f * k, 4f * k), 1.2f * k)
    }
}

/** The comment column over the live stream: comments and gifts in one column, the newest at the bottom. */
@Composable
internal fun LiveComments(lines: List<ChatMessage>, modifier: Modifier = Modifier, sideColor: (String) -> androidx.compose.ui.graphics.Color? = { null }) {
    Column(modifier.testTag("live-comments"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (m in lines) {
            val text =
                when (m) {
                    is ChatText -> "${m.from?.let { firstName(it) } ?: "You"}: ${m.text}"
                    is ChatGift -> giftLineText(m)
                }
            val side = (m as? ChatGift)?.receiver?.let(sideColor)
            Row(
                Modifier.clip(RoundedCornerShape(12.dp))
                    .background(androidx.compose.ui.graphics.Color(0x8C000000))
                    // A battle gift takes the receiving side's colour (the bar's colours, SPEC 21.5).
                    .then(side?.let { Modifier.border(2.dp, it, RoundedCornerShape(12.dp)) } ?: Modifier)
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (m is ChatGift) UrlImage(m.icon, 20.dp)
                Txt(text, androidx.compose.ui.graphics.Color.White, 13f, bold = m is ChatGift, maxLines = 2)
            }
        }
    }
}
