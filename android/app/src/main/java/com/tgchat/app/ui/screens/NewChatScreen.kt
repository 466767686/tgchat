package com.tgchat.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.data.UserDto
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.EmptyState
import com.tgchat.app.ui.components.SectionDivider
import com.tgchat.app.ui.components.ScreenHeader
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue
import kotlinx.coroutines.delay

@Composable
fun NewChatScreen(vm: AppViewModel) {
    val c = LocalTgColors.current
    var query by remember { mutableStateOf("") }

    LaunchedEffect(query) {
        delay(if (query.isBlank()) 0 else 280)
        vm.loadUsers(query)
    }

    Column(modifier = Modifier.fillMaxSize().background(c.background)) {
        ScreenHeader(title = "新建会话", onBack = { vm.back() })

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(c.surfaceAlt)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = c.textTertiary, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text("搜索用户名或昵称", color = c.textTertiary, fontSize = 15.sp)
                    }
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        singleLine = true,
                        textStyle = TextStyle(color = c.textPrimary, fontSize = 15.sp),
                        cursorBrush = SolidColor(TelegramBlue),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        if (vm.usersLoading && vm.usersDirectory.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = TelegramBlue, strokeWidth = 2.dp, modifier = Modifier.size(26.dp))
            }
        } else if (vm.usersDirectory.isEmpty()) {
            EmptyState(
                title = "没有找到联系人",
                subtitle = "请联系管理员为你创建账号",
                modifier = Modifier.padding(top = 48.dp),
            )
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(vm.usersDirectory, key = { it.id }) { user ->
                    UserRow(user = user, onClick = { vm.startChatWith(user.id) })
                    SectionDivider()
                }
            }
        }
    }
}

@Composable
private fun UserRow(user: UserDto, onClick: () -> Unit) {
    val c = LocalTgColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name = user.displayName.ifBlank { user.username }, colorHex = user.avatarColor, size = 46.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = user.displayName.ifBlank { user.username },
                color = c.textPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = "@${user.username}",
                color = c.textSecondary,
                fontSize = 13.sp,
                maxLines = 1,
            )
        }
        if (user.role == "admin") {
            Text(
                text = "管理员",
                color = c.accent,
                fontSize = 12.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(c.accentSoft)
                    .padding(horizontal = 8.dp, vertical = 3.dp),
            )
        }
    }
}
