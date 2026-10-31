package com.tgchat.app.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Talks to a locally running backend (see backend/scripts/local-dev.mjs) through
 * the same ApiClient the app uses, so request/response serialization is covered.
 *
 * The test is skipped automatically when nothing is listening on 127.0.0.1:8787.
 */
class ApiClientTest {

    private val base = "http://127.0.0.1:8787"

    private fun serverUp(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", 8787), 500) }
        true
    } catch (_: Exception) {
        false
    }

    @Test
    fun loginSendAndReceive() = runBlocking {
        assumeTrue("local backend is not running", serverUp())

        val admin = ApiClient(base)
        val adminLogin = admin.login("admin", "admin12345")
        assertTrue("token should not be blank", adminLogin.token.isNotBlank())
        admin.token = adminLogin.token

        val suffix = System.currentTimeMillis().toString(36).takeLast(6)
        val username = "junit_$suffix"
        val created = admin.adminCreateUser(username, "junit12345", "JUnit User", "user")
        assertEquals(username, created.user.username)

        val user = ApiClient(base)
        val userLogin = user.login(username, "junit12345")
        user.token = userLogin.token
        assertEquals(created.user.id, userLogin.user.id)

        val chats = user.chats().chats
        val chat = chats.firstOrNull { it.members.any { member -> member.id != userLogin.user.id } }
        assertTrue("new account should get a chat with the admin", chat != null)

        val text = "junit message ${'$'}suffix"
        val clientId = "junit-${'$'}suffix"
        val sent = user.sendMessage(chat!!.id, text, clientId)
        assertTrue(sent.message.seq > 0)

        val duplicate = user.sendMessage(chat.id, text, clientId)
        assertTrue("same clientId must be idempotent", duplicate.duplicate)
        assertEquals(sent.message.seq, duplicate.message.seq)

        val history = admin.messages(chat.id, 0, 50)
        assertTrue(history.messages.any { it.seq == sent.message.seq && it.text == text })

        admin.markRead(chat.id, sent.message.seq)
        val refreshed = admin.chats().chats.first { it.id == chat.id }
        assertEquals(0, refreshed.unread)
        assertTrue(refreshed.otherReadSeq >= sent.message.seq)
    }

    @Test
    fun loginRejectsWrongPassword() = runBlocking {
        assumeTrue("local backend is not running", serverUp())
        val client = ApiClient(base)
        val error = runCatching { client.login("admin", "wrong-password") }.exceptionOrNull()
        assertTrue("expected ApiException", error is ApiException)
        assertEquals(401, (error as ApiException).status)
    }
}
