package com.tgchat.app.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

data class TgColors(
    val isDark: Boolean,
    val accent: Color,
    val accentSoft: Color,
    val background: Color,
    val surface: Color,
    val surfaceAlt: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val divider: Color,
    val bubbleIn: Color,
    val bubbleOut: Color,
    val bubbleInText: Color,
    val bubbleOutText: Color,
    val chatBgTop: Color,
    val chatBgBottom: Color,
    val headerBg: Color,
    val statusOnline: Color,
    val unreadBadge: Color,
    val inputBg: Color,
    val danger: Color,
    val dateChipBg: Color,
    val icon: Color,
)

val TelegramBlue = Color(0xFF3390EC)

val LightTgColors = TgColors(
    isDark = false,
    accent = TelegramBlue,
    accentSoft = Color(0xFFE7F1FD),
    background = Color(0xFFFFFFFF),
    surface = Color(0xFFFFFFFF),
    surfaceAlt = Color(0xFFF1F3F6),
    textPrimary = Color(0xFF0F1419),
    textSecondary = Color(0xFF707579),
    textTertiary = Color(0xFF8E9299),
    divider = Color(0xFFE9EBEE),
    bubbleIn = Color(0xFFFFFFFF),
    bubbleOut = Color(0xFFEFFDDE),
    bubbleInText = Color(0xFF0F1419),
    bubbleOutText = Color(0xFF0F1419),
    chatBgTop = Color(0xFFD7E3EE),
    chatBgBottom = Color(0xFFEDF2F7),
    headerBg = Color(0xFFFFFFFF),
    statusOnline = TelegramBlue,
    unreadBadge = TelegramBlue,
    inputBg = Color(0xFFFFFFFF),
    danger = Color(0xFFE0493E),
    dateChipBg = Color(0x59000000),
    icon = Color(0xFF707579),
)

val DarkTgColors = TgColors(
    isDark = true,
    accent = Color(0xFF6AB3F3),
    accentSoft = Color(0xFF1D3448),
    background = Color(0xFF0E1621),
    surface = Color(0xFF17212B),
    surfaceAlt = Color(0xFF232E3C),
    textPrimary = Color(0xFFF5F7FA),
    textSecondary = Color(0xFF8A9AA8),
    textTertiary = Color(0xFF6D7F8E),
    divider = Color(0xFF1C2733),
    bubbleIn = Color(0xFF182533),
    bubbleOut = Color(0xFF2B5278),
    bubbleInText = Color(0xFFF2F5F8),
    bubbleOutText = Color(0xFFFFFFFF),
    chatBgTop = Color(0xFF0B131C),
    chatBgBottom = Color(0xFF15212D),
    headerBg = Color(0xFF17212B),
    statusOnline = Color(0xFF6AB3F3),
    unreadBadge = Color(0xFF3390EC),
    inputBg = Color(0xFF17212B),
    danger = Color(0xFFFF6B6B),
    dateChipBg = Color(0x66000000),
    icon = Color(0xFF8A9AA8),
)

val LocalTgColors = staticCompositionLocalOf { LightTgColors }

/** Deterministic avatar palette, mirrored from the backend defaults. */
val AvatarPalette = listOf(
    "#3390EC", "#E17076", "#7BC862", "#E5CA77",
    "#A695E7", "#EE7AAE", "#6EC9CB", "#FAA774",
)

fun avatarColorFor(seed: String): Color {
    var hash = 0
    for (ch in seed) hash = hash * 31 + ch.code
    val idx = (hash and 0x7FFFFFFF) % AvatarPalette.size
    return parseHexColor(AvatarPalette[idx])
}

fun parseHexColor(hex: String, fallback: Color = TelegramBlue): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (_: Exception) {
    fallback
}
