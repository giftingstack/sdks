package com.giftingstack.demo

/**
 * The pretend people and posts of "Pixel", the fake app around the SDK. Demo only: a real app has
 * its own user table and feed. Pure (no Android), so the tests can check it. The content is the
 * same as in the web demo (`packages/sdk-js/demo/shared.ts`).
 */

/** A display name and an avatar colour (0xAARRGGBB) for an external user id. */
data class PixelPerson(val name: String, val color: Long)

val PEOPLE: Map<String, PixelPerson> =
    linkedMapOf(
        "ava" to PixelPerson("Ava Carter", 0xFFE0457B),
        "mateo" to PixelPerson("Mateo Silva", 0xFF2F9E8F),
        "zoe" to PixelPerson("Zoe Lambert", 0xFF7B61FF),
        "caleb" to PixelPerson("Caleb Stone", 0xFFE8892B),
        "dana" to PixelPerson("Dana", 0xFF2A8FD6),
        "ethan" to PixelPerson("Ethan Park", 0xFFC2453D),
        "emma" to PixelPerson("Emma", 0xFFB04FD0),
        "sofia" to PixelPerson("Sofia Rossi", 0xFF1F9D7A),
        "ben" to PixelPerson("Ben", 0xFF6B7A8F),
        "aisha" to PixelPerson("Aisha Khan", 0xFFD6559A),
        "kai" to PixelPerson("Kai", 0xFF4C6EF5),
        "daphne" to PixelPerson("Daphne Lee", 0xFF3AA356),
        "oliver" to PixelPerson("Oliver", 0xFFC9822B),
        "ella" to PixelPerson("Ella Fox", 0xFF8E5BD9),
        "mia" to PixelPerson("Mia", 0xFFD9534F),
        "theo" to PixelPerson("Theo Martin", 0xFF3B82A0),
        "elise" to PixelPerson("Elise", 0xFFD98A2B),
        "mila" to PixelPerson("Mila", 0xFF5A8F3C),
        "owen" to PixelPerson("Owen", 0xFF4A74C9),
        "ada" to PixelPerson("Ada", 0xFFB5527F),
        "irem" to PixelPerson("İrem", 0xFF7A5AC0),
        "yigit" to PixelPerson("Yiğit", 0xFF3F8A8A),
    )

fun displayName(id: String): String = PEOPLE[id]?.name ?: id.replaceFirstChar { it.uppercase() }

fun firstName(id: String): String = displayName(id).substringBefore(' ')

fun userColor(id: String): Long = PEOPLE[id]?.color ?: 0xFF6B7A8F

/** The letter in the round avatar. */
fun initialOf(id: String): String = displayName(id).firstOrNull()?.uppercase() ?: "?"

/** The people who send gifts to the signed-in demo user (everyone but ava). */
val SENDERS: List<String> = listOf("zoe", "caleb", "elise", "mateo", "dana", "ethan", "sofia", "aisha", "daphne", "kai")

/** Which drawing `PixelArt.kt` makes for a post. */
enum class ArtKind { Sunset, City, Ocean, Aurora }

/** One post of the feed. The post id is the `reference` of the gifts sent to it. */
data class Post(val id: String, val author: String, val text: String, val art: ArtKind, val ago: String, val likes: Int)

val POSTS: List<Post> =
    listOf(
        Post(DEMO_POST, DEMO_AUTHOR, "Golden hour on the pier. It never gets old.", ArtKind.Sunset, "2h", 482),
        Post("post_43", "zoe", "New skyline set, three weeks of work. Which window is your favourite?", ArtKind.City, "5h", 1_204),
        Post("post_44", "caleb", "The tide was perfect this morning.", ArtKind.Ocean, "9h", 236),
        Post("post_45", "dana", "Northern lights from the cabin porch. Hot chocolate helped.", ArtKind.Aurora, "1d", 3_071),
    )
