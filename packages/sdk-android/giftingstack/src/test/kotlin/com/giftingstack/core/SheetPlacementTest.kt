package com.giftingstack.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** The first placement of the sheet: no flight from the guess to the real position, one soft entrance. */
class SheetPlacementTest {
    @Test fun anUnmeasuredOrUnplacedSheetJumpsNeverSprings() {
        assertEquals(SheetMove.Jump, sheetMove(placed = false, measured = false, dragging = false, reducedMotion = false))
        assertEquals(SheetMove.Jump, sheetMove(placed = false, measured = true, dragging = false, reducedMotion = false))
        assertEquals(SheetMove.Jump, sheetMove(placed = true, measured = false, dragging = false, reducedMotion = false))
    }

    @Test fun aPlacedSheetSpringsExceptWhileDraggingOrWithReducedMotion() {
        assertEquals(SheetMove.Spring, sheetMove(placed = true, measured = true, dragging = false, reducedMotion = false))
        assertEquals(SheetMove.Jump, sheetMove(placed = true, measured = true, dragging = true, reducedMotion = false))
        assertEquals(SheetMove.Jump, sheetMove(placed = true, measured = true, dragging = false, reducedMotion = true))
    }

    @Test fun theWholeSheetIsInvisibleUntilPlacedThenFadesInAndRises() {
        assertEquals(0.0, sheetEntranceAlpha(placed = false, progress = 1.0, reducedMotion = false), 0.0)
        assertEquals(0.0, sheetEntranceRise(placed = false, progress = 0.0, reducedMotion = false), 0.0)
        assertEquals(0.0, sheetEntranceAlpha(placed = true, progress = 0.0, reducedMotion = false), 0.0)
        assertEquals(SHEET_ENTRANCE_RISE_DP, sheetEntranceRise(placed = true, progress = 0.0, reducedMotion = false), 0.0)
        assertEquals(0.5, sheetEntranceAlpha(placed = true, progress = 0.5, reducedMotion = false), 0.0)
        assertEquals(12.0, sheetEntranceRise(placed = true, progress = 0.5, reducedMotion = false), 0.0)
        assertEquals(1.0, sheetEntranceAlpha(placed = true, progress = 1.0, reducedMotion = false), 0.0)
        assertEquals(0.0, sheetEntranceRise(placed = true, progress = 1.0, reducedMotion = false), 0.0)
    }

    @Test fun reducedMotionShowsTheSheetAtOnceWithoutAnEntrance() {
        assertEquals(0.0, sheetEntranceAlpha(placed = false, progress = 0.0, reducedMotion = true), 0.0)
        assertEquals(1.0, sheetEntranceAlpha(placed = true, progress = 0.0, reducedMotion = true), 0.0)
        assertEquals(0.0, sheetEntranceRise(placed = true, progress = 0.0, reducedMotion = true), 0.0)
    }
}
