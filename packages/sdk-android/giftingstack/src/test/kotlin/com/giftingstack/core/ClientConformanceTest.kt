package com.giftingstack.core

import kotlinx.serialization.json.JsonObject
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** client.json: one scenario = one client call against a scripted transport and token provider. */
@RunWith(Parameterized::class)
class ClientConformanceTest(private val name: String, private val s: JsonObject) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun scenarios() = scenarioParams("client.json")
    }

    @org.junit.Test
    fun scenario() {
        runClientScenario(name, s)
    }
}
