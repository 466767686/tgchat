package com.tgchat.app.push

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.tgchat.app.MainActivity
import com.tgchat.app.R
import com.tgchat.app.data.MessageDto

object Notifications {
    const val CHANNEL_MESSAGES = "tgchat_messages"
    const val CHANNEL_SERVICE = "tgchat_service"
    private const val SERVICE_ID = 1

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MESSAGES, "应用通知", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "新消息提醒"
                enableVibration(true)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SERVICE, "后台运行", NotificationManager.IMPORTANCE_MIN).apply {
                description = "保持后台运行"
                setShowBadge(false)
            },
        )
    }

    fun serviceNotification(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("计算器")
            .setContentText("保持后台运行")
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
