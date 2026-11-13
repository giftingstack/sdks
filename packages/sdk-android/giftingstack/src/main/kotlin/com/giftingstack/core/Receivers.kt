package com.giftingstack.core

/**
 * The receiver picker of a battle tray (SPEC 21): one gift button, the tray's "Send to" row picks the side.
 * Pure: the holder keeps `selected` and `last`, the tray draws the row. Port of `packages/sdk-js/src/core/receivers.ts`.
 */

/**
 * One side the viewer can send to.
 *
 * @param id your user id of the receiver.
 * @param name the name shown under the avatar.
 * @param color the side colour (ring) as `#rgb`, `#rrggbb` or `rgba(r, g, b, a)`; null: the battle palette
 *   ([battleSidePalette], the same default as the battle bar).
 * @param avatarUrl a picture; null: the name's first letter on the side colour.
 */
data class TrayReceiver(
    val id: String,
    val name: String,
    val color: String? = null,
    val avatarUrl: String? = null,
)

/**
 * Which side the next gift goes to (SPEC 21.2): [selected] if it is in [ids], else [last] if in [ids], else
 * [fallback] if in [ids], else the first id; with no ids, [fallback].
 */
fun resolveReceiver(
    ids: List<String>,
    selected: String? = null,
    last: String? = null,
    fallback: String? = null,
): String? {
    if (ids.isEmpty()) return fallback
    for (id in listOf(selected, last, fallback)) if (id != null && id in ids) return id
    return ids[0]
}

/** The default label of the tray's "Send to" row. */
const val SEND_TO_LABEL = "Send to"

/** The default label of a tappable battle side; `{name}` is replaced. */
const val PRESS_SIDE_LABEL = "Send {name} a gift"

/** [PRESS_SIDE_LABEL] (or your [template]) for the side called [name]. */
fun pressSideLabel(name: String, template: String = PRESS_SIDE_LABEL): String = template.replace("{name}", name)
