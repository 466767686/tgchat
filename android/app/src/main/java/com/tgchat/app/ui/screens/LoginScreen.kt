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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.ui.components.ServerUrlDialog
import com.tgchat.app.ui.components.TgTextField
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue

@Composable
fun LoginScreen(vm: AppViewModel) {
    val c = LocalTgColors.current
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var showServerDialog by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize().background(c.background)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(78.dp))

            Box(
                modifier = Modifier
                    .size(104.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(Color(0xFF5FAEF7), TelegramBlue))),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Send,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(50.dp),
                )
            }

            Spacer(Modifier.height(20.dp))
            Text(
                text = "Telegram",
                color = c.textPrimary,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "登录以开始聊天",
                color = c.textSecondary,
                fontSize = 14.sp,
            )

            if (vm.baseUrl.contains("example.workers.dev")) {
                Spacer(Modifier.height(18.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (c.isDark) Color(0xFF3A2E1A) else Color(0xFFFFF4E5))
                        .clickable { showServerDialog = true }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Rounded.Warning,
                        contentDescription = null,
                        tint = if (c.isDark) Color(0xFFFFC46B) else Color(0xFFE08A00),
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "服务器地址尚未配置，点此填写你的 Worker 地址",
                        color = if (c.isDark) Color(0xFFFFD79A) else Color(0xFF8A5300),
                        fontSize = 12.5.sp,
                    )
                }
            }

            Spacer(Modifier.height(38.dp))
            TgTextField(
                value = username,
                onValueChange = { username = it; vm.clearLoginError() },
                placeholder = "用户名",
                keyboardType = KeyboardType.Text,
            )
            Spacer(Modifier.height(12.dp))
            TgTextField(
                value = password,
                onValueChange = { password = it; vm.clearLoginError() },
                placeholder = "密码",
                isPassword = true,
                keyboardType = KeyboardType.Password,
            )

            val error = vm.loginError
            if (error != null) {
                Spacer(Modifier.height(10.dp))
                Text(
                    text = error,
                    color = c.danger,
                    fontSize = 13.sp,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.height(20.dp))
            Button(
                onClick = { vm.login(username, password) },
                enabled = !vm.loginLoading && username.isNotBlank() && password.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = TelegramBlue,
                    contentColor = Color.White,
                    disabledContainerColor = TelegramBlue.copy(alpha = 0.35f),
                    disabledContentColor = Color.White.copy(alpha = 0.8f),
                ),
            ) {
                if (vm.loginLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text("登录", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(Modifier.height(18.dp))
            Text(
                text = "账号由管理员创建，应用内不支持自助注册",
                color = c.textTertiary,
                fontSize = 12.sp,
            )

            Spacer(Modifier.height(46.dp))
            TextButton(onClick = { showServerDialog = true }) {
                Text(
                    text = "服务器 · ${vm.baseUrl}",
                    color = c.textSecondary,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.height(20.dp))
        }
    }

    if (showServerDialog) {
        ServerUrlDialog(
            current = vm.baseUrl,
            onDismiss = { showServerDialog = false },
            onSave = {
                vm.setBaseUrl(it)
                showServerDialog = false
            },
        )
    }
}
