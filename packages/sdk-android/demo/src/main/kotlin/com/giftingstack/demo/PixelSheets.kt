package com.giftingstack.demo

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.giftingstack.core.EffectQuality
import com.giftingstack.ui.GiftingTheme

/** A pretend coin pack. Nothing is charged. */
internal class CoinPack(val coins: Int, val price: String)

internal val COIN_PACKS = listOf(CoinPack(1_000, "$0.99"), CoinPack(5_000, "$4.49"), CoinPack(20_000, "$15.99"))

/** A modal bottom sheet: a scrim (tap or Back closes) and a panel at the bottom, at most [maxFraction] of the height. */
@Composable
internal fun ModalSheet(theme: GiftingTheme, onClose: () -> Unit, maxFraction: Float = 0.85f, content: @Composable () -> Unit) {
    BackHandler(onBack = onClose)
    BoxWithConstraints(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(onClick = onClose), contentAlignment = Alignment.BottomCenter) {
        Column(
            Modifier.fillMaxWidth()
                .heightIn(max = maxHeight * maxFraction)
                .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                .background(theme.surface)
                .clickable(enabled = false) {}
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 20.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.align(Alignment.CenterHorizontally).size(width = 40.dp, height = 4.dp).clip(RoundedCornerShape(2.dp)).background(theme.border))
            content()
        }
    }
}

/** The demo's pretend coin store: a pack ADDS its coins to the balance. */
@Composable
internal fun CoinStoreSheet(theme: GiftingTheme, onBuy: (Int) -> Unit, onClose: () -> Unit) {
    ModalSheet(theme, onClose) {
        Txt("Get coins", theme.text, 18f, bold = true)
        Txt("Demo store: nothing is charged.", theme.muted, 12f)
        for (pack in COIN_PACKS) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(14.dp)).background(theme.background).clickable { onBuy(pack.coins) }.padding(horizontal = 16.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Txt("+${com.giftingstack.ui.formatCoins(pack.coins)} coins", theme.text, 15f, bold = true)
                Txt(pack.price, theme.coin, 15f, bold = true)
            }
        }
        Txt("Not now", theme.muted, 14f, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = onClose).padding(10.dp), align = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

/** Long-press (1 s) on the element opens the developer menu. A short tap passes through. */
internal fun Modifier.devTrigger(onOpen: () -> Unit): Modifier =
    pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false)
            var held = true
            withTimeoutOrNull(DEV_HOLD_MS) {
                waitForUpOrCancellation()
                held = false
            }
            if (held) {
                onOpen()
                waitForUpOrCancellation()
            }
        }
    }

@Composable
private fun DevChip(label: String, selected: Boolean, theme: GiftingTheme, onClick: () -> Unit) {
    Box(
        Modifier.heightIn(min = 44.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) theme.accent else Color.Transparent)
            .border(1.dp, if (selected) theme.accent else theme.border, RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .semantics { role = Role.Button; this.selected = selected }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) { Txt(label, if (selected) theme.accentText else theme.text, 13f, bold = true) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> ChoiceRow(label: String, options: List<T>, current: T, theme: GiftingTheme, text: (T) -> String, onPick: (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(label, theme.muted, 12f, bold = true)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (o in options) DevChip(text(o), o == current, theme) { onPick(o) }
        }
    }
}

/** What the developer menu can make the demo do. */
internal class DevActions(
    val playIncoming: () -> Unit,
    val combo: () -> Unit,
    val awayAgain: () -> Unit,
    val wallPlus: () -> Unit,
    val reset: () -> Unit,
    val change: ((DevSettings) -> DevSettings) -> Unit,
)

/** The hidden developer menu: the only debug surface of the demo. Not part of the SDK. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun DevMenuSheet(settings: DevSettings, theme: GiftingTheme, actions: DevActions, onClose: () -> Unit) {
    ModalSheet(theme, onClose) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Txt(DEV_MENU_TITLE, theme.text, 16f, bold = true, modifier = Modifier.weight(1f))
            DevChip("Done", false, theme, onClose)
        }
        ChoiceRow("Incoming gift", IncomingMode.entries, settings.incoming, theme, { it.label }) { m -> actions.change { it.copy(incoming = m) } }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Txt("Play", theme.muted, 12f, bold = true)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DevChip("Play gift", false, theme, actions.playIncoming)
                DevChip("x5 combo", false, theme, actions.combo)
                DevChip("Away summary again", false, theme, actions.awayAgain)
                DevChip("Wall +5", false, theme, actions.wallPlus)
            }
        }
        ChoiceRow("Quality", EffectQuality.entries, settings.quality, theme, { if (it == EffectQuality.High) "High" else "Low" }) { v -> actions.change { it.copy(quality = v) } }
        ChoiceRow("Theme", DemoTheme.entries, settings.theme, theme, { it.label }) { v -> actions.change { it.copy(theme = v) } }
        ChoiceRow("Motion", DemoMotion.entries, settings.motion, theme, { it.label }) { v -> actions.change { it.copy(motion = v) } }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Txt("Mock failure", theme.muted, 12f, bold = true)
                Txt("Go offline: every call fails", theme.text, 13f)
            }
            PixelSwitch(settings.offline, theme, "Mock failure: go offline") { v -> actions.change { it.copy(offline = v) } }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Txt("Demo", theme.muted, 12f, bold = true)
            Row { DevChip("Reset demo", false, theme, actions.reset) }
        }
    }
}
