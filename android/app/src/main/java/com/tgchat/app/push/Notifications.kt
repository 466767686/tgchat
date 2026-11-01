package com.tgchat.app.push

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.tgchat.app.MainActivity
import com.tgchat.app.R
import com.tgchat.app.data.MessageDto

object Notifications {
    const val CHANNEL_MESSAGES = "yuejian_messages_v2"
    const val CHANNEL_SERVICE = "tgchat_service"
    private const val SERVICE_ID = 1

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val ding = Uri.parse(
            "android.resource://" + context.packageName + "/" + R.raw.message_ding,
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MESSAGES, "消息提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "新消息横幅与提示音"
                enableVibration(true)
                setSound(
                    ding,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SERVICE, "便笺同步", NotificationManager.IMPORTANCE_MIN).apply {
                description = "同步便笺内容"
                setShowBadge(false)
            },
        )
    }

    fun serviceNotification(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("月见便笺")
            .setContentText("正在同步便笺")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    fun serviceId(): Int = SERVICE_ID

    fun showMessage(context: Context, message: MessageDto) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannels(context)

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chatId", message.chatId)
        }
        val pending = PendingIntent.getActivity(
            context,
            message.chatId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val text = message.text.replace("\n", " ")
        val notification = NotificationCompat.Builder(context, CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(message.senderName.ifBlank { "新消息" })
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setGroup(message.chatId)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(pending)
            .build()

        runCatching {
            NotificationManagerCompat.from(context).notify(message.chatId.hashCode(), notification)
        }
    }
}

/** Set from MainActivity so the service can avoid notifying while the app is open. */
object AppVisibility {
    @Volatile
    var visible: Boolean = false
}
