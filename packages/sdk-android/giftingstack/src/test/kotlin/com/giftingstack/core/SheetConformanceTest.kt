package com.giftingstack.core

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

private val sheetFile = Fixtures.conformance("sheet.json")

private fun num(o: JsonObject, key: String): Double? {
    val v = o[key] ?: return null
    return if (v is JsonNull) null else v.jsonPrimitive.double
}

/** A fixture layout: missing keys are "not given". */
fun sheetLayout(o: JsonObject): SheetLayout {
    val s = o["snaps"]?.jsonObject
    return SheetLayout(
        containerHeight = num(o, "containerHeight") ?: 0.0,
        snaps = SheetSnapFractions(s?.let { num(it, "peek") }, s?.let { num(it, "default") }, s?.let { num(it, "expanded") }),
        peekMinHeight = num(o, "peekMinHeight") ?: 0.0,
        defaultMinHeight = num(o, "defaultMinHeight") ?: 0.0,
        contentHeight = num(o, "contentHeight") ?: 0.0,
    )
}

private fun expectHeights(label: String, expect: JsonObject, got: SheetHeights) {
    assertEquals("$label.peek", expect.getValue("peek").jsonPrimitive.double, got.peek, 0.0)
    assertEquals("$label.default", expect.getValue("default").jsonPrimitive.double, got.default, 0.0)
    assertEquals("$label.expanded", expect.getValue("expanded").jsonPrimitive.double, got.expanded, 0.0)
}

/** sheet.json "heights": resolveSheetHeights. */
@RunWith(Parameterized::class)
class SheetHeightsConformanceTest(private val name: String, private val case: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases() = scenarioParams("sheet.json", "heights")
    }

    @org.junit.Test
    fun heights() {
        val got = resolveSheetHeights(sheetLayout(case.getValue("layout").jsonObject))
        expectHeights(name, case.getValue("expect").jsonObject, got)
    }
}

/** sheet.json "scenarios": the TraySheetController. */
@RunWith(Parameterized::class)
class SheetConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = scenarioParams("sheet.json")

        private fun layoutOf(ref: kotlinx.serialization.json.JsonElement): SheetLayout =
            if (ref is JsonPrimitive) sheetLayout(sheetFile.getValue("layouts").jsonObject.getValue(ref.content).jsonObject)
            else sheetLayout(ref.jsonObject)
    }

    @org.junit.Test
    fun scenario() {
        val changes = ArrayList<String>()
        val c =
            TraySheetController(
                initialSnap = s.stringOrNull("initialSnap")?.let { SheetSnap.fromWire(it) } ?: SheetSnap.Default,
                layout = layoutOf(s.getValue("layout")),
                onSnapChange = { changes.add(it.wire) },
            )
        s.getValue("steps").arr().forEachIndexed { i, st ->
            val step = st.obj()
            val at = "$name: step ${i + 1}"
            fun returns(got: String) {
                if (step.has("returns")) assertEquals("$at returns", step.string("returns"), got)
            }
            when {
                step.has("dragStart") -> c.dragStart()
                step.has("drag") -> c.drag(step.getValue("drag").jsonPrimitive.double)
                step.has("release") -> returns(c.release(step.getValue("release").jsonPrimitive.double).wire)
                step.has("cancel") -> c.cancel()
                step.has("snapTo") -> c.snapTo(SheetSnap.fromWire(step.string("snapTo")))
                step.has("toggle") -> returns(c.toggle().wire)
                step.has("step") -> returns(c.step(step.getValue("step").jsonPrimitive.int).wire)
                step.has("layout") -> c.setLayout(layoutOf(step.getValue("layout")))
                step.has("scrollOwner") -> {
                    val so = step.getValue("scrollOwner").obj()
                    val owner = c.scrollOwner(so.getValue("dy").jsonPrimitive.double, so.getValue("gridScrollTop").jsonPrimitive.double)
                    returns(if (owner == ScrollOwner.Sheet) "sheet" else "grid")
                }
                step.has("expect") -> {
                    val e = step.getValue("expect").obj()
                    val st2 = c.getState()
                    e.stringOrNull("snap")?.let { assertEquals("$at snap", it, st2.snap.wire) }
                    num(e, "offset")?.let { assertEquals("$at offset", it, st2.offset, 0.0) }
                    num(e, "visibleHeight")?.let { assertEquals("$at visibleHeight", it, st2.visibleHeight, 0.0) }
                    if (e.has("dragging")) assertEquals("$at dragging", e.bool("dragging"), st2.dragging)
                    if (e.has("gridScrollable")) assertEquals("$at gridScrollable", e.bool("gridScrollable"), st2.gridScrollable)
                    if (e.has("heights")) expectHeights("$at heights", e.getValue("heights").obj(), st2.heights)
                    if (e.has("snapChanges")) {
                        assertEquals("$at snapChanges", e.getValue("snapChanges").arr().map { it.jsonPrimitive.content }, changes)
                    }
                }
                else -> error("$at: unknown step $step")
            }
        }
    }
}
