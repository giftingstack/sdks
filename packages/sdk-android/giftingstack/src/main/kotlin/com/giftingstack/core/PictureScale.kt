package com.giftingstack.core

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * How much bigger than the phone layout the gift picture is drawn in a wide or tall layer (the web
 * layer's `pictureScale`, `packages/sdk-js/src/web/anim.ts`). A phone layer (about 390 x 700 dp)
 * gives 1; the picture grows with the layer's area up to 2, and never beyond 90 percent of the
 * layer's short side at its biggest. [manual] replaces the automatic value. [width] and [height]
 * are in dp; [peakScale] is the recipe's.
 */
fun pictureScale(width: Double, height: Double, peakScale: Double, manual: Double? = null): Double {
    val room = (0.9 * min(width, height)) / (100.0 * peakScale)
    val wanted = manual ?: min(2.0, max(1.0, sqrt(width * height) / 530.0))
    return min(wanted, max(room, 0.5))
}
