package com.tororide.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * WhatsApp-style notification: full-color TORO logo as the Person avatar
 * on the LEFT circle. Uses MessagingStyle + conversation shortcut so
 * Android 12+ renders the avatar instead of the monochrome small icon.
 */
class ToroNotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "toro_custom_notifications"
        const val CHANNEL_NAME = "TORO Notificaciones"
        const val SHORTCUT_ID = "toro_notifications"
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notificaciones de TORO Driver"
                enableVibration(true)
                enableLights(true)
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    fun showNotification(
        notificationId: Int,
        title: String,
        body: String,
    ) {
        // Load TORO logo as bitmap for the Person avatar
        val logoBitmap = BitmapFactory.decodeResource(context.resources, R.drawable.toro_notification_logo)
        val personIcon = IconCompat.createWithBitmap(logoBitmap)

        // Create Person with TORO logo as avatar
        val person = Person.Builder()
            .setName(title)
            .setIcon(personIcon)
            .setKey(SHORTCUT_ID)
            .build()

        // Create conversation shortcut (required for avatar to show on Android 12+)
        val shortcut = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel("TORO Driver")
            .setLongLived(true)
            .setPerson(person)
            .setIntent(Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
            })
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)

        // MessagingStyle — same approach as WhatsApp
        val messagingStyle = NotificationCompat.MessagingStyle(person)
            .addMessage(body, System.currentTimeMillis(), person)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(Color.parseColor("#0D0D1A"))
            .setStyle(messagingStyle)
            .setShortcutId(SHORTCUT_ID)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 300, 200, 300))
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }
}
