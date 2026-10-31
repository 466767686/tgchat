package com.tgchat.app.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.sessionDataStore by preferencesDataStore(name = "tgchat_session")

data class StoredSession(
    val token: String? = null,
    val userJson: String? = null,
    val baseUrl: String? = null,
    val theme: String = "system",
    val disguise: Boolean = true,
    val unlockPin: String = "1234",
)

class SessionStore(private val context: Context) {

    private object Keys {
        val token = stringPreferencesKey("token")
        val user = stringPreferencesKey("user_json")
        val baseUrl = stringPreferencesKey("base_url")
        val theme = stringPreferencesKey("theme")
        val disguise = booleanPreferencesKey("disguise")
        val unlockPin = stringPreferencesKey("unlock_pin")
    }

    val session: Flow<StoredSession> = context.sessionDataStore.data.map { prefs ->
        StoredSession(
            token = prefs[Keys.token],
            userJson = prefs[Keys.user],
            baseUrl = prefs[Keys.baseUrl],
            theme = prefs[Keys.theme] ?: "system",
            disguise = prefs[Keys.disguise] ?: true,
            unlockPin = prefs[Keys.unlockPin] ?: "1234",
        )
    }

    suspend fun saveSession(token: String, userJson: String) {
        context.sessionDataStore.edit {
            it[Keys.token] = token
            it[Keys.user] = userJson
        }
    }

    suspend fun saveBaseUrl(url: String) {
        context.sessionDataStore.edit { it[Keys.baseUrl] = url }
    }

    suspend fun saveTheme(mode: String) {
        context.sessionDataStore.edit { it[Keys.theme] = mode }
    }

    suspend fun saveDisguise(enabled: Boolean) {
        context.sessionDataStore.edit { it[Keys.disguise] = enabled }
    }

    suspend fun saveUnlockPin(pin: String) {
        context.sessionDataStore.edit { it[Keys.unlockPin] = pin }
    }

    suspend fun clearSession() {
        context.sessionDataStore.edit {
            it.remove(Keys.token)
            it.remove(Keys.user)
        }
    }
}
