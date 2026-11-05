package com.giftingstack.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same cases as `packages/sdk-js/test/web-anim.test.ts` "pictureScale". */
class PictureScaleTest {
    @Test fun isOneOnAPhoneLayerGrowsInAWideLayerAndStopsAtTwo() {
        assertEquals(1.0, pictureScale(390.0, 700.0, 2.8), 0.0)
        val wide = pictureScale(877.0, 493.0, 1.5)
        assertTrue(wide > 1.2 && wide < 1.4)
        assertEquals(2.0, pictureScale(3000.0, 2000.0, 1.5), 0.0)
    }

    @Test fun neverLetsThePicturePassNinetyPercentOfTheShortSide() {
        assertEquals(0.9643, pictureScale(600.0, 300.0, 2.8), 0.0001)
        assertEquals(0.9643, pictureScale(600.0, 300.0, 2.8, 5.0), 0.0001)
    }

    @Test fun takesAManualMultiplierInsteadOfTheAutomaticOne() {
        assertEquals(1.5, pictureScale(390.0, 700.0, 0.9, 1.5), 0.0)
        assertEquals(1.0, pictureScale(1200.0, 800.0, 0.9, 1.0), 0.0)
    }
}
