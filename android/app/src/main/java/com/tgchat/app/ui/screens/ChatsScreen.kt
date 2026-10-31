package com.tgchat.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.ChatUi
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.EmptyState
import com.tgchat.app.ui.components.SectionDivider
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue
import com.tgchat.app.util.formatChatListTime

@Composable
fun ChatsScreen(vm: AppViewModel) {
    val c = LocalTgColors.current
    var searchMode by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }

    val visible = remember(vm.chats, query) {
        if (query.isBlank()) vm.chats
        else vm.chats.filter {
            it.title.contains(query, ignoreCase = true) || it.lastText.contains(query, ignoreCase = true)
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(c.background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            // ---------------- header ----------------
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(c.surface)
                    .statusBarsPadding()
                    .height(56.dp)
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { vm.openSettings() }) {
                    Icon(Icons.Rounded.Menu, contentDescription = "菜单", tint = c.icon)
                }
                Text(
                    text = "Chats",
                    color = c.textPrimary,
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { searchMode = !searchMode; if (!searchMode) query = "" }) {
                    Icon(Icons.Rounded.Search, contentDescription = "搜索", tint = c.icon)
                }
                Box {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = "更多", tint = c.icon)
                    }
                    DropdownMenu(
                        expanded = menuOpen,
                        onDismissRequest = { menuOpen = false },
                        containerColor = c.surface,
                    ) {
                        DropdownMenuItem(
                            text = { Text("新建会话", color = c.textPrimary) },
                            onClick = { menuOpen = false; vm.openNewChat() },
                        )
                        DropdownMenuItem(
                            text = { Text("设置", color = c.textPrimary) },
                            onClick = { menuOpen = false; vm.openSettings() },
                        )
                        if (vm.me?.role == "admin") {
                            DropdownMenuItem(
                                text = { Text("用户管理", color = c.textPrimary) },
                                onClick = { menuOpen = false; vm.openAdmin() },
                            )
                        }
                    }
                }
            }

            if (searchMode) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(c.surface)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(18.dp))
                            .background(c.surfaceAlt)
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                    ) {
                        if (query.isEmpty()) {
                            Text("搜索", color = c.textTertiary, fontSize = 15.sp)
                        }
                        BasicTextField(
                            value = query,
                            onValueChange = { query = it },
                            singleLine = true,
                            textStyle = androidx.compose.ui.text.TextStyle(
                                color = c.textPrimary,
                                fontSize = 15.sp,
                            ),
                            cursorBrush = SolidColor(TelegramBlue),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    IconButton(onClick = { searchMode = false; query = "" }) {
                        Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = c.icon)
                    }
                }
            }

            Spacer(Modifier.height(4.dp))

            when {
                vm.chatsLoading && vm.chats.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = TelegramBlue, strokeWidth = 2.5.dp)
                    }
                }
                visible.isEmpty() -> {
                    EmptyState(
                        title = if (query.isBlank()) "还没有会话" else "没有找到结果",
                        subtitle = if (query.isBlank()) "点右下角的按钮开始聊天" else "试试其他关键词",
                        modifier = Modifier.padding(top = 60.dp),
                    )
                }
                else -> {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(visible, key = { it.id }) { chat ->
                            ChatRow(chat = chat, onClick = { vm.openChat(chat.id) })
                            SectionDivider()
                        }
                        item { Spacer(Modifier.height(88.dp)) }
                    }
                }
            }
        }

        FloatingActionButton(
            onClick = { vm.openNewChat() },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(18.dp),
            containerColor = TelegramBlue,
            contentColor = Color.White,
            shape = CircleShape,
        ) {
            Icon(Icons.Rounded.Edit, contentDescription = "新建会话")
        }
    }
}

@Composable
private fun ChatRow(chat: ChatUi, onClick: () -> Unit) {
    val c = LocalTgColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.background)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name = chat.title, colorHex = chat.avatarColor, size = 54.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = chat.title,
                    color = c.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = formatChatListTime(chat.lastAt),
                    color = if (chat.unread > 0) c.accent else c.textTertiary,
                    fontSize = 12.sp,
                )
            }
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = chat.lastText,
                    color = c.textSecondary,
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (chat.unread > 0) {
                    Spacer(Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
                            .clip(CircleShape)
                            .background(c.unreadBadge)
                            .padding(horizontal = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = if (chat.unread > 99) "99+" else chat.unread.toString(),
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
            }
        }
    }
}
