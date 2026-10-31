package com.tgchat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.parseHexColor

private fun initialsOf(name: String): String {
    val trimmed = name.trim()
    if (trimmed.isEmpty()) return "?"
    val parts = trimmed.split(" ", "　").filter { it.isNotBlank() }
    return if (parts.size >= 2) {
        (parts[0].take(1) + parts[1].take(1)).uppercase()
    } else {
        trimmed.take(1).uppercase()
    }
}

@Composable
fun Avatar(
    name: String,
    colorHex: String,
    size: Dp = 54.dp,
    modifier: Modifier = Modifier,
    online: Boolean = false,
) {
    val c = LocalTgColors.current
    val base = parseHexColor(colorHex)
    val brush = Brush.linearGradient(listOf(lerp(base, Color.White, 0.22f), base))
    Box(modifier = modifier.size(size)) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .background(brush),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = initialsOf(name),
                color = Color.White,
                fontSize = (size.value * 0.36f).sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (online) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 1.dp, y = 1.dp)
                    .size(size * 0.26f)
                    .clip(CircleShape)
                    .background(Color(0xFF4CD964))
                    .border(2.dp, c.surface, CircleShape),
            )
        }
    }
}
