package com.giftingstack.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The away card shows the first time after install only (kept in SharedPreferences).
        val awayOnce = AwayOnce(PrefsAwayStore(applicationContext))
        setContent { PixelApp(awayOnce) }
    }
}
