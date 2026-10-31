package com.tgchat.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.UiMessage
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.ChatBackground
import com.tgchat.app.ui.components.DateChip
import com.tgchat.app.ui.components.MessageBubble
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue
import com.tgchat.app.util.formatDateHeader
import com.tgchat.app.util.formatLastSeen
import com.tgchat.app.util.isSameDay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

private val EMOJIS = listOf(
    "😀", "😂", "🥰", "😎", "😭", "🤔", "👍", "👏", "🙏", "🔥",
    "❤️", "🎉", "☕️", "🌙", "⭐️", "🚀", "🐱", "🍀", "💯", "✅",
)

@Composable
fun ChatScreen(vm: AppViewModel, chatId: String) {
    val c = LocalTgColors.current
    val chat = vm.chats.firstOrNull { it.id == chatId }
    val messages = vm.activeMessages
    val reversed = remember(messages) { messages.asReversed() }
    val listState = rememberLazyListState()
    val scrollScope = rememberCoroutineScope()

    val peer = chat?.members?.firstOrNull { it.id != vm.me?.id }
    val subtitle = when {
        vm.typingUser != null -> "正在输入…"
        chat == null -> ""
        chat.isGroup -> "${chat.members.size} 位成员"
        else -> formatLastSeen(peer?.lastSeenAt)
    }

    Column(modifier = Modifier.fillMaxSize().background(c.background)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(c.headerBg)
                .statusBarsPadding()
                .height(56.dp)
                .padding(horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { vm.back() }) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = c.icon)
            }
            Avatar(
                name = chat?.title ?: "?",
                colorHex = chat?.avatarColor ?: "#3390EC",
                size = 38.dp,
            )
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = chat?.title ?: "会话",
                    color = c.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
                Text(
                    text = subtitle,
                    color = if (vm.typingUser != null) c.accent else c.textSecondary,
                    fontSize = 12.sp,
                    maxLines = 1,
                )
            }
            Spacer(Modifier.width(8.dp))
        }

        Box(modifier = Modifier.weight(1f)) {
            ChatBackground(modifier = Modifier.fillMaxSize())

            when {
                vm.chatLoading && messages.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = TelegramBlue, strokeWidth = 2.5.dp)
                    }
                }
                messages.isEmpty() -> {
                    Column(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = "这里还没有消息",
                            color = c.textPrimary.copy(alpha = 0.7f),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = "发送第一条消息，开始对话",
                            color = c.textSecondary,
                            fontSize = 13.sp,
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        state = listState,
                        reverseLayout = true,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 8.dp),
                    ) {
                        itemsIndexed(reversed, key = { _, item -> item.key }) { index, message ->
                            val older = reversed.getOrNull(index + 1)
                            val newer = reversed.getOrNull(index - 1)
                            val dateChanged = older == null || !isSameDay(older.createdAt, message.createdAt)
                            val isOut = message.senderId == vm.me?.id
                            val showAuthor = !isOut && chat?.isGroup == true &&
                                (dateChanged || newer == null || newer.senderId != message.senderId)
                            val showTail = newer == null || newer.senderId != message.senderId ||
                                !isSameDay(newer.createdAt, message.createdAt)
                            val readByPeer = isOut && message.seq > 0 && (chat?.otherReadSeq ?: 0) >= message.seq

                            Column {
                                if (dateChanged) DateChip(formatDateHeader(message.createdAt))
                                MessageBubble(
                                    message = message,
                                    isOut = isOut,
                                    showAuthor = showAuthor,
                                    showTail = showTail,
                                    readByPeer = readByPeer,
                                    onRetry = { message.clientId?.let(vm::retrySend) },
                                )
                            }
                        }

                        if (vm.hasMore[chatId] != false) {
                            item(key = "load-more") {
                                Box(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (vm.loadingOlder) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(20.dp),
                                            color = TelegramBlue,
                                            strokeWidth = 2.dp,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if (listState.firstVisibleItemIndex > 6) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(14.dp)
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(c.surface)
                                .clickable {
                                    scrollScope.launch { listState.animateScrollToItem(0) }
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Rounded.ExpandMore,
                                contentDescription = null,
                                tint = c.icon,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                }
            }
        }

        Composer(
            onSend = { vm.sendMessage(it) },
            onTyping = { vm.onComposerTyping(it) },
        )
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty() && listState.firstVisibleItemIndex <= 1) {
            listState.animateScrollToItem(0)
        }
    }

    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1 }
            .distinctUntilChanged()
            .collect { last ->
                if (last >= vm.activeMessages.size - 2 && vm.activeMessages.isNotEmpty()) {
                    vm.loadOlder()
                }
            }
    }
}

@Composable
private fun Composer(onSend: (String) -> Unit, onTyping: (String) -> Unit) {
    val c = LocalTgColors.current
    var text by remember { mutableStateOf("") }
    var emojiOpen by remember { mutableStateOf(false) }

    Column(modifier = Modifier.background(c.headerBg)) {
        if (emojiOpen) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                for (emoji in EMOJIS) {
                    Text(
                        text = emoji,
                        fontSize = 24.sp,
                        modifier = Modifier
                            .padding(horizontal = 6.dp)
                            .clickable { text += emoji },
                    )
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            IconButton(onClick = { emojiOpen = !emojiOpen }) {
                Icon(
                    Icons.Outlined.EmojiEmotions,
                    contentDescription = "表情",
                    tint = c.icon,
                )
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(20.dp))
                    .background(c.surfaceAlt)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                if (text.isEmpty()) {
                    Text("Message", color = c.textTertiary, fontSize = 16.sp)
                }
                BasicTextField(
                    value = text,
                    onValueChange = {
                        text = it
                        onTyping(it)
                    },
                    textStyle = TextStyle(color = c.textPrimary, fontSize = 16.sp, lineHeight = 21.sp),
                    cursorBrush = SolidColor(TelegramBlue),
                    maxLines = 5,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.width(8.dp))

            val enabled = text.isNotBlank()
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(if (enabled) TelegramBlue else c.surfaceAlt)
                    .clickable(enabled = enabled) {
                        onSend(text)
                        text = ""
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Send,
                    contentDescription = "发送",
                    tint = if (enabled) Color.White else c.textTertiary,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
}
