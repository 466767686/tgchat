package com.tgchat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.Surface
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.tgchat.app.MessageStatus
import com.tgchat.app.UiMessage
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.data.MediaDto
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
    mediaUrl: (MediaDto) -> String = { it.url },
    onLongPress: () -> Unit = {},
    onReaction: (String) -> Unit = {},
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
        if (!isOut) Spacer(Modifier.width(0.dp))
        Box(
            modifier = Modifier
                .widthIn(max = 300.dp)
                .drawBehind { drawBubble(bubbleColor, isOut, showTail) }
                .pointerInput(message.key) {
                    detectTapGestures(onLongPress = { onLongPress() })
                }
                .padding(
                    start = if (isOut) 12.dp else 18.dp,
                    end = if (isOut) 18.dp else 12.dp,
                    top = 6.dp,
                    bottom = 5.dp,
                ),
        ) {
            Column {
                message.replyTo?.let { reply ->
                    Row(
                        modifier = Modifier
                            .padding(bottom = 4.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(c.accent.copy(alpha = 0.10f))
                            .padding(horizontal = 6.dp, vertical = 4.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .width(2.dp)
                                .height(30.dp)
                                .background(c.accent),
                        )
                        Spacer(Modifier.width(6.dp))
                        Column {
                            Text(
                                text = reply.senderName,
                                color = c.accent,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                text = reply.text.ifBlank { "消息" },
                                color = c.textSecondary,
                                fontSize = 12.sp,
                                maxLines = 2,
                            )
                        }
                    }
                }

                message.forwardedFrom?.let { from ->
                    Text(
                        text = "转发自 $from",
                        color = c.accent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }

                if (showAuthor) {
                    Text(
                        text = message.senderName,
                        color = parseHexColor(message.senderColor, c.accent),
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(bottom = 2.dp),
                    )
                }
                message.media?.let { media ->
                    val shape = RoundedCornerShape(10.dp)
                    when (media.kind) {
                        "image", "sticker", "gif", "video_note" -> {
                            val width = (media.width ?: 240).coerceIn(120, 280)
                            val height = (media.height ?: 240).coerceIn(120, 280)
                            AsyncImage(
                                model = mediaUrl(media),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .padding(bottom = 4.dp)
                                    .heightIn(max = 260.dp)
                                    .clip(shape),
                            )
                        }
                        else -> {
                            Row(
                                modifier = Modifier
                                    .padding(bottom = 4.dp)
                                    .clip(shape)
                                    .background(Color.Black.copy(alpha = 0.06f))
                                    .padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    Icons.Rounded.Done,
                                    contentDescription = null,
                                    tint = c.accent,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = media.name ?: "文件",
                                    color = textColor,
                                    fontSize = 13.sp,
                                    maxLines = 2,
                                )
                            }
                        }
                    }
                }

                if (message.deleted) {
                    Text(
                        text = "消息已删除",
                        color = c.textTertiary,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Normal,
                    )
                } else if (message.text.isNotBlank()) {
                    Text(
                        text = message.text,
                        color = textColor,
                        fontSize = 16.sp,
                        lineHeight = 21.sp,
                    )
                }

                message.poll?.let { poll ->
                    Column(
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.Black.copy(alpha = 0.05f))
                            .padding(8.dp)
                            .widthIn(max = 260.dp),
                    ) {
                        Text(
                            text = poll.question,
                            color = textColor,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(Modifier.height(4.dp))
                        poll.options.forEach { option ->
                            val selected = poll.myVotes.contains(option.index)
                            Text(
                                text = "${if (selected) "✓ " else ""}${option.text}  ${option.votes}",
                                color = if (selected) c.accent else textColor,
                                fontSize = 13.sp,
                                modifier = Modifier.padding(vertical = 1.dp),
                            )
                        }
                        Text(
                            text = "${poll.totalVotes} 票",
                            color = c.textTertiary,
                            fontSize = 11.sp,
                        )
                    }
                }
                Row(
                    modifier = Modifier
                        .align(Alignment.End)
                        .padding(top = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    message.views?.let { views ->
                        Text(
                            text = "👁 $views",
                            color = c.textTertiary,
                            fontSize = 10.sp,
                        )
                        Spacer(Modifier.width(4.dp))
                    }
                    if (message.editedAt != null) {
                        Text(
                            text = "已编辑",
                            color = c.textTertiary,
                            fontSize = 10.sp,
                        )
                        Spacer(Modifier.width(4.dp))
                    }
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
fun ReactionsRow(reactions: List<com.tgchat.app.data.ReactionDto>, onReact: (String) -> Unit) {
    if (reactions.isEmpty()) return
    val c = LocalTgColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp)) {
        reactions.forEach { reaction ->
            Surface(
                shape = RoundedCornerShape(10.dp),
                color = if (reaction.me) c.accent.copy(alpha = 0.20f) else c.surfaceAlt,
                modifier = Modifier.clickable { onReact(reaction.emoji) },
            ) {
                Text(
                    text = "${reaction.emoji} ${reaction.count}",
                    fontSize = 11.sp,
                    color = c.textPrimary,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                )
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
