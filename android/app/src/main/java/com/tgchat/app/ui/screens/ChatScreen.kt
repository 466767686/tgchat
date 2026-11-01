package com.tgchat.app.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.rounded.AttachFile
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.UiMessage
import com.tgchat.app.ui.LocalReduceMotion
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.ChatBackground
import com.tgchat.app.ui.components.DateChip
import com.tgchat.app.ui.components.MessageBubble
import com.tgchat.app.ui.components.ReactionsRow
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

private val QUICK_REACTIONS = listOf("👍", "❤️", "😂", "😮", "😢", "🔥")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(vm: AppViewModel, chatId: String) {
    val c = LocalTgColors.current
    val reduceMotion = LocalReduceMotion.current
    val clipboard = LocalClipboardManager.current
    val chat = vm.chats.firstOrNull { it.id == chatId }
    val messages = vm.activeMessages
    val reversed = remember(messages) { messages.asReversed() }
    val listState = rememberLazyListState()
    val scrollScope = rememberCoroutineScope()

    var replyTo by remember { mutableStateOf<UiMessage?>(null) }
    var editing by remember { mutableStateOf<UiMessage?>(null) }
    var sheetMessage by remember { mutableStateOf<UiMessage?>(null) }
    var draft by remember { mutableStateOf("") }
    var attachOpen by remember { mutableStateOf(false) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { vm.sendMedia(it, "image") }
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { vm.sendMedia(it, "file") }
    }

    val peer = chat?.members?.firstOrNull { it.id != vm.me?.id }
    val subtitle = when {
        vm.typingUser != null -> "正在输入…"
        chat == null -> ""
        chat.isGroup -> "${chat.members.size} 位成员"
        else -> formatLastSeen(peer?.lastSeenAt)
    }

    fun performSend() {
        val content = draft.trim()
        if (content.isEmpty()) return
        val editingNow = editing
        if (editingNow != null) {
            vm.editMessage(editingNow.seq, content)
            editing = null
        } else {
            vm.sendMessage(content, replyTo?.seq)
            replyTo = null
        }
        draft = ""
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
                                    mediaUrl = { media -> vm.api.mediaUrl(media) },
                                    onLongPress = {
                                        if (message.seq > 0) sheetMessage = message
                                    },
                                    onReaction = { emoji -> vm.toggleReaction(message.seq, emoji) },
                                )
                                if (!isOut || message.reactions.isNotEmpty()) {
                                    ReactionsRow(
                                        reactions = message.reactions,
                                        onReact = { emoji -> vm.toggleReaction(message.seq, emoji) },
                                    )
                                }
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
                                    scrollScope.launch {
                                        if (reduceMotion) listState.scrollToItem(0)
                                        else listState.animateScrollToItem(0)
                                    }
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
            value = draft,
            onValueChange = {
                draft = it
                vm.onComposerTyping(it)
            },
            replyTo = replyTo,
            editing = editing,
            onCancelReply = { replyTo = null },
            onCancelEdit = {
                editing = null
                draft = ""
            },
            onAttach = { attachOpen = true },
            onEmoji = { draft += it },
            onSend = { performSend() },
        )
    }

    if (attachOpen) {
        AttachDialog(
            onDismiss = { attachOpen = false },
            onPhoto = {
                attachOpen = false
                imagePicker.launch("image/*")
            },
            onFile = {
                attachOpen = false
                filePicker.launch("*/*")
            },
        )
    }

    sheetMessage?.let { message ->
        val isMine = message.senderId == vm.me?.id
        val canManage = chat?.canManage == true
        val sheetState = rememberModalBottomSheetState()
        ModalBottomSheet(
            onDismissRequest = { sheetMessage = null },
            sheetState = sheetState,
            containerColor = c.headerBg,
        ) {
            MessageActions(
                message = message,
                isMine = isMine,
                canManage = canManage,
                onReply = {
                    replyTo = message
                    editing = null
                    sheetMessage = null
                },
                onCopy = {
                    clipboard.setText(AnnotatedString(message.text))
                    sheetMessage = null
                },
                onEdit = {
                    editing = message
                    replyTo = null
                    draft = message.text
                    sheetMessage = null
                },
                onDelete = {
                    vm.deleteMessage(message.seq)
                    sheetMessage = null
                },
                onPin = {
                    vm.pinMessage(message.seq, !message.pinned)
                    sheetMessage = null
                },
                onReact = { emoji ->
                    vm.toggleReaction(message.seq, emoji)
                    sheetMessage = null
                },
            )
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty() && listState.firstVisibleItemIndex <= 1) {
            if (reduceMotion) listState.scrollToItem(0) else listState.animateScrollToItem(0)
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
private fun MessageActions(
    message: UiMessage,
    isMine: Boolean,
    canManage: Boolean,
    onReply: () -> Unit,
    onCopy: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onPin: () -> Unit,
    onReact: (String) -> Unit,
) {
    val c = LocalTgColors.current

    Column(modifier = Modifier.fillMaxWidth().padding(bottom = 18.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            QUICK_REACTIONS.forEach { emoji ->
                Text(
                    text = emoji,
                    fontSize = 26.sp,
                    modifier = Modifier
                        .clip(CircleShape)
                        .clickable { onReact(emoji) }
                        .padding(6.dp),
                )
            }
        }

        ActionRow("回复", Icons.AutoMirrored.Rounded.Reply, c) { onReply() }
        if (message.text.isNotBlank()) {
            ActionRow("复制", Icons.Rounded.ContentCopy, c) { onCopy() }
        }
        if (isMine && message.media == null && !message.deleted) {
            ActionRow("编辑", Icons.Rounded.Edit, c) { onEdit() }
        }
        ActionRow(if (message.pinned) "取消置顶" else "置顶", Icons.Rounded.PushPin, c) { onPin() }
        if ((isMine || canManage) && !message.deleted) {
            ActionRow("删除", Icons.Rounded.Delete, c, danger = true) { onDelete() }
        }
    }
}

@Composable
private fun ActionRow(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    c: com.tgchat.app.ui.theme.TgColors,
    danger: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (danger) c.danger else c.icon, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, color = if (danger) c.danger else c.textPrimary, fontSize = 15.sp)
    }
    HorizontalDivider(color = c.divider.copy(alpha = 0.4f), thickness = 0.5.dp)
}

