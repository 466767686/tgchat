package com.tgchat.app

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import com.tgchat.app.push.RealtimeService
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.tgchat.app.ui.screens.AdminScreen
import com.tgchat.app.ui.LocalReduceMotion
import com.tgchat.app.ui.rememberReduceMotion
import com.tgchat.app.data.MessageDto
import com.tgchat.app.push.AppSettings
import com.tgchat.app.push.IncomingCenter
import com.tgchat.app.push.MessageSound
import com.tgchat.app.ui.components.Avatar
import com.tgchat.app.ui.screens.NoteDisguiseScreen
import com.tgchat.app.util.formatMessageTime
import com.tgchat.app.ui.screens.ChatScreen
import com.tgchat.app.ui.screens.ChatsScreen
import com.tgchat.app.ui.screens.LoginScreen
import com.tgchat.app.ui.screens.NewChatScreen
import com.tgchat.app.ui.screens.SettingsScreen
import com.tgchat.app.ui.theme.LocalTgColors
import com.tgchat.app.ui.theme.TelegramBlue
import com.tgchat.app.ui.theme.TgTheme
import kotlinx.coroutines.delay

private fun Context.findActivity(): Activity? {
    var ctx = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

@Composable
fun TelegramApp(vm: AppViewModel) {
    val dark = when (vm.themeMode) {
        ThemeMode.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }

    TgTheme(darkTheme = dark) {
        val reduceMotion = rememberReduceMotion()
        val view = LocalView.current
        val context = LocalContext.current

        var popupMessage by remember { mutableStateOf<MessageDto?>(null) }
        var popupVisible by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) {
            IncomingCenter.events.collect { message ->
                if (vm.token == null || vm.locked) return@collect
                if (message.chatId == vm.activeChatId) return@collect
                if (!AppSettings.popupEnabled(context)) return@collect
                popupMessage = message
                popupVisible = true
                MessageSound.play(context)
            }
        }

        LaunchedEffect(popupVisible) {
            if (popupVisible) {
                delay(4200)
                popupVisible = false
            }
        }
        val lockedNow = vm.disguiseEnabled && vm.locked
        SideEffect {
            if (!view.isInEditMode) {
                context.findActivity()?.let { activity ->
                    val light = if (lockedNow) true else !dark
                    WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = light
                    WindowCompat.getInsetsController(activity.window, view).isAppearanceLightNavigationBars = light
                }
            }
        }

        val lifecycleOwner = LocalLifecycleOwner.current
        DisposableEffect(lifecycleOwner) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_STOP) vm.lock()
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
        }

        val appContext = context.applicationContext
        LaunchedEffect(vm.token, vm.baseUrl) {
            val token = vm.token
            if (token != null) {
                runCatching { RealtimeService.start(appContext, vm.baseUrl, token) }
            } else {
                runCatching { RealtimeService.stopAndClear(appContext) }
            }
        }
        LaunchedEffect(vm.token, vm.chats, vm.locked) {
            val pending = PendingNavigation.chatId
            if (!vm.locked && pending != null && vm.token != null && vm.chats.any { it.id == pending }) {
                PendingNavigation.chatId = null
                vm.openChat(pending)
            }
        }

        CompositionLocalProvider(LocalReduceMotion provides reduceMotion) {
        Surface(modifier = Modifier.fillMaxSize(), color = LocalTgColors.current.background) {
            Box(modifier = Modifier.fillMaxSize()) {
                if (vm.disguiseEnabled && vm.locked) {
                    NoteDisguiseScreen(vm)
                } else AnimatedContent(
                    targetState = vm.route,
                    transitionSpec = {
                        if (reduceMotion) {
                            fadeIn(tween(120)) togetherWith fadeOut(tween(120))
                        } else {
                            (fadeIn(tween(180)) + slideInHorizontally(tween(220)) { it / 14 }) togetherWith
                                (fadeOut(tween(140)) + slideOutHorizontally(tween(200)) { -it / 20 })
                        }
                    },
                    label = "screen",
                ) { route ->
                    when (route) {
                        Route.Boot -> SplashScreen()
                        Route.Login -> LoginScreen(vm)
                        Route.Chats -> ChatsScreen(vm)
                        is Route.Chat -> ChatScreen(vm, route.id)
                        Route.NewChat -> NewChatScreen(vm)
                        Route.Settings -> SettingsScreen(vm)
                        Route.Admin -> AdminScreen(vm)
                    }
                }

                AnimatedVisibility(
                    visible = popupVisible,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .statusBarsPadding()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    enter = if (reduceMotion) fadeIn(tween(120))
                    else slideInVertically(tween(220)) { -it } + fadeIn(tween(180)),
                    exit = if (reduceMotion) fadeOut(tween(120))
                    else slideOutVertically(tween(180)) { -it } + fadeOut(tween(140)),
                ) {
                    popupMessage?.let { message ->
                        MessagePopup(
                            message = message,
                            title = vm.chats.firstOrNull { it.id == message.chatId }?.title ?: message.senderName,
                            colorHex = vm.chats.firstOrNull { it.id == message.chatId }?.avatarColor ?: "#3390EC",
                            onOpen = {
                                popupVisible = false
                                vm.openChat(message.chatId)
                            },
                            onDismiss = { popupVisible = false },
                        )
                    }
                }

                val toast = vm.toast
                LaunchedEffect(toast) {
                    if (toast != null) {
                        delay(2600)
                        vm.clearToast()
                    }
                }
                AnimatedVisibility(
                    visible = toast != null,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(bottom = 96.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color(0xE6202124))
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        Text(toast ?: "", color = Color.White, fontSize = 13.sp)
                    }
                }
            }
        }

        BackHandler(enabled = vm.backStack.size > 1) { vm.back() }
        }
    }
}

@Composable
private fun SplashScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFF4AA3F0), TelegramBlue))),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Send,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(64.dp),
            )
            Spacer(Modifier.height(14.dp))
            Text("Telegram", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(28.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                color = Color.White.copy(alpha = 0.85f),
                strokeWidth = 2.dp,
            )
        }
    }
}


@Composable
private fun MessagePopup(
    message: MessageDto,
    title: String,
    colorHex: String,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
) {
    val c = LocalTgColors.current
    val preview = when {
        message.deleted -> "消息已删除"
        message.poll != null -> "[投票] " + (message.poll?.question ?: "")
        message.media != null -> when (message.media?.kind) {
            "image" -> "[图片]"
            "video", "video_note" -> "[视频]"
            "voice" -> "[语音]"
            "sticker" -> "[贴纸]"
            "gif" -> "[GIF]"
            else -> "[文件] " + (message.media?.name ?: "")
        }
        else -> message.text.replace("\n", " ")
    }

    Card(
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = c.headerBg),
        elevation = CardDefaults.cardElevation(defaultElevation = 10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .pointerInput(Unit) {
                detectVerticalDragGestures { _, dragAmount ->
                    if (dragAmount < -6f) onDismiss()
                }
            }
            .clickable { onOpen() },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar(name = title, colorHex = colorHex, size = 40.dp)
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    color = c.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = preview,
                    color = c.textSecondary,
                    fontSize = 13.sp,
                    maxLines = 2,
                )
            }
            Spacer(Modifier.width(8.dp))
            Text(
                text = formatMessageTime(message.createdAt),
                color = c.textTertiary,
                fontSize = 11.sp,
            )
        }
    }
}
