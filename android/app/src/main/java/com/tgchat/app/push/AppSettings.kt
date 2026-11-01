package com.tgchat.app.push

import android.content.Context

/**
 * 轻量同步开关：通知服务（后台）和 Compose 界面都会读取。
 */
object AppSettings {
    private const val PREFS = "yuejian_settings"
    private const val KEY_POPUP = "inapp_popup"
    private const val KEY_SOUND = "message_sound"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun popupEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_POPUP, true)

    fun setPopupEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_POPUP, enabled).apply()
    }

    fun soundEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_SOUND, true)

    fun setSoundEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_SOUND, enabled).apply()
    }
}
