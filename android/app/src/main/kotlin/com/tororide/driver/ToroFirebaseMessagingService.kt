package com.tororide.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Native Firebase Messaging Service that handles ALL FCM messages
 * (both foreground and background) with MessagingStyle + TORO logo on LEFT.
 */
class ToroFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        const val CHANNEL_ID = "ride_notifications"
        const val CHANNEL_NAME = "Solicitudes de viaje"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        val title = remoteMessage.notification?.title
            ?: remoteMessage.data["title"]
            ?: "TORO Driver"
        val body = remoteMessage.notification?.body
            ?: remoteMessage.data["body"]
            ?: ""

        showMessagingStyleNotification(title, body)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    private fun showMessagingStyleNotification(title: String, body: String) {
        val ctx: Context = applicationContext
        ensureNotificationChannel(ctx)

        val logoIcon = IconCompat.createWithResource(ctx, R.drawable.toro_notification_logo)

        // "Self" = the driver (phone owner) - not displayed prominently
        val selfPerson = Person.Builder()
            .setName("Me")
            .setKey("self")
            .build()

        // Sender = whoever sent the notification, shows TORO logo on left
        val senderPerson = Person.Builder()
            .setName(title)
            .setKey("toro_system")
            .setIcon(logoIcon)
            .setImportant(true)
            .build()

        val messagingStyle = NotificationCompat.MessagingStyle(selfPerson)
            .addMessage(body, System.currentTimeMillis(), senderPerson)

        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            ctx, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setStyle(messagingStyle)
            .setShortcutId("toro_notifications")
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setColor(0xFF2196F3.toInt())
            .setVibrate(longArrayOf(0, 300, 200, 300))
            .build()

        val notificationId = System.currentTimeMillis().toInt()
        NotificationManagerCompat.from(ctx).notify(notificationId, notification)
    }

    private fun ensureNotificationChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notificaciones de viajes y solicitudes"
                enableVibration(true)
                enableLights(true)
            }
            val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
