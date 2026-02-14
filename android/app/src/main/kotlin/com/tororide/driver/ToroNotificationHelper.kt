package com.tororide.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Custom notification with full-color TORO logo on the LEFT.
 * Uses DecoratedCustomViewStyle + RemoteViews for complete control.
 */
class ToroNotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "toro_custom_notifications"
        const val CHANNEL_NAME = "TORO Notificaciones"
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
        // Custom layout with TORO logo on the LEFT
        val customView = RemoteViews(context.packageName, R.layout.notification_toro).apply {
            setTextViewText(R.id.notification_title, title)
            setTextViewText(R.id.notification_body, body)
            setImageViewResource(R.id.notification_logo, R.drawable.toro_notification_logo)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setCustomContentView(customView)
            .setCustomBigContentView(customView)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 300, 200, 300))
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }
}
