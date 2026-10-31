package com.tgchat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue

@Composable
fun ScreenHeader(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val c = LocalTgColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(c.surface)
            .statusBarsPadding()
            .height(56.dp)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = c.icon)
        }
        Text(
            text = title,
            color = c.textPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
        )
        actions()
    }
}

@Composable
fun TgTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    isPassword: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
) {
    val c = LocalTgColors.current
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text(placeholder, color = c.textTertiary, fontSize = 15.sp) },
        singleLine = singleLine,
        visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = TelegramBlue,
            unfocusedBorderColor = c.divider,
            focusedContainerColor = c.surfaceAlt.copy(alpha = 0.55f),
            unfocusedContainerColor = c.surfaceAlt.copy(alpha = 0.55f),
            cursorColor = TelegramBlue,
            focusedTextColor = c.textPrimary,
            unfocusedTextColor = c.textPrimary,
        ),
    )
}

@Composable
fun ServerUrlDialog(
    current: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    val c = LocalTgColors.current
    var value by remember { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = c.surface,
        shape = RoundedCornerShape(20.dp),
        title = {
            Text("服务器地址", color = c.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
        },
        text = {
            Column {
                Text(
                    "填写部署好的 Cloudflare Worker 地址，例如 https://tgchat-api.你的账号.workers.dev",
                    color = c.textSecondary,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = TelegramBlue,
                        unfocusedBorderColor = c.divider,
                        focusedTextColor = c.textPrimary,
                        unfocusedTextColor = c.textPrimary,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (value.isNotBlank()) onSave(value.trim())
            }) { Text("保存", color = TelegramBlue, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = c.textSecondary) }
        },
    )
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = false,
) {
    val c = LocalTgColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = c.surface,
        shape = RoundedCornerShape(20.dp),
        title = { Text(title, color = c.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold) },
        text = { Text(text, color = c.textSecondary, fontSize = 14.sp, lineHeight = 20.sp) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel, color = if (destructive) c.danger else TelegramBlue, fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = c.textSecondary) }
        },
    )
}

@Composable
fun EmptyState(title: String, subtitle: String, modifier: Modifier = Modifier) {
    val c = LocalTgColors.current
    Column(
        modifier = modifier.fillMaxWidth().heightIn(min = 240.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .background(c.surfaceAlt, RoundedCornerShape(36.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Rounded.ChatBubbleOutline,
                contentDescription = null,
                tint = c.textTertiary,
                modifier = Modifier.size(30.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
        Text(title, color = c.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(4.dp))
        Text(subtitle, color = c.textTertiary, fontSize = 13.sp)
    }
}

@Composable
fun SectionDivider() {
    val c = LocalTgColors.current
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 84.dp)
            .height(0.6.dp)
            .background(c.divider),
    )
}

@Composable
fun VerticalSpacer(height: Int) = Spacer(Modifier.height(height.dp))

@Composable
fun HorizontalSpacer(width: Int) = Spacer(Modifier.width(width.dp))
