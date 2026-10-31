import { ApiError, handleRequest } from "./api";
import { ChatHub } from "./hub";
import { sha256Hex } from "./crypto";
import type { Env, UserRow } from "./types";

export { ChatHub };

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,PATCH,DELETE,OPTIONS",
  "access-control-allow-headers": "authorization,content-type",
  "access-control-max-age": "86400",
};

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(response.body, { status: response.status, headers });
}

function errorResponse(status: number, message: string, code = "error"): Response {
  return withCors(
    new Response(JSON.stringify({ error: message, code }), {
      status,
      headers: { "content-type": "application/json; charset=utf-8" },
    }),
  );
}

async function sessionUser(env: Env, token: string): Promise<UserRow | null> {
  const tokenHash = await sha256Hex(token);
  return env.DB.prepare(
    "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?",
  )
    .bind(tokenHash, Date.now())
    .first<UserRow>();
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }

    if (path === "/api/ws") {
      const upgrade = request.headers.get("Upgrade");
      if (!upgrade || upgrade.toLowerCase() !== "websocket") {
        return errorResponse(426, "Expected WebSocket upgrade", "upgrade_required");
      }
      const token = url.searchParams.get("token") ?? "";
      const chatId = url.searchParams.get("chat") ?? "";
      if (!token || !chatId) return errorResponse(401, "缺少 token 或 chat 参数", "unauthorized");

      const user = await sessionUser(env, token);
      if (!user) return errorResponse(401, "登录已过期，请重新登录", "unauthorized");

      const member = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
        .bind(chatId, user.id)
        .first();
      if (!member) return errorResponse(403, "你不是该会话的成员", "forbidden");

      const stub = env.CHAT_HUB.get(env.CHAT_HUB.idFromName(chatId));
      const headers = new Headers(request.headers);
      headers.set("x-user-id", user.id);
      headers.set("x-user-name", user.display_name);
      headers.set("x-user-color", user.avatar_color);
      headers.set("x-chat-id", chatId);
      return stub.fetch(new Request("https://hub/ws", { headers, method: "GET" }));
    }

    if (path === "/" || path === "/api") {
      return withCors(
        Response.json({
          service: "tgchat",
          ok: true,
          endpoints: [
            "POST /api/auth/login",
            "POST /api/auth/logout",
            "GET  /api/me",
            "GET  /api/users",
            "GET  /api/chats",
            "POST /api/chats",
            "GET  /api/chats/:id/messages",
            "POST /api/chats/:id/messages",
            "POST /api/chats/:id/read",
            "GET  /api/ws?chat=:id&token=:token",
          ],
        }),
      );
    }

    try {
      return withCors(await handleRequest(request, env, ctx, path));
    } catch (err) {
      if (err instanceof ApiError) {
        return errorResponse(err.status, err.message, err.code);
      }
      console.error("unhandled error", err);
      return errorResponse(500, "服务器内部错误", "internal");
    }
  },
};
