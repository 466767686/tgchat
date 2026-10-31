package com.tgchat.app.util

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private val timeFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
private val dayFmt = SimpleDateFormat("yyyy年M月d日", Locale.getDefault())
private val shortDateFmt = SimpleDateFormat("M月d日", Locale.getDefault())
private val listDateFmt = SimpleDateFormat("dd.MM.yy", Locale.getDefault())

private fun startOfDay(millis: Long): Long {
    val cal = Calendar.getInstance()
    cal.timeInMillis = millis
    cal.set(Calendar.HOUR_OF_DAY, 0)
    cal.set(Calendar.MINUTE, 0)
    cal.set(Calendar.SECOND, 0)
    cal.set(Calendar.MILLISECOND, 0)
    return cal.timeInMillis
}

fun formatMessageTime(millis: Long): String = timeFmt.format(Date(millis))

/** Time shown on the right of a chat-list row. */
fun formatChatListTime(millis: Long): String {
    if (millis <= 0) return ""
    val today = startOfDay(System.currentTimeMillis())
    val target = startOfDay(millis)
    return when {
        target == today -> timeFmt.format(Date(millis))
        today - target == 86_400_000L -> "昨天"
        today - target < 6 * 86_400_000L -> SimpleDateFormat("EEE", Locale.getDefault()).format(Date(millis))
        else -> listDateFmt.format(Date(millis))
    }
}

/** Header chip inside the conversation. */
fun formatDateHeader(millis: Long): String {
    val today = startOfDay(System.currentTimeMillis())
    val target = startOfDay(millis)
    return when {
        target == today -> "今天"
        today - target == 86_400_000L -> "昨天"
        today - target < 365L * 86_400_000L -> shortDateFmt.format(Date(millis))
        else -> dayFmt.format(Date(millis))
    }
}

fun isSameDay(a: Long, b: Long): Boolean = startOfDay(a) == startOfDay(b)

fun formatLastSeen(millis: Long?): String {
    if (millis == null || millis <= 0) return "最近在线"
    val diff = System.currentTimeMillis() - millis
    return when {
        diff < 60_000 -> "在线"
        diff < 3_600_000 -> "最后在线 ${diff / 60_000} 分钟前"
        diff < 86_400_000 -> "最后在线 ${diff / 3_600_000} 小时前"
        else -> "最后在线 " + shortDateFmt.format(Date(millis))
    }
}