@Composable
private fun AttachDialog(
    onDismiss: () -> Unit,
    onPhoto: () -> Unit,
    onFile: () -> Unit,
) {
    val c = LocalTgColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = c.textSecondary) }
        },
        title = { Text("发送", color = c.textPrimary) },
        text = {
            Column {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onPhoto)
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.Image, contentDescription = null, tint = TelegramBlue)
                    Spacer(Modifier.width(12.dp))
                    Text("照片", color = c.textPrimary, fontSize = 15.sp)
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onFile)
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.Description, contentDescription = null, tint = TelegramBlue)
                    Spacer(Modifier.width(12.dp))
                    Text("文件", color = c.textPrimary, fontSize = 15.sp)
                }
            }
        },
    )
}

@Composable
private fun Composer(
    value: String,
    onValueChange: (String) -> Unit,
    replyTo: UiMessage?,
    editing: UiMessage?,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit,
    onAttach: () -> Unit,
    onEmoji: (String) -> Unit,
    onSend: () -> Unit,
) {
    val c = LocalTgColors.current
    var emojiOpen by remember { mutableStateOf(false) }

    Column(modifier = Modifier.background(c.headerBg)) {
        if (editing != null) {
            Bar(
                title = "编辑消息",
                body = editing.text,
                tint = TelegramBlue,
                onClose = onCancelEdit,
            )
        } else if (replyTo != null) {
            Bar(
                title = replyTo.senderName,
                body = replyTo.text.ifBlank { "消息" },
                tint = c.accent,
                onClose = onCancelReply,
            )
        }

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
                            .clickable { onEmoji(emoji) },
                    )
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))
                .padding(horizontal = 4.dp, vertical = 6.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            IconButton(onClick = onAttach) {
                Icon(Icons.Rounded.AttachFile, contentDescription = "附件", tint = c.icon)
            }

            IconButton(onClick = { emojiOpen = !emojiOpen }) {
                Icon(Icons.Outlined.EmojiEmotions, contentDescription = "表情", tint = c.icon)
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(20.dp))
                    .background(c.surfaceAlt)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                if (value.isEmpty()) {
                    Text("Message", color = c.textTertiary, fontSize = 16.sp)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    textStyle = TextStyle(color = c.textPrimary, fontSize = 16.sp, lineHeight = 21.sp),
                    cursorBrush = SolidColor(TelegramBlue),
                    maxLines = 5,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.width(8.dp))

            val enabled = value.isNotBlank()
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(if (enabled) TelegramBlue else c.surfaceAlt)
                    .clickable(enabled = enabled) { onSend() },
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

@Composable
private fun Bar(title: String, body: String, tint: Color, onClose: () -> Unit) {
    val c = LocalTgColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.surfaceAlt)
            .padding(horizontal = 14.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .width(2.dp)
                .height(30.dp)
                .background(tint, RoundedCornerShape(1.dp)),
        )
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = tint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(body, color = c.textSecondary, fontSize = 12.sp, maxLines = 1)
        }
        IconButton(onClick = onClose) {
            Icon(
                Icons.Rounded.Close,
                contentDescription = "取消",
                tint = c.textTertiary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
