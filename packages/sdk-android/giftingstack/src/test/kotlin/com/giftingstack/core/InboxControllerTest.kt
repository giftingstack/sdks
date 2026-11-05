package com.giftingstack.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The paging logic of the inbox and the small pure helpers around it. */
@OptIn(ExperimentalCoroutinesApi::class)
class InboxControllerTest {
    private fun item(id: String, at: String = "2026-11-02T09:00:00.000Z", status: String = "completed", sender: String? = "ayla") =
        InboxItem(id, at, sender, InboxGift("rose", "Rose", 10, null, null), 1, 10, status)

    private fun page(items: List<InboxItem>, next: String?) = Inbox("me", "s", "u", items, next != null, next)

    /** Answers the calls in order; a call with no answer left waits on [gate]. */
    private class Fake(val answers: MutableList<Any>) : InboxApi {
        val queries = ArrayList<InboxQuery>()
        var gate: CompletableDeferred<Inbox>? = null

        override suspend fun getInbox(query: InboxQuery): Inbox {
            queries.add(query)
            if (answers.isEmpty()) return gate!!.await()
            val next = answers.removeAt(0)
            if (next is Throwable) throw next
            return next as Inbox
        }
    }

    @Test fun firstPageThenShowMoreAppendsAndOlderPageEndsTheList() = runTest {
        val api = Fake(mutableListOf(page(listOf(item("a"), item("b")), "c1"), page(listOf(item("c")), null)))
        val loaded = ArrayList<Int>()
        val c = InboxController(api, backgroundScope, pageSize = 2)
        c.onLoaded = { loaded.add(it.size) }
        c.start()
        assertEquals(InboxStatus.Ready, c.state.value.status)
        assertTrue(c.state.value.hasMore)
        assertEquals(InboxQuery(limit = 2), api.queries[0])
        c.loadMore()
        assertEquals(listOf("a", "b", "c"), c.state.value.items.map { it.id })
        assertFalse(c.state.value.hasMore)
        assertEquals(InboxQuery(cursor = "c1", limit = 2), api.queries[1])
        assertEquals(listOf(2, 3), loaded)
        // No older page: nothing is asked.
        c.loadMore()
        assertEquals(2, api.queries.size)
    }

    @Test fun emptyWhenThereAreNoCompletedGifts() = runTest {
        val api = Fake(mutableListOf(page(emptyList(), null)))
        val c = InboxController(api, backgroundScope)
        c.start()
        assertEquals(InboxStatus.Empty, c.state.value.status)
    }

    @Test fun onlyReversedGiftsWithAnOlderPageStayReadySoShowMoreCanFetchTheRest() = runTest {
        val api = Fake(mutableListOf(page(listOf(item("a", status = "reversed")), "c1"), page(listOf(item("b")), null)))
        val c = InboxController(api, backgroundScope)
        c.start()
        assertEquals(InboxStatus.Ready, c.state.value.status)
        assertTrue(inboxRows(c.state.value.items, 0).isEmpty())
        c.loadMore()
        assertEquals(listOf("b"), inboxRows(c.state.value.items, 0).map { it.id })
    }

    @Test fun failedFirstLoadShowsErrorAndRefreshRecovers() = runTest {
        val api = Fake(mutableListOf(GiftingException(0, "network_error", "x"), page(listOf(item("a")), null)))
        val errors = ArrayList<String>()
        val c = InboxController(api, backgroundScope)
        c.onError = { errors.add(it.type) }
        c.start()
        assertEquals(InboxStatus.Error, c.state.value.status)
        assertEquals(listOf("network_error"), errors)
        c.refresh()
        assertEquals(InboxStatus.Ready, c.state.value.status)
        assertEquals(listOf("a"), c.state.value.items.map { it.id })
    }

    @Test fun failedShowMoreKeepsTheRowsAndAllowsAnotherTry() = runTest {
        val api = Fake(mutableListOf(page(listOf(item("a")), "c1"), GiftingException(503, "x", "x"), page(listOf(item("b")), null)))
        val c = InboxController(api, backgroundScope)
        c.start()
        c.loadMore()
        assertEquals(InboxStatus.Ready, c.state.value.status)
        assertEquals(listOf("a"), c.state.value.items.map { it.id })
        assertTrue(c.state.value.hasMore)
        assertFalse(c.state.value.loadingMore)
        c.loadMore()
        assertEquals(listOf("a", "b"), c.state.value.items.map { it.id })
    }

    @Test fun refreshKeepsRowsAndReplacesThemFromTheFirstPage() = runTest {
        val api = Fake(mutableListOf(page(listOf(item("a")), "c1"), page(listOf(item("n"), item("a")), null)))
        val c = InboxController(api, backgroundScope)
        c.start()
        c.refresh()
        assertEquals(listOf("n", "a"), c.state.value.items.map { it.id })
        assertNull(api.queries[1].cursor)
    }

    @Test fun showMoreWhileLoadingIsIgnoredAndAnAnswerAfterDisposeChangesNothing() = runTest {
        val api = Fake(mutableListOf(page(listOf(item("a")), "c1")))
        val c = InboxController(api, backgroundScope)
        c.start()
        api.gate = CompletableDeferred()
        c.loadMore()
        assertTrue(c.state.value.loadingMore)
        c.loadMore()
        assertEquals(2, api.queries.size)
        c.dispose()
        api.gate!!.complete(page(listOf(item("b")), null))
        assertEquals(listOf("a"), c.state.value.items.map { it.id })
    }

    @Test fun isoTimesParseToEpochMillis() {
        assertEquals(0L, parseIsoTimeMs("1970-01-01T00:00:00.000Z"))
        assertEquals(1793613600000L, parseIsoTimeMs("2026-11-02T10:00:00.000Z"))
        assertEquals(1793613600500L, parseIsoTimeMs("2026-11-02T10:00:00.5Z"))
        assertEquals(1793613600000L, parseIsoTimeMs("2026-11-02T10:00:00Z"))
        assertEquals("an offset moves the instant", 1793613600000L, parseIsoTimeMs("2026-11-02T13:00:00+03:00"))
        assertNull(parseIsoTimeMs("yesterday"))
    }

    @Test fun spokenTimeAndRowSentence() {
        assertEquals("just now", inboxTimeSpoken("now"))
        assertEquals("1 minute ago", inboxTimeSpoken("1m"))
        assertEquals("3 hours ago", inboxTimeSpoken("3h"))
        assertEquals("2 days ago", inboxTimeSpoken("2d"))
        val rows = inboxRows(listOf(item("a")), 0, mapOf("ayla" to "Ayla K."))
        assertEquals("Ayla K. sent you Rose", inboxRowText(rows[0]))
        assertEquals("Ayla K. sent you Rose x3", inboxRowText(rows[0].copy(quantity = 3)))
    }
}
