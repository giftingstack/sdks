package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private const val URL = "https://assets.example.test/recipes.json"
private const val HOUR = 3_600_000L

private fun doc(combo: Int = 3000, sparks: Int = 90) =
    """{"specVersion":"1.0.0","comboWindowMs":$combo,"recipes":{"high":{"large":{"sparks":$sparks}}}}"""

private class FakeStorage(val data: MutableMap<String, String> = HashMap(), val throwing: Boolean = false) : RecipesStorage {
    override fun get(key: String): String? = if (throwing) error("blocked") else data[key]

    override fun set(key: String, value: String) {
        if (throwing) error("full")
        data[key] = value
    }
}

private class Script(var next: () -> String) {
    var calls = 0
    val fetch = RecipesFetch { calls++; next() }
}

@OptIn(ExperimentalCoroutinesApi::class)
class RecipesLoaderTest {
    private var clock = 1_000_000L

    @Before fun reset() {
        clock = 1_000_000L
        RecipesLoaders.reset()
    }

    private fun loader(script: Script?, storage: RecipesStorage? = FakeStorage()) = RecipesLoader(URL, script?.fetch, storage, { clock })

    @Test fun usesTheCachedCopyAtOnceWithoutTheNetwork() {
        val storage = FakeStorage()
        storage.data["giftingstack:recipes:$URL"] = """{"fetchedAt":$clock,"doc":${doc()}}"""
        val s = Script { error("no network expected") }
        val l = loader(s, storage)
        assertEquals(3000L, l.current()!!.set.comboWindowMs)
        assertEquals(0, s.calls)
    }

    @Test fun cachedCopyIsParsedAgainSoNewLimitsApplyAndGarbageIsIgnored() {
        val storage = FakeStorage()
        storage.data["giftingstack:recipes:$URL"] = """{"fetchedAt":$clock,"doc":${doc(combo = 99999)}}"""
        assertEquals(10_000L, loader(null, storage).current()!!.set.comboWindowMs)
        for (bad in listOf("not json", """{"fetchedAt":1,"doc":{"specVersion":"2.0.0"}}""", """{"doc":${doc()}}""", "[]")) {
            val st = FakeStorage()
            st.data["giftingstack:recipes:$URL"] = bad
            assertNull(bad, loader(null, st).current())
        }
    }

    @Test fun fetchesAppliesAndCachesAndConcurrentRefreshesShareOneRequest() = runTest {
        val gate = CompletableDeferred<String>()
        var calls = 0
        val storage = FakeStorage()
        val l = RecipesLoader(URL, { calls++; gate.await() }, storage, { clock })
        assertNull(l.current())
        val a = async { l.refresh() }
        val b = async { l.refresh() }
        testScheduler.runCurrent()
        gate.complete(doc())
        a.await(); b.await()
        assertEquals(1, calls)
        assertEquals(3000L, l.current()!!.set.comboWindowMs)
        assertTrue(storage.data.getValue("giftingstack:recipes:$URL").contains("\"fetchedAt\":$clock"))
    }

    @Test fun refreshesAtMostOncePerSixHours() = runTest {
        val s = Script { doc() }
        val l = loader(s)
        l.refresh(); l.refresh()
        assertEquals(1, s.calls)
        clock += 6 * HOUR - 1
        l.refresh()
        assertEquals(1, s.calls)
        clock += 1
        l.refresh()
        assertEquals(2, s.calls)
    }

    @Test fun aCachedCopyOlderThanSixHoursIsUsedNowAndRefreshed() = runTest {
        val storage = FakeStorage()
        storage.data["giftingstack:recipes:$URL"] = """{"fetchedAt":${clock - 7 * HOUR},"doc":${doc(combo = 3000)}}"""
        val s = Script { doc(combo = 4000) }
        val l = loader(s, storage)
        assertEquals(3000L, l.current()!!.set.comboWindowMs)
        l.refresh()
        assertEquals(4000L, l.current()!!.set.comboWindowMs)
    }

    @Test fun aClockThatWentBackCountsAsDue() = runTest {
        val storage = FakeStorage()
        storage.data["giftingstack:recipes:$URL"] = """{"fetchedAt":${clock + HOUR},"doc":${doc()}}"""
        val s = Script { doc(combo = 5000) }
        loader(s, storage).refresh()
        assertEquals(1, s.calls)
    }

