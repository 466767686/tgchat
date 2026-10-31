package com.tgchat.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.tgchat.app.ui.theme.LocalTgColors

/**
 * Telegram-like conversation wallpaper: a soft vertical gradient with a faint
 * repeating pattern, drawn once per size change by Compose's canvas.
 */
@Composable
fun ChatBackground(modifier: Modifier = Modifier) {
    val c = LocalTgColors.current
    val patternColor = if (c.isDark) Color.White.copy(alpha = 0.028f) else Color(0xFF2E5A88).copy(alpha = 0.045f)
    val accentPattern = if (c.isDark) Color.White.copy(alpha = 0.035f) else Color(0xFF2E5A88).copy(alpha = 0.055f)

    Canvas(modifier.fillMaxSize()) {
        drawRect(Brush.verticalGradient(listOf(c.chatBgTop, c.chatBgBottom)))

        val step = 72.dp.toPx()
        val dot = 2.2.dp.toPx()
        val ring = 5.5.dp.toPx()

        var row = 0
        var y = step / 2f
        while (y < size.height + step) {
            var x = if (row % 2 == 0) step / 2f else step
            while (x < size.width + step) {
                drawCircle(color = patternColor, radius = dot, center = Offset(x, y))
                if ((row + (x / step).toInt()) % 3 == 0) {
                    drawCircle(
                        color = accentPattern,
                        radius = ring,
                        center = Offset(x + step / 2f, y + step / 3f),
                        style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.2.dp.toPx()),
                    )
                }
                x += step
            }
            y += step
            row++
        }
    }
}
