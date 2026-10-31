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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.PersonAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.data.UserDto
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.ScreenHeader
import com.tgchat.app.ui.components.SectionDivider
import com.tgchat.app.ui.components.TgTextField
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue

@Composable
fun AdminScreen(vm: AppViewModel) {
    val c = LocalTgColors.current
    var showAdd by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize().background(c.background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            ScreenHeader(title = "用户管理", onBack = { vm.back() })

            Text(
                text = "共 ${vm.adminUsers.size} 个账号 · 应用内不支持自助注册",
                color = c.textSecondary,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
            )

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(vm.adminUsers, key = { it.id }) { user ->
                    AdminUserRow(user)
                    SectionDivider()
                }
                item { Spacer(Modifier.height(96.dp)) }
            }
        }

        FloatingActionButton(
            onClick = { vm.clearAdminError(); showAdd = true },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(18.dp),
            containerColor = TelegramBlue,
            contentColor = Color.White,
            shape = CircleShape,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = "创建账号")
        }
    }

    if (showAdd) {
        AddUserDialog(vm, onDismiss = { showAdd = false })
    }
}

@Composable
private fun AdminUserRow(user: UserDto) {
    val c = LocalTgColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name = user.displayName.ifBlank { user.username }, colorHex = user.avatarColor, size = 44.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = user.displayName.ifBlank { user.username },
                color = c.textPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
            )
            Text("@${user.username}", color = c.textSecondary, fontSize = 12.5.sp)
        }
        val isAdmin = user.role == "admin"
        Text(
            text = if (isAdmin) "管理员" else "普通用户",
            color = if (isAdmin) c.accent else c.textSecondary,
            fontSize = 12.sp,
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(if (isAdmin) c.accentSoft else c.surfaceAlt)
                .padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}

@Composable
private fun AddUserDialog(vm: AppViewModel, onDismiss: () -> Unit) {
    val c = LocalTgColors.current
    var username by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isAdmin by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { if (!vm.adminBusy) onDismiss() },
        containerColor = c.surface,
        shape = RoundedCornerShape(20.dp),
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.PersonAdd, contentDescription = null, tint = TelegramBlue)
                Spacer(Modifier.width(8.dp))
                Text("创建账号", color = c.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
            }
        },
        text = {
            Column {
                TgTextField(username, { username = it; vm.clearAdminError() }, "用户名（字母、数字、下划线）")
                Spacer(Modifier.height(10.dp))
                TgTextField(displayName, { displayName = it }, "显示名称（可选）")
                Spacer(Modifier.height(10.dp))
                TgTextField(password, { password = it; vm.clearAdminError() }, "初始密码（至少 6 位）", isPassword = true)
                Spacer(Modifier.height(14.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("账号类型", color = c.textSecondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    RoleChip("普通用户", !isAdmin) { isAdmin = false }
                    Spacer(Modifier.width(8.dp))
                    RoleChip("管理员", isAdmin) { isAdmin = true }
                }

                val error = vm.adminError
                if (error != null) {
                    Spacer(Modifier.height(10.dp))
                    Text(error, color = c.danger, fontSize = 13.sp)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !vm.adminBusy,
                onClick = {
                    vm.adminCreateUser(username, password, displayName, if (isAdmin) "admin" else "user") {
                        onDismiss()
                    }
                },
            ) {
                if (vm.adminBusy) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = TelegramBlue)
                } else {
                    Text("创建", color = TelegramBlue, fontWeight = FontWeight.SemiBold)
                }
            }
        },
        dismissButton = {
            TextButton(enabled = !vm.adminBusy, onClick = onDismiss) {
                Text("取消", color = c.textSecondary)
            }
        },
    )
}

@Composable
private fun RoleChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val c = LocalTgColors.current
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) TelegramBlue else c.surfaceAlt)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else c.textSecondary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}
