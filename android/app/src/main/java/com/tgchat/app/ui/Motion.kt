package com.tgchat.app.ui

import android.animation.ValueAnimator
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext

/**
 * Android 端统一动效参数。与 iOS `Motion.swift` 保持同一套语义：
 * 页面不自行写死时长，Reduce Motion 时统一退化为短淡入。
 */
object MotionTokens {
    val quick: FiniteAnimationSpec<Float> = spring(dampingRatio = 0.86f, stiffness = 520f)
    val standard: FiniteAnimationSpec<Float> = spring(dampingRatio = 0.87f, stiffness = 320f)
    val gentle: FiniteAnimationSpec<Float> = spring(dampingRatio = 0.90f, stiffness = 190f)
    val fade: FiniteAnimationSpec<Float> = tween(durationMillis = 150)
}

val LocalReduceMotion = staticCompositionLocalOf { false }

/**
 * 读取系统「移除动画 / 动画时长缩放为 0」设置，并监听变化。
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    var enabled by remember {
        mutableStateOf(!ValueAnimator.areAnimatorsEnabled() || animatorScale(context) == 0f)
    }

    DisposableEffect(context) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                enabled = !ValueAnimator.areAnimatorsEnabled() || animatorScale(context) == 0f
            }
        }
        context.contentResolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            observer,
        )
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }

    return enabled
}

private fun animatorScale(context: android.content.Context): Float =
    runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
    }.getOrDefault(1f)

/**
 * 按压反馈：轻微缩放 + 透明度。Reduce Motion 时只保留透明度。
 */
@Composable
fun Modifier.motionPress(
    interaction: MutableInteractionSource,
    reduceMotion: Boolean,
    pressedScale: Float = 0.97f,
): Modifier {
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) pressedScale else 1f,
        animationSpec = MotionTokens.quick,
        label = "press-scale",
    )
    val alpha by animateFloatAsState(
        targetValue = if (pressed) 0.92f else 1f,
        animationSpec = MotionTokens.fade,
        label = "press-alpha",
    )
    return this.graphicsLayer {
        scaleX = scale
        scaleY = scale
        this.alpha = alpha
    }
}
