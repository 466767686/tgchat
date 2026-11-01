package com.tgchat.app.push

import com.tgchat.app.data.MessageDto
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * 前台收到的消息事件。RealtimeService 在 App 可见时把消息投递到这里，
 * Compose 层据此弹出 QQ 风格横幅并播放提示音。
 */
object IncomingCenter {
    private val _events = MutableSharedFlow<MessageDto>(extraBufferCapacity = 16)
    val events: SharedFlow<MessageDto> = _events

    fun publish(message: MessageDto) {
        _events.tryEmit(message)
    }
}
