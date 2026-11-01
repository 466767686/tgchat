package com.tgchat.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tgchat.app.AppViewModel
import com.tgchat.app.ui.LocalReduceMotion
import com.tgchat.app.ui.motionPress
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val PinkTop = Color(0xFFFFE6F1)
private val PinkBottom = Color(0xFFF3ECFF)
private val AccentPink = Color(0xFFFF7FAE)
private val DeepInk = Color(0xFF5C4A56)
private val SoftInk = Color(0xFFA6909E)

private data class FakeNote(
    val id: String,
    val title: String,
    val body: String,
    val time: String,
    val emoji: String,
    val tint: Color,
)

private fun sampleNotes(): List<FakeNote> = listOf(
    FakeNote("1", "周末计划", "去美术馆看新展，然后吃草莓蛋糕 🍰\n记得带上相机。", "今天 09:24", "🍰", Color(0xFFFF9FC4)),
    FakeNote("2", "想买的", "月见色的指甲油、兔子抱枕、新的手帐本 ✨", "昨天", "🐰", Color(0xFFC6A8FF)),
    FakeNote("3", "给未来的自己", "今天也有好好努力，辛苦啦 🌙\n明天也要记得吃早饭。", "10月28日", "🌙", Color(0xFF9ED8FF)),
)

@Composable
fun NoteDisguiseScreen(vm: AppViewModel) {
    val reduceMotion = LocalReduceMotion.current
    val haptic = LocalHapticFeedback.current
    var notes by remember { mutableStateOf(sampleNotes()) }
    var query by remember { mutableStateOf("") }
    var moonTaps by remember { mutableIntStateOf(0) }
    var showPin by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<FakeNote?>(null) }
    var composing by remember { mutableStateOf(false) }

    LaunchedEffect(moonTaps) {
        if (moonTaps >= 5) {
            moonTaps = 0
            showPin = true
        }
    }

    val filtered = remember(query, notes) {
        if (query.isBlank()) notes
        else notes.filter { it.title.contains(query, true) || it.body.contains(query, true) }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(PinkTop, Color(0xFFFFF7FB), PinkBottom))),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 20.dp),
        ) {
            Header(
                reduceMotion = reduceMotion,
                onMoonTap = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    moonTaps += 1
                },
            )

            SearchField(
                value = query,
                onValueChange = { value ->
                    if (value.isNotEmpty() && value == vm.unlockPin) {
                        query = ""
                        vm.unlock()
                    } else {
                        query = value
                    }
                },
            )

            if (filtered.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(top = 60.dp),
                    ) {
                        Text("🌙", fontSize = 34.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("没有找到便笺", color = SoftInk, fontSize = 14.sp)
                    }
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    item { Spacer(Modifier.height(4.dp)) }
                    items(filtered, key = { it.id }) { note ->
                        NoteCard(note = note, reduceMotion = reduceMotion) { detail = note }
                    }
                    item { Spacer(Modifier.height(96.dp)) }
                }
            }
        }

        FloatingActionButton(
            onClick = { composing = true },
            containerColor = AccentPink,
            contentColor = Color.White,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 22.dp, bottom = 26.dp),
        ) {
            Icon(Icons.Rounded.Add, contentDescription = "新建便笺")
        }

        AnimatedVisibility(
            visible = showPin,
            enter = fadeIn(tween(160)) + scaleIn(
                initialScale = if (reduceMotion) 1f else 0.96f,
                animationSpec = tween(180),
            ),
            exit = fadeOut(tween(120)),
        ) {
            PinPad(
                pin = vm.unlockPin,
                reduceMotion = reduceMotion,
                onSuccess = {
                    showPin = false
                    vm.unlock()
                },
                onCancel = { showPin = false },
            )
        }
    }

    if (showPin) {
        BackHandler { showPin = false }
    }

    detail?.let { note ->
        AlertDialog(
            onDismissRequest = { detail = null },
            confirmButton = {
                TextButton(onClick = { detail = null }) { Text("关闭", color = AccentPink) }
            },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(note.emoji, fontSize = 22.sp)
                    Spacer(Modifier.width(8.dp))
                    Text(note.title, color = DeepInk, fontWeight = FontWeight.Bold)
                }
            },
            text = {
                Column {
                    Text(note.time, color = SoftInk, fontSize = 12.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(note.body, color = DeepInk, fontSize = 15.sp, lineHeight = 22.sp)
                }
            },
        )
    }

    if (composing) {
        ComposeNoteDialog(
            onDismiss = { composing = false },
            onSave = { title, body ->
                notes = notes + FakeNote(
                    id = "n-" + System.currentTimeMillis(),
                    title = title.ifBlank { "无标题" },
                    body = body,
                    time = "刚刚",
                    emoji = listOf("🌙", "🍰", "🌷", "✨", "🐰").random(),
                    tint = listOf(Color(0xFFFF9FC4), Color(0xFFC6A8FF), Color(0xFF9ED8FF)).random(),
                )
                composing = false
            },
        )
    }
}

