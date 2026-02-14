package com.tororide.driver

import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import androidx.core.content.LocusIdCompat
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.tororide.driver/notifications"
    private val SPLASH_CHANNEL = "com.tororide.driver/splash"
    private lateinit var notificationHelper: ToroNotificationHelper
    private var splashOverlay: View? = null
    private val startTime = System.currentTimeMillis()

    private fun log(msg: String) {
        val elapsed = System.currentTimeMillis() - startTime
        Log.i("TORO_SPLASH", "[${elapsed}ms] $msg")
    }

    // TextureView + TRANSPARENT: the TextureView is see-through until Flutter
    // renders its first frame. The windowBackground (launch_background with TORO
    // branding) is visible through the transparent TextureView during Impeller init.
    // No overlay needed — the window background does the job.
    override fun createFlutterFragment(): FlutterFragment {
        log("createFlutterFragment: texture + transparent (windowBg visible)")

        val builder = FlutterFragment.withNewEngine()
            .dartEntrypoint(getDartEntrypointFunctionName())
            .initialRoute(getInitialRoute())
            .appBundlePath(getAppBundlePath())
            .flutterShellArgs(FlutterShellArgs.fromIntent(getIntent()))
            .handleDeeplinking(shouldHandleDeeplinking())
            .renderMode(RenderMode.texture)
            .transparencyMode(TransparencyMode.transparent)
            .shouldAttachEngineToActivity(shouldAttachEngineToActivity())
            .shouldDelayFirstAndroidViewDraw(false)
            .shouldAutomaticallyHandleOnBackPressed(true)

        getDartEntrypointLibraryUri()?.let { builder.dartLibraryUri(it) }
        getDartEntrypointArgs()?.let { builder.dartEntrypointArgs(it) }

        return builder.build()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        log("onCreate START")

        // Keep Android 12+ splash screen visible for 3 seconds so Flutter has
        // time to initialize. When the splash dismisses, particles are already running.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val content: View = findViewById(android.R.id.content)
            content.viewTreeObserver.addOnPreDrawListener(
                object : ViewTreeObserver.OnPreDrawListener {
                    override fun onPreDraw(): Boolean {
                        return if (System.currentTimeMillis() - startTime >= 3000) {
                            content.viewTreeObserver.removeOnPreDrawListener(this)
                            log("Android 12 splash released after 3s")
                            true
                        } else {
                            false // Keep splash visible
                        }
                    }
                }
            )
            log("Android 12 splash held for 3s")
        }

        super.onCreate(savedInstanceState)
        log("super.onCreate DONE")
        notificationHelper = ToroNotificationHelper(this)
        registerToroConversationShortcut()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        log("configureFlutterEngine")

        // Platform channel for custom TORO notifications
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                    val title = call.argument<String>("title") ?: "TORO Driver"
                    val body = call.argument<String>("body") ?: ""
                    notificationHelper.showNotification(id, title, body)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Splash channel — kept for compatibility. No overlay to remove;
        // the window background (launch_background) shows through Flutter's
        // transparent Scaffold during the splash animation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPLASH_CHANNEL)
            .setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    log("Flutter ready (no overlay to remove)")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerToroConversationShortcut() {
        try {
            val toroPerson = Person.Builder()
                .setName("TORO Driver")
                .setIcon(IconCompat.createWithResource(this, R.drawable.toro_notification_logo))
                .setImportant(true)
                .build()

            val shortcut = ShortcutInfoCompat.Builder(this, "toro_notifications")
                .setLocusId(LocusIdCompat("toro_notifications"))
                .setShortLabel("TORO Driver")
                .setLongLabel("TORO Driver Notifications")
                .setIcon(IconCompat.createWithResource(this, R.drawable.toro_notification_logo))
                .setIntent(Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                })
                .setPerson(toroPerson)
                .setLongLived(true)
                .setIsConversation()
                .build()

            ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
