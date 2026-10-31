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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AdminPanelSettings
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Logout
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.ThemeMode
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.components.ConfirmDialog
import com.tgchat.app.ui.components.ScreenHeader
import com.tgchat.app.ui.components.ServerUrlDialog
import com.tgchat.app.ui.components.SectionDivider
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue

@Composable
fun SettingsScreen(vm: AppViewModel) {
    val c = LocalTgColors.current
    var showTheme by remember { mutableStateOf(false) }
    var showServer by remember { mutableStateOf(false) }
    var showLogout by remember { mutableStateOf(false) }

    val me = vm.me

    Column(modifier = Modifier.fillMaxSize().background(c.background)) {
        ScreenHeader(title = "设置", onBack = { vm.back() })

        // profile
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar(
                name = me?.displayName?.ifBlank { me.username } ?: "?",
                colorHex = me?.avatarColor ?: "#3390EC",
                size = 62.dp,
            )
            Spacer(Modifier.width(14.dp))
            Column {
                Text(
                    text = me?.displayName?.ifBlank { me?.username } ?: "未登录",
                    color = c.textPrimary,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "@${me?.username ?: ""}",
                    color = c.textSecondary,
                    fontSize = 14.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = if (me?.role == "admin") "管理员账号" else "普通账号",
                    color = c.accent,
                    fontSize = 12.sp,
                )
            }
        }

        SectionDivider()

        SettingsRow(
            icon = Icons.Rounded.DarkMode,
            title = "主题",
            value = when (vm.themeMode) {
                ThemeMode.SYSTEM -> "跟随系统"
                ThemeMode.LIGHT -> "浅色"
                ThemeMode.DARK -> "深色"
            },
            onClick = { showTheme = true },
        )
        SettingsRow(
            icon = Icons.Rounded.Cloud,
            title = "服务器地址",
            value = vm.baseUrl.removePrefix("https://").removePrefix("http://"),
            onClick = { showServer = true },
        )
        if (me?.role == "admin") {
            SettingsRow(
                icon = Icons.Rounded.AdminPanelSettings,
                title = "用户管理",
                value = "创建账号",
                onClick = { vm.openAdmin() },
            )
        }

        Spacer(Modifier.height(10.dp))
        SectionDivider()

        SettingsRow(
            icon = Icons.Rounded.Logout,
            title = "退出登录",
            value = "",
            tint = c.danger,
            onClick = { showLogout = true },
        )

        Spacer(Modifier.weight(1f))
        Text(
            text = "Telegram Clone 1.0.0 · Cloudflare Workers + D1",
            color = c.textTertiary,
            fontSize = 11.sp,
            modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }

    if (showTheme) {
        ThemeDialog(
            current = vm.themeMode,
            onSelect = { vm.setTheme(it); showTheme = false },
            onDismiss = { showTheme = false },
        )
    }
    if (showServer) {
        ServerUrlDialog(
            current = vm.baseUrl,
            onDismiss = { showServer = false },
            onSave = {
                vm.setBaseUrl(it)
                showServer = false
            },
        )
    }
    if (showLogout) {
        ConfirmDialog(
            title = "退出登录",
            text = "退出后需要重新输入用户名和密码，确定退出吗？",
            confirmLabel = "退出",
            destructive = true,
            onConfirm = {
                showLogout = false
                vm.logout()
            },
            onDismiss = { showLogout = false },
        )
    }
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    title: String,
    value: String,
    onClick: () -> Unit,
    tint: androidx.compose.ui.graphics.Color? = null,
) {
    val c = LocalTgColors.current
    val color = tint ?: c.textPrimary
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (tint != null) color else c.icon, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(16.dp))
        Text(title, color = color, fontSize = 16.sp, modifier = Modifier.weight(1f))
        if (value.isNotEmpty()) {
            Text(value, color = c.textSecondary, fontSize = 13.sp, maxLines = 1)
        }
    }
}

@Composable
private fun ThemeDialog(
    current: ThemeMode,
    onSelect: (ThemeMode) -> Unit,
    onDismiss: () -> Unit,
) {
    val c = LocalTgColors.current
    val options = listOf(
        ThemeMode.SYSTEM to "跟随系统",
        ThemeMode.LIGHT to "浅色",
        ThemeMode.DARK to "深色",
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = c.surface,
        shape = RoundedCornerShape(20.dp),
        title = { Text("主题", color = c.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold) },
        text = {
            Column {
                for ((mode, label) in options) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onSelect(mode) }
                            .padding(vertical = 12.dp, horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(label, color = c.textPrimary, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        if (mode == current) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = TelegramBlue, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("完成", color = TelegramBlue) }
        },
    )
}
