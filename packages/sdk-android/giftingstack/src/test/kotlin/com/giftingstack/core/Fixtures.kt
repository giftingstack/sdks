package com.giftingstack.core

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Reads the shared fixtures from packages/sdk-spec. Fails loudly when they are missing. */
object Fixtures {
    val specDir: File by lazy {
        val prop = System.getProperty("giftingstack.spec.dir")
        val dir = File(prop ?: "../sdk-spec")
        check(dir.isDirectory && File(dir, "recipes.json").isFile) {
            "sdk-spec folder not found at ${dir.absolutePath}. The conformance fixtures are " +
                "required; run the tests from the Gradle project inside packages/sdk-android."
        }
        dir
    }

    fun read(relative: String): JsonObject {
        val f = File(specDir, relative)
        check(f.isFile) { "Fixture missing: ${f.absolutePath}" }
        return Json.parseToJsonElement(f.readText(Charsets.UTF_8)).jsonObject
    }

    fun conformance(name: String): JsonObject = read("conformance/$name")
}

fun JsonElement.obj(): JsonObject = jsonObject

fun JsonElement.arr(): JsonArray = jsonArray

fun JsonObject.string(key: String): String = getValue(key).jsonPrimitive.content

fun JsonObject.stringOrNull(key: String): String? {
    val v = this[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.contentOrNull
}

fun JsonObject.intOrNull(key: String): Int? {
    val v = this[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.int
}

fun JsonObject.bool(key: String): Boolean = getValue(key).jsonPrimitive.boolean

fun JsonObject.has(key: String) = containsKey(key)

fun scenarioParams(file: String, key: String = "scenarios"): List<Array<Any>> =
    Fixtures.conformance(file).getValue(key).jsonArray.map {
        arrayOf(it.jsonObject.string("name"), it)
    }

fun prim(v: Any?): JsonElement =
    when (v) {
        null -> JsonNull
        is Int -> JsonPrimitive(v)
        is Boolean -> JsonPrimitive(v)
        is String -> JsonPrimitive(v)
        else -> error("prim: $v")
    }
