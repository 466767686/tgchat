package com.tgchat.app.push

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import com.tgchat.app.R

/**
 * 极轻量的提示音播放器。SoundPool 只加载一次，重复消息不会卡顿。
 */
object MessageSound {
    private var pool: SoundPool? = null
    private var soundId = 0
    private var loaded = false

    fun play(context: Context) {
        if (!AppSettings.soundEnabled(context)) return

        val soundPool = pool ?: SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
            .also { pool = it }

        if (!loaded) {
            soundId = soundPool.load(context.applicationContext, R.raw.message_ding, 1)
            soundPool.setOnLoadCompleteListener { _, _, status ->
                if (status == 0) loaded = true
            }
            return
        }

        runCatching { soundPool.play(soundId, 0.9f, 0.9f, 1, 0, 1f) }
    }
}