    @Test fun badJsonHttpErrorAndWrongMajorKeepTheOldCopyAndBackOff() = runTest {
        for (failure in listOf<() -> String>({ "{nope" }, { error("http 500") }, { """{"specVersion":"2.0.0"}""" })) {
            val storage = FakeStorage()
            storage.data["giftingstack:recipes:$URL"] = """{"fetchedAt":${clock - 7 * HOUR},"doc":${doc(combo = 3000)}}"""
            val s = Script(failure)
            val l = loader(s, storage)
            l.refresh()
            assertEquals(1, s.calls)
            assertEquals("old copy stays", 3000L, l.current()!!.set.comboWindowMs)
            assertTrue("nothing written", storage.data.getValue("giftingstack:recipes:$URL").contains("3000"))
            l.refresh() // inside the 1 minute backoff
            assertEquals(1, s.calls)
        }
    }

    @Test fun backsOffOneMinuteTwoMinutesFourMinutesCappedAtSixHours() = runTest {
        val s = Script { error("down") }
        val l = loader(s)
        var expectWait = 60_000L
        var calls = 0
        repeat(9) { n ->
            l.refresh(); calls++
            assertEquals("attempt ${n + 1}", calls, s.calls)
            clock += expectWait - 1
            l.refresh() // still backing off
            assertEquals("backing off after ${n + 1}", calls, s.calls)
            clock += 1
            expectWait = minOf(6 * HOUR, expectWait * 2)
        }
        assertEquals(6 * HOUR, expectWait)
    }

    @Test fun aSuccessResetsTheBackoff() = runTest {
        var ok = false
        val s = Script { if (ok) doc() else error("down") }
        val l = loader(s)
        l.refresh()
        clock += 60_000
        l.refresh()
        assertEquals(2, s.calls)
        clock += 2 * 60_000
        ok = true
        l.refresh()
        assertEquals(3, s.calls)
        assertNotNull(l.current())
        clock += 6 * HOUR
        ok = false
        l.refresh()
        clock += 60_000 // first failure after a success waits one minute again
        l.refresh()
        assertEquals(5, s.calls)
    }

    @Test fun givesUpAfterThreeSecondsAndAbortsTheRequest() = runTest {
        var cancelled = false
        val l = RecipesLoader(URL, { try { awaitCancellation() } finally { cancelled = true } }, FakeStorage(), { clock })
        val job = async { l.refresh() }
        advanceTimeBy(2_999)
        assertEquals(false, cancelled)
        advanceTimeBy(2)
        job.await()
        assertTrue("request aborted", cancelled)
        assertTrue(currentTime >= 3_000L)
        assertNull(l.current())
    }

    @Test fun worksWithoutStorageWithThrowingStorageAndWithoutFetch() = runTest {
        val s = Script { doc() }
        val noStorage = loader(s, null)
        noStorage.refresh()
        assertNotNull(noStorage.current())
        val thrower = loader(Script { doc() }, FakeStorage(throwing = true))
        thrower.refresh()
        assertNotNull(thrower.current())
        val offline = RecipesLoader(URL, null, FakeStorage(), { clock })
        offline.refresh()
        assertNull(offline.current())
    }

    @Test fun remoteRecipesFalseMakesNoLoaderAndNoRequest() {
        var calls = 0
        RecipesLoaders.fetch = RecipesFetch { calls++; doc() }
        try {
            assertNull(RecipesLoaders.forOptions(remoteRecipes = false))
            assertNull("a version that cannot be pinned is off too", RecipesLoaders.forOptions(recipesVersion = "../x"))
            assertEquals(0, calls)
        } finally {
            RecipesLoaders.fetch = DefaultRecipesFetch
        }
    }

    @Test fun sharedLoaderPerUrlAndPinnedVersionUrl() {
        val a = RecipesLoaders.forOptions()!!
        assertTrue(a === RecipesLoaders.forOptions())
        val pinned = RecipesLoaders.forOptions(recipesUrl = URL, recipesVersion = "1.0.0")!!
        assertTrue(pinned === RecipesLoaders.shared("https://assets.example.test/recipes.1.0.0.json"))
    }
}

