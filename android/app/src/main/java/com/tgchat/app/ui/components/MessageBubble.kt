package com.tgchat.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.MessageStatus
import com.tgchat.app.UiMessage
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.parseHexColor
import com.tgchat.app.util.formatMessageTime

private fun DrawScope.drawBubble(color: Color, isOut: Boolean, withTail: Boolean) {
    val radius = 16.dp.toPx()
    val tail = 9.dp.toPx()
    val left = if (isOut) 0f else tail
    val right = if (isOut) size.width - tail else size.width
    val path = Path()
    path.addRoundRect(RoundRect(left, 0f, right, size.height, CornerRadius(radius)))
    if (withTail) {
        val baseY = size.height - 11.dp.toPx()
        if (isOut) {
            path.moveTo(right - 1f, baseY)
            path.lineTo(right + tail, size.height)
            path.lineTo(right - 1f, size.height)
        } else {
            path.moveTo(left + 1f, baseY)
            path.lineTo(left - tail, size.height)
            path.lineTo(left + 1f, size.height)
        }
        path.close()
    }
    drawPath(path, color)
}

@Composable
fun MessageBubble(
    message: UiMessage,
    isOut: Boolean,
    showAuthor: Boolean,
    showTail: Boolean,
    readByPeer: Boolean,
    onRetry: () -> Unit,
) {
    val c = LocalTgColors.current
    val bubbleColor = if (isOut) c.bubbleOut else c.bubbleIn
    val textColor = if (isOut) c.bubbleOutText else c.bubbleInText

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 1.5.dp),
        horizontalArrangement = if (isOut) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 300.dp)
                .drawBehind { drawBubble(bubbleColor, isOut, showTail) }
                .padding(
                    start = if (isOut) 12.dp else 18.dp,
                    end = if (isOut) 18.dp else 12.dp,
                    top = 6.dp,
                    bottom = 5.dp,
                ),
        ) {
            Column {
                if (showAuthor) {
                    Text(
                        text = message.senderName,
                        color = parseHexColor(message.senderColor, c.accent),
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
                Text(
                    text = message.text,
                    color = textColor,
                    fontSize = 16.sp,
                    lineHeight = 21.sp,
                )
                Row(
                    modifier = Modifier
                        .align(Alignment.End)
                        .padding(top = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = formatMessageTime(message.createdAt),
                        color = if (isOut) c.textSecondary.copy(alpha = 0.85f) else c.textTertiary,
                        fontSize = 11.sp,
                    )
                    if (isOut) {
                        Spacer(Modifier.width(3.dp))
                        Box(
                            modifier = Modifier.clickable(enabled = message.status == MessageStatus.FAILED) { onRetry() },
                        ) {
                            when (message.status) {
                                MessageStatus.SENDING -> Icon(
                                    Icons.Rounded.Schedule,
                                    contentDescription = null,
                                    tint = c.textTertiary,
                                    modifier = Modifier.size(12.dp),
                                )
                                MessageStatus.FAILED -> Icon(
                                    Icons.Rounded.ErrorOutline,
                                    contentDescription = "重发",
                                    tint = c.danger,
                                    modifier = Modifier.size(14.dp),
                                )
                                MessageStatus.SENT -> Icon(
                                    if (readByPeer) Icons.Rounded.DoneAll else Icons.Rounded.Done,
                                    contentDescription = null,
                                    tint = if (readByPeer) c.accent else c.textTertiary,
                                    modifier = Modifier.size(14.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun DateChip(label: String) {
    val c = LocalTgColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.Center,
    ) {
        Text(
            text = label,
            color = Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier
                .clip(CircleShape)
                .drawBehind { drawRoundRect(c.dateChipBg, cornerRadius = CornerRadius(size.height / 2f)) }
                .padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}