@Composable
private fun Header(reduceMotion: Boolean, onMoonTap: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 18.dp, bottom = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = SimpleDateFormat("M月d日 EEEE", Locale.CHINA).format(Date()),
                color = SoftInk,
                fontSize = 12.sp,
            )
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🌙", fontSize = 20.sp)
                Spacer(Modifier.width(6.dp))
                Text("月见便笺", color = DeepInk, fontSize = 26.sp, fontWeight = FontWeight.Bold)
            }
        }

        val interaction = remember { MutableInteractionSource() }
        IconButton(
            onClick = onMoonTap,
            modifier = Modifier
                .size(44.dp)
                .motionPress(interaction, reduceMotion, 0.9f)
                .background(Color.White.copy(alpha = 0.8f), CircleShape),
        ) {
            Text("🌙", fontSize = 18.sp)
        }
    }
}

@Composable
private fun SearchField(value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        placeholder = { Text("搜索便笺", color = SoftInk, fontSize = 14.sp) },
        leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null, tint = SoftInk) },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onValueChange("") }) {
                    Icon(Icons.Rounded.Close, contentDescription = null, tint = SoftInk)
                }
            }
        },
        shape = RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = Color.White.copy(alpha = 0.92f),
            unfocusedContainerColor = Color.White.copy(alpha = 0.92f),
            focusedBorderColor = AccentPink.copy(alpha = 0.5f),
            unfocusedBorderColor = Color.Transparent,
            focusedTextColor = DeepInk,
            unfocusedTextColor = DeepInk,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp),
    )
}

@Composable
private fun NoteCard(note: FakeNote, reduceMotion: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.94f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier
            .fillMaxWidth()
            .motionPress(interaction, reduceMotion, 0.985f)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .background(note.tint.copy(alpha = 0.22f), RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(note.emoji, fontSize = 22.sp)
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(note.title, color = DeepInk, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(4.dp))
                Text(
                    note.body,
                    color = SoftInk,
                    fontSize = 13.sp,
                    maxLines = 2,
                    lineHeight = 18.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(note.time, color = SoftInk.copy(alpha = 0.75f), fontSize = 11.sp)
            }
        }
    }
}

@Composable
private fun PinPad(
    pin: String,
    reduceMotion: Boolean,
    onSuccess: () -> Unit,
    onCancel: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val length = maxOf(4, pin.length)
    var input by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(PinkTop, PinkBottom)))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { /* swallow taps behind the lock */ },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(horizontal = 32.dp),
        ) {
            Text("🌙", fontSize = 38.sp)
            Spacer(Modifier.height(8.dp))
            Text("月见便笺", color = DeepInk, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text(
                if (error) "密码不对，再试一次" else "输入密码",
                color = if (error) Color(0xFFE0645A) else SoftInk,
                fontSize = 13.sp,
            )

            Spacer(Modifier.height(18.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                repeat(length) { index ->
                    Box(
                        modifier = Modifier
                            .size(13.dp)
                            .background(
                                if (index < input.length) AccentPink else Color.White,
                                CircleShape,
                            ),
                    )
                }
            }

            Spacer(Modifier.height(28.dp))

            val rows = listOf(
                listOf("1", "2", "3"),
                listOf("4", "5", "6"),
                listOf("7", "8", "9"),
                listOf("", "0", "⌫"),
            )
            rows.forEach { row ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(18.dp),
                    modifier = Modifier.padding(bottom = 14.dp),
                ) {
                    row.forEach { key ->
                        if (key.isEmpty()) {
                            Spacer(Modifier.size(72.dp))
                        } else {
                            val interaction = remember { MutableInteractionSource() }
                            Box(
                                modifier = Modifier
                                    .size(72.dp)
                                    .motionPress(interaction, reduceMotion, 0.92f)
                                    .background(Color.White.copy(alpha = 0.94f), CircleShape)
                                    .clickable(interactionSource = interaction, indication = null) {
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        if (key == "⌫") {
                                            if (input.isNotEmpty()) input = input.dropLast(1)
                                            error = false
                                        } else if (input.length < length) {
                                            input += key
                                            if (input.length == length) {
                                                if (input == pin) {
                                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                                    onSuccess()
                                                } else {
                                                    error = true
                                                    input = ""
                                                }
                                            }
                                        }
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                if (key == "⌫") {
                                    Icon(
                                        Icons.Rounded.Delete,
                                        contentDescription = "删除",
                                        tint = DeepInk,
                                    )
                                } else {
                                    Text(key, color = DeepInk, fontSize = 26.sp, fontWeight = FontWeight.Medium)
                                }
                            }
                        }
                    }
                }
            }

            TextButton(onClick = onCancel) {
                Text("取消", color = SoftInk, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun ComposeNoteDialog(
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onSave(title.trim(), body.trim()) }) {
                Text("保存", color = AccentPink)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = SoftInk) }
        },
        title = { Text("新建便笺", color = DeepInk) },
        text = {
            Column {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    singleLine = true,
                    placeholder = { Text("标题", color = SoftInk) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                )
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = body,
                    onValueChange = { body = it },
                    placeholder = { Text("写点什么…", color = SoftInk) },
                    minLines = 3,
                    maxLines = 6,
                )
            }
        },
    )
}
