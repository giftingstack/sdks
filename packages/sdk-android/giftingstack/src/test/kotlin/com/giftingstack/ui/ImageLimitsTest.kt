package com.giftingstack.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** R-08: how big a decoded picture may be (the URL rules and the failure memory are in PicturesConformanceTest). */
class ImageLimitsTest {
    @Test
    fun theSampleSizeKeepsAPictureWithinTheSideAndPixelLimits() {
        assertEquals(1, imageSampleSize(512, 512))
        assertEquals(1, imageSampleSize(1024, 1024)) // 1,048,576 px
        assertEquals(2, imageSampleSize(2048, 1000))
        assertEquals(4, imageSampleSize(4096, 4096))
        assertEquals(1, imageSampleSize(0, 0))
        for ((w, h) in listOf(1025 to 10, 4000 to 3000, 12_000 to 9000, 30_000 to 2)) {
            val s = imageSampleSize(w, h)
            assertTrue("$w x $h sample $s", w / s <= IMAGE_MAX_SIDE && h / s <= IMAGE_MAX_SIDE)
            assertTrue("$w x $h sample $s", (w / s).toLong() * (h / s) <= IMAGE_MAX_PIXELS)
            assertEquals("a power of two", 0, s and (s - 1))
        }
    }
}
