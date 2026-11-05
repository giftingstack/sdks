package com.giftingstack.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.assertExists
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import com.giftingstack.core.BattleBarLabels
import com.giftingstack.core.BattleSide
import com.giftingstack.core.BattleView
import org.junit.Rule
import org.junit.Test

private object BarInstant : GiftImageLoader {
    private val bmp = ImageBitmap(8, 8)

    override fun peek(url: String) = bmp

    override suspend fun load(url: String) = bmp

    override fun prefetch(url: String) {}
}

private fun view(a: Long, b: Long, remainingMs: Long = 61_000, round: String = "r1"): BattleView {
    val total = a + b
    return BattleView(
        round = round,
        open = remainingMs > 0,
        remainingMs = remainingMs,
        total = total,
        sides =
            listOf(
                BattleSide("mia", a, 1, if (total > 0) a.toDouble() / total else 0.5),
                BattleSide("theo", b, 1, if (total > 0) b.toDouble() / total else 0.5),
            ),
        leader = if (a == b) null else if (a > b) "mia" else "theo",
    )
}

private val users = mapOf("mia" to BattleBarUser("Mia"), "theo" to BattleBarUser("Theo"))

/**
 * Compose tests of the battle bar (SPEC 18.7). They need a device or an emulator
 * (`connectedDebugAndroidTest`); the numbers behind them (split, clock, colours, words) run on the
 * JVM in `BattleBarConformanceTest`.
 */
class GiftBattleBarUiTest {
    @get:Rule val rule = createComposeRule()

    private fun show(v: BattleView?, reduced: Boolean = true, labels: BattleBarLabels = BattleBarLabels(), theme: GiftingTheme = GiftingTheme()) {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides BarInstant) {
                Box(Modifier.width(358.dp)) {
                    GiftBattleBar(v, users = users, reducedMotion = reduced, labels = labels, theme = theme)
                }
            }
        }
    }

    @Test
    fun drawsNothingWithoutARound() {
        show(null)
        rule.onNodeWithTag("gift-battle-bar").assertDoesNotExist()
    }

    @Test
    fun showsBothSidesTheClockAndTheScores() {
        show(view(300, 100, remainingMs = 30_000))
        rule.onNodeWithTag("gift-battle-bar").assertExists()
        rule.onNodeWithTag("gift-battle-score-0", useUnmergedTree = true).assertTextEquals("300")
        rule.onNodeWithTag("gift-battle-score-1", useUnmergedTree = true).assertTextEquals("100")
        rule.onNodeWithTag("gift-battle-clock", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("gift-battle-banner").assertDoesNotExist()
    }

    @Test
    fun oneSentenceForAScreenReader() {
        show(view(5, 1, remainingMs = 0))
        rule.onNodeWithContentDescription("Mia 5, Theo 1. Mia wins the round").assertExists()
    }

    @Test
    fun endedRoundShowsTheBannerAndTheCrown() {
        show(view(5, 1, remainingMs = 0))
        rule.onNodeWithTag("gift-battle-banner", useUnmergedTree = true).assertTextEquals("Mia wins the round")
        rule.onNodeWithTag("gift-battle-crown", useUnmergedTree = true).assertExists()
    }

    @Test
    fun aDrawHasNoCrown() {
        show(view(4, 4, remainingMs = 0))
        rule.onNodeWithTag("gift-battle-banner", useUnmergedTree = true).assertTextEquals("Draw: nobody wins this round")
        rule.onNodeWithTag("gift-battle-crown", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun scoresUseTheShortFormAndLabelsTranslate() {
        show(view(135_484, 9_999, remainingMs = 0), labels = BattleBarLabels(finalText = "Bitti", wins = "{name} kazandi"))
        rule.onNodeWithTag("gift-battle-score-0", useUnmergedTree = true).assertTextEquals("135K")
        rule.onNodeWithTag("gift-battle-score-1", useUnmergedTree = true).assertTextEquals("9,999")
        rule.onNodeWithTag("gift-battle-banner", useUnmergedTree = true).assertTextEquals("Mia kazandi")
    }

    @Test
    fun reducedMotionJumpsToTheNewScore() {
        var v by mutableStateOf(view(100, 100))
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides BarInstant) {
                Box(Modifier.width(358.dp)) { GiftBattleBar(v, users = users, reducedMotion = true) }
            }
        }
        v = view(1_000, 100)
        rule.waitForIdle()
        rule.onNodeWithTag("gift-battle-score-0", useUnmergedTree = true).assertTextEquals("1,000")
    }
}