/** The scheduler with a recipe set (spec 13.4). */
class SchedulerRemoteRecipesTest {
    private fun gift(price: Int, id: String = "g") = GiftEffectEvent(EffectGift(id, id, price.toLong(), null, null), "ayla", null)

    private fun remote(json: String): RecipeSet = parseRemoteRecipes(kotlinx.serialization.json.Json.parseToJsonElement(json))!!.set

    @Test fun withoutASetItUsesTheEmbeddedRecipes() {
        val s = EffectScheduler(now = { 0 })
        val entered = ArrayList<ScheduledEffect>()
        s.listener = object : EffectSchedulerListener { override fun enter(effect: ScheduledEffect) { entered.add(effect) } }
        s.play(gift(20_000))
        assertEquals(recipeFor(EffectTier.Large), entered[0].recipe)
    }

    @Test fun usesTheRemoteRecipesThresholdsAndQualityTable() {
        val set = remote("""{"specVersion":"1.0.0","thresholds":{"mediumFrom":50,"largeFrom":5000},"recipes":{"low":{"medium":{"sparks":7}},"high":{"medium":{"sparks":33}}}}""")
        val s = EffectScheduler(now = { 0 })
        val entered = ArrayList<ScheduledEffect>()
        s.listener = object : EffectSchedulerListener { override fun enter(effect: ScheduledEffect) { entered.add(effect) } }
        s.options = EffectSchedulerOptions(recipes = { set })
        s.play(gift(60)) // medium now
        assertEquals(33, entered[0].recipe.sparks)
        s.options = EffectSchedulerOptions(quality = EffectQuality.Low, recipes = { set })
        s.play(gift(60, "h"))
        assertEquals(7, entered[1].recipe.sparks)
    }

    @Test fun appThresholdsBeatRemoteThresholds() {
        val set = remote("""{"specVersion":"1.0.0","thresholds":{"mediumFrom":50,"largeFrom":5000}}""")
        val s = EffectScheduler(now = { 0 })
        val entered = ArrayList<ScheduledEffect>()
        s.listener = object : EffectSchedulerListener { override fun enter(effect: ScheduledEffect) { entered.add(effect) } }
        s.options = EffectSchedulerOptions(thresholds = TierThresholds(200, 9000), recipes = { set })
        s.play(gift(150)) // small by the app's 200
        assertEquals(EffectTier.Small, entered[0].recipe.tier)
    }

    @Test fun theRemoteComboWindowAppliesUnlessTheAppGaveOne() {
        val set = remote("""{"specVersion":"1.0.0","comboWindowMs":1000}""")
        var t = 0L
        val noticeCounts = ArrayList<Int>()
        fun run(app: Long?): List<Int> {
            noticeCounts.clear()
            t = 0
            val s = EffectScheduler(app, { t })
            s.options = EffectSchedulerOptions(reducedMotion = true, recipes = { set })
            s.listener = object : EffectSchedulerListener { override fun notice(notice: NoticeData, durationMs: Int) { noticeCounts.add(notice.count) } }
            s.play(gift(1)); t = 1500; s.play(gift(1))
            return noticeCounts.toList()
        }
        assertEquals("remote 1000 ms: 1500 ms apart starts over", listOf(1, 1), run(null))
        assertEquals("the app's 2500 wins", listOf(1, 2), run(2500))
    }

    @Test fun effectsAlreadyRunningOrQueuedKeepTheirRecipeWhenANewSetArrives() {
        var current: RecipeSet? = remote("""{"specVersion":"1.0.0","recipes":{"high":{"large":{"sparks":11}}}}""")
        val s = EffectScheduler(now = { 0 })
        s.options = EffectSchedulerOptions(recipes = { current })
        val entered = ArrayList<ScheduledEffect>()
        s.listener = object : EffectSchedulerListener { override fun enter(effect: ScheduledEffect) { entered.add(effect) } }
        val first = s.play(gift(20_000, "a"))
        val second = s.play(gift(20_000, "b")) // queued
        current = remote("""{"specVersion":"1.0.0","recipes":{"high":{"large":{"sparks":99}}}}""")
        val third = s.play(gift(20_000, "c")) // queued, new set
        s.finished(first)
        s.finished(second)
        assertEquals(listOf(11, 11, 99), entered.map { it.recipe.sparks })
        assertTrue(third > second)
    }
}
