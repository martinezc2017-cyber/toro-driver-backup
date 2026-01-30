package com.example.toro_driver

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // CRITICAL FIX: Force AppCompat theme BEFORE super.onCreate() to eliminate ThemeUtils errors
        // This ensures all Mapbox widgets (compass/logo/attribution) have correct theme context
        setTheme(androidx.appcompat.R.style.Theme_AppCompat_Light_NoActionBar)
        super.onCreate(savedInstanceState)
    }

    // SDK nativo de Mapbox Navigation deshabilitado
    // Usamos REST API de Mapbox Directions (gratuita) en Flutter
}
