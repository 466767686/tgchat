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
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import com.tgchat.app.push.RealtimeService
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.tgchat.app.ui.screens.AdminScreen
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
        val view = LocalView.current
        val context = LocalContext.current
        SideEffect {
            if (!view.isInEditMode) {
                context.findActivity()?.let { activity ->
                    WindowCompat.getInsetsController(activity.window, view).isAppearanceLightStatusBars = !dark
                    WindowCompat.getInsetsController(activity.window, view).isAppearanceLightNavigationBars = !dark
                }
            }
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
        LaunchedEffect(vm.token, vm.chats) {
            val pending = PendingNavigation.chatId
            if (pending != null && vm.token != null && vm.chats.any { it.id == pending }) {
                PendingNavigation.chatId = null
                vm.openChat(pending)
            }
        }

        Surface(modifier = Modifier.fillMaxSize(), color = LocalTgColors.current.background) {
            Box(modifier = Modifier.fillMaxSize()) {
                AnimatedContent(
                    targetState = vm.route,
                    transitionSpec = {
                        (fadeIn(tween(180)) + slideInHorizontally(tween(220)) { it / 14 }) togetherWith
                            (fadeOut(tween(140)) + slideOutHorizontally(tween(200)) { -it / 20 })
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
