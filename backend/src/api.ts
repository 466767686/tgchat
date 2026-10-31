import {
  DEFAULT_ITERATIONS,
  hashPassword,
  randomHex,
  sha256Hex,
  verifyPassword,
} from "./crypto";
import { broadcast } from "./hub";
import type { Env, PublicUser, UserRow } from "./types";
import { publicUser } from "./types";

const AVATAR_COLORS = ["#3390EC", "#E17076", "#7BC862", "#E5CA77", "#A695E7", "#EE7AAE", "#6EC9CB", "#FAA774"];

class ApiError extends Error {
  constructor(public status: number, message: string, public code = "error") {
    super(message);
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function ok(data: unknown = { ok: true }): Response {
  return json(data);
}

async function readBody(request: Request): Promise<Record<string, any>> {
  try {
    const body = await request.json();
    return body && typeof body === "object" ? (body as Record<string, any>) : {};
  } catch {
    return {};
  }
}

function text(value: unknown, field: string, min = 1, max = 4096): string {
  if (typeof value !== "string") throw new ApiError(400, `${field} is required`, "invalid_input");
  const trimmed = value.trim();
  if (trimmed.length < min) throw new ApiError(400, `${field} is too short`, "invalid_input");
  if (trimmed.length > max) throw new ApiError(400, `${field} is too long`, "invalid_input");
  return trimmed;
}

function username(value: unknown): string {
  const v = typeof value === "string" ? value.trim() : "";
  if (!/^[a-zA-Z0-9_.]{3,32}$/.test(v)) {
    throw new ApiError(400, "用户名需为 3-32 位字母、数字、下划线或点", "invalid_username");
  }
  return v;
}

function password(value: unknown): string {
  if (typeof value !== "string" || value.length < 6 || value.length > 128) {
    throw new ApiError(400, "密码长度需为 6-128 位", "invalid_password");
  }
  return value;
}

async function authenticate(request: Request, env: Env): Promise<UserRow> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) throw new ApiError(401, "缺少登录凭证", "unauthorized");
  const tokenHash = await sha256Hex(match[1]);
  const row = await env.DB.prepare(
    "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?",
  )
    .bind(tokenHash, Date.now())
    .first<UserRow>();
  if (!row) throw new ApiError(401, "登录已过期，请重新登录", "unauthorized");
  return row;
}

function requireAdmin(user: UserRow): void {
  if (user.role !== "admin") throw new ApiError(403, "需要管理员权限", "forbidden");
}

async function isMember(env: Env, chatId: string, userId: string): Promise<boolean> {
  const row = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
    .bind(chatId, userId)
    .first();
  return !!row;
}

async function assertMember(env: Env, chatId: string, userId: string): Promise<void> {
  if (!(await isMember(env, chatId, userId))) throw new ApiError(403, "你不是该会话的成员", "forbidden");
}

function mapMessage(row: any) {
  return {
    seq: row.seq,
    id: row.id,
    chatId: row.chat_id,
    senderId: row.sender_id,
    senderName: row.sender_name,
    senderColor: row.sender_color,
    text: row.text,
    createdAt: row.created_at,
    clientId: row.client_id ?? null,
  };
}

const MESSAGE_SELECT = `
  SELECT m.seq, m.id, m.chat_id, m.sender_id, m.text, m.created_at, m.client_id,
         u.display_name AS sender_name, u.avatar_color AS sender_color
  FROM messages m JOIN users u ON u.id = m.sender_id`;

async function loadChat(env: Env, chatId: string, viewerId: string) {
  const chat = await env.DB.prepare("SELECT * FROM chats WHERE id = ?").bind(chatId).first<any>();
  if (!chat) throw new ApiError(404, "会话不存在", "chat_not_found");
  const members = await env.DB.prepare(
    `SELECT u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at
     FROM chat_members m JOIN users u ON u.id = m.user_id WHERE m.chat_id = ? ORDER BY u.display_name`,
  )
    .bind(chatId)
    .all<any>();
  const last = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.chat_id = ? ORDER BY m.seq DESC LIMIT 1`)
    .bind(chatId)
    .first<any>();
  const me = await env.DB.prepare("SELECT last_read_seq FROM chat_members WHERE chat_id = ? AND user_id = ?")
    .bind(chatId, viewerId)
    .first<any>();
  const unread = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM messages WHERE chat_id = ? AND seq > ? AND sender_id != ?",
  )
    .bind(chatId, me?.last_read_seq ?? 0, viewerId)
    .first<any>();
  const otherRead = await env.DB.prepare(
    "SELECT MAX(last_read_seq) AS n FROM chat_members WHERE chat_id = ? AND user_id != ?",
  )
    .bind(chatId, viewerId)
    .first<any>();

  return {
    id: chat.id,
    type: chat.type,
    title: chat.title,
    createdAt: chat.created_at,
    lastReadSeq: me?.last_read_seq ?? 0,
    otherReadSeq: otherRead?.n ?? 0,
    unread: unread?.n ?? 0,
    lastMessage: last ? mapMessage(last) : null,
    members: members.results.map((m: any) => ({
      id: m.id,
      username: m.username,
      displayName: m.display_name,
      avatarColor: m.avatar_color,
      role: m.role,
      lastSeenAt: m.last_seen_at,
    })),
  };
}

async function createChat(
  env: Env,
  creatorId: string,
  memberIds: string[],
  type: "direct" | "group",
  title: string | null,
): Promise<string> {
  const id = crypto.randomUUID();
  const now = Date.now();
  const unique = [...new Set([creatorId, ...memberIds])];
  const stmts = [
    env.DB.prepare("INSERT INTO chats (id, type, title, created_at, created_by) VALUES (?, ?, ?, ?, ?)").bind(
      id,
      type,
      title,
      now,
      creatorId,
    ),
    ...unique.map((uid) =>
      env.DB.prepare("INSERT INTO chat_members (chat_id, user_id, joined_at, last_read_seq) VALUES (?, ?, ?, 0)").bind(
        id,
        uid,
        now,
      ),
    ),
  ];
  await env.DB.batch(stmts);
  return id;
}

export async function handleRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  path: string,
): Promise<Response> {
  const method = request.method.toUpperCase();
  const seg = path.split("/").filter(Boolean); // ["api", ...]

  // ---------------- health ----------------
  if (method === "GET" && path === "/api/health") {
    return json({ ok: true, service: "tgchat", time: new Date().toISOString() });
  }

  // ---------------- auth ----------------
  if (method === "POST" && path === "/api/auth/login") {
    const body = await readBody(request);
    const name = typeof body.username === "string" ? body.username.trim() : "";
    const pass = typeof body.password === "string" ? body.password : "";
    if (!name || !pass) throw new ApiError(400, "请输入用户名和密码", "invalid_input");

    const user = await env.DB.prepare("SELECT * FROM users WHERE username = ?").bind(name).first<UserRow>();
    if (!user || !(await verifyPassword(pass, user.password_hash))) {
      throw new ApiError(401, "用户名或密码错误", "bad_credentials");
    }

    const token = randomHex(32);
    const days = parseInt(env.SESSION_TTL_DAYS ?? "30", 10) || 30;
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?").bind(now),
      env.DB.prepare("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)").bind(
        await sha256Hex(token),
        user.id,
        now,
        now + days * 24 * 60 * 60 * 1000,
      ),
      env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(now, user.id),
    ]);

    return json({ token, user: publicUser(user) });
  }

  if (method === "POST" && path === "/api/auth/logout") {
    const me = await authenticate(request, env);
    const header = request.headers.get("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header.trim());
    if (match) {
      await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256Hex(match[1])).run();
    }
    return ok({ ok: true, userId: me.id });
  }

  // ---------------- me ----------------
  if (method === "GET" && path === "/api/me") {
    return json({ user: publicUser(await authenticate(request, env)) });
  }

  if (method === "PATCH" && path === "/api/me") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const displayName =
      typeof body.displayName === "string" && body.displayName.trim()
        ? text(body.displayName, "displayName", 1, 64)
        : me.display_name;
    const avatarColor =
      typeof body.avatarColor === "string" && /^#[0-9a-fA-F]{6}$/.test(body.avatarColor)
        ? body.avatarColor
        : me.avatar_color;
    await env.DB.prepare("UPDATE users SET display_name = ?, avatar_color = ? WHERE id = ?")
      .bind(displayName, avatarColor, me.id)
      .run();
    return json({ user: { ...publicUser(me), displayName, avatarColor } });
  }

  // ---------------- users directory ----------------
  if (method === "GET" && path === "/api/users") {
    const me = await authenticate(request, env);
    const q = new URL(request.url).searchParams.get("query")?.trim() ?? "";
    const like = `%${q}%`;
    const rows = await env.DB.prepare(
      `SELECT * FROM users WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
       ORDER BY display_name COLLATE NOCASE LIMIT 100`,
    )
      .bind(me.id, like, like)
      .all<UserRow>();
    return json({ users: rows.results.map(publicUser) });
  }

  // ---------------- chats ----------------
  if (method === "GET" && path === "/api/chats") {
    const me = await authenticate(request, env);
    ctx.waitUntil(env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(Date.now(), me.id).run());

    const rows = await env.DB.prepare(
      `SELECT c.id, c.type, c.title, c.created_at, cm.last_read_seq,
              (SELECT MAX(cm2.last_read_seq) FROM chat_members cm2 WHERE cm2.chat_id = c.id AND cm2.user_id != ?) AS other_read_seq,
              (SELECT COUNT(*) FROM messages m WHERE m.chat_id = c.id AND m.seq > cm.last_read_seq AND m.sender_id != ?) AS unread
       FROM chats c JOIN chat_members cm ON cm.chat_id = c.id
       WHERE cm.user_id = ?
       ORDER BY COALESCE((SELECT MAX(seq) FROM messages m WHERE m.chat_id = c.id), 0) DESC, c.created_at DESC`,
    )
      .bind(me.id, me.id, me.id)
      .all<any>();

    const ids = rows.results.map((r: any) => r.id);
    let membersByChat: Record<string, any[]> = {};
    if (ids.length > 0) {
      const placeholders = ids.map(() => "?").join(",");
      const members = await env.DB.prepare(
        `SELECT m.chat_id, u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at
         FROM chat_members m JOIN users u ON u.id = m.user_id
         WHERE m.chat_id IN (${placeholders}) ORDER BY u.display_name`,
      )
        .bind(...ids)
        .all<any>();
      for (const m of members.results) {
        (membersByChat[m.chat_id] ??= []).push({
          id: m.id,
          username: m.username,
          displayName: m.display_name,
          avatarColor: m.avatar_color,
          role: m.role,
          lastSeenAt: m.last_seen_at,
        });
      }
    }

    const lastMessages = await env.DB.prepare(
      `SELECT m.seq, m.id, m.chat_id, m.sender_id, m.text, m.created_at, m.client_id,
              u.display_name AS sender_name, u.avatar_color AS sender_color
       FROM messages m JOIN users u ON u.id = m.sender_id
       WHERE m.seq IN (SELECT MAX(seq) FROM messages WHERE chat_id IN (${
         ids.length ? ids.map(() => "?").join(",") : "''"
       }) GROUP BY chat_id)`,
    )
      .bind(...ids)
      .all<any>();

    const lastByChat: Record<string, any> = {};
    for (const m of lastMessages.results) lastByChat[m.chat_id] = mapMessage(m);

    const chats = rows.results.map((c: any) => ({
      id: c.id,
      type: c.type,
      title: c.title,
      createdAt: c.created_at,
      lastReadSeq: c.last_read_seq,
      otherReadSeq: c.other_read_seq ?? 0,
      unread: c.unread,
      lastMessage: lastByChat[c.id] ?? null,
      members: membersByChat[c.id] ?? [],
    }));

    return json({ chats });
  }

  if (method === "POST" && path === "/api/chats") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const memberIds: string[] = Array.isArray(body.memberIds)
      ? body.memberIds.filter((x: unknown) => typeof x === "string" && x)
      : [];
    if (memberIds.length === 0) throw new ApiError(400, "请选择至少一位联系人", "invalid_input");

    const ids = [...new Set(memberIds.filter((id) => id !== me.id))];
    if (ids.length === 0) throw new ApiError(400, "不能与自己创建会话", "invalid_input");
    const found = await env.DB.prepare(
      `SELECT id FROM users WHERE id IN (${ids.map(() => "?").join(",")})`,
    )
      .bind(...ids)
      .all<any>();
    if (found.results.length !== ids.length) throw new ApiError(400, "存在无效用户", "invalid_input");

    if (ids.length === 1) {
      const existing = await env.DB.prepare(
        `SELECT c.id FROM chats c
         JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
         JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
         WHERE c.type = 'direct' LIMIT 1`,
      )
        .bind(me.id, ids[0])
        .first<any>();
      if (existing) return json({ chat: await loadChat(env, existing.id, me.id), created: false });
      const chatId = await createChat(env, me.id, ids, "direct", null);
      return json({ chat: await loadChat(env, chatId, me.id), created: true }, 201);
    }

    const title = typeof body.title === "string" && body.title.trim() ? text(body.title, "title", 1, 64) : "群聊";
    const chatId = await createChat(env, me.id, ids, "group", title);
    return json({ chat: await loadChat(env, chatId, me.id), created: true }, 201);
  }

  // ---------------- single chat ----------------
  if (seg.length >= 4 && seg[0] === "api" && seg[1] === "chats") {
    const chatId = seg[2];

    if (method === "GET" && seg.length === 4 && seg[3] === "messages") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const url = new URL(request.url);
      const before = parseInt(url.searchParams.get("before") ?? "0", 10) || 0;
      const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") ?? "50", 10) || 50, 1), 100);
      const rows = await env.DB.prepare(
        `${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.seq < ? ORDER BY m.seq DESC LIMIT ?`,
      )
        .bind(chatId, before > 0 ? before : Number.MAX_SAFE_INTEGER, limit)
        .all<any>();
      const messages = rows.results.map(mapMessage).reverse();
      return json({ messages, hasMore: rows.results.length === limit });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "messages") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const content = text(body.text, "消息内容", 1, 4096);
      const clientId = typeof body.clientId === "string" ? body.clientId.slice(0, 64) : null;

      if (clientId) {
        const dup = await env.DB.prepare(
          `${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.sender_id = ? AND m.client_id = ? LIMIT 1`,
        )
          .bind(chatId, me.id, clientId)
          .first<any>();
        if (dup) return json({ message: mapMessage(dup), duplicate: true });
      }

      const id = crypto.randomUUID();
      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO messages (id, chat_id, sender_id, text, created_at, client_id) VALUES (?, ?, ?, ?, ?, ?)",
      )
        .bind(id, chatId, me.id, content, now, clientId)
        .run();
      const row = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.id = ?`).bind(id).first<any>();
      const message = mapMessage(row);
      await env.DB.prepare("UPDATE chat_members SET last_read_seq = MAX(last_read_seq, ?) WHERE chat_id = ? AND user_id = ?")
        .bind(message.seq, chatId, me.id)
        .run();

      await broadcast(env, ctx, chatId, { type: "message", chatId, message });
      return json({ message }, 201);
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "read") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const seq = Math.max(0, parseInt(String(body.seq ?? "0"), 10) || 0);
      await env.DB.prepare("UPDATE chat_members SET last_read_seq = MAX(last_read_seq, ?) WHERE chat_id = ? AND user_id = ?")
        .bind(seq, chatId, me.id)
        .run();
      await broadcast(env, ctx, chatId, { type: "read", chatId, userId: me.id, seq }, me.id);
      return ok({ ok: true, seq });
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "members") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const members = await env.DB.prepare(
        `SELECT u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at
         FROM chat_members m JOIN users u ON u.id = m.user_id WHERE m.chat_id = ?`,
      )
        .bind(chatId)
        .all<any>();
      return json({
        members: members.results.map((m: any) => ({
          id: m.id,
          username: m.username,
          displayName: m.display_name,
          avatarColor: m.avatar_color,
          role: m.role,
          lastSeenAt: m.last_seen_at,
        })),
      });
    }
  }

  // ---------------- admin ----------------
  if (seg[0] === "api" && seg[1] === "admin" && seg[2] === "users") {
    const me = await authenticate(request, env);
    requireAdmin(me);

    if (method === "GET" && seg.length === 3) {
      const rows = await env.DB.prepare("SELECT * FROM users ORDER BY created_at").all<UserRow>();
      return json({ users: rows.results.map(publicUser) });
    }

    if (method === "POST" && seg.length === 3) {
      const body = await readBody(request);
      const uname = username(body.username);
      const pass = password(body.password);
      const displayName =
        typeof body.displayName === "string" && body.displayName.trim()
          ? text(body.displayName, "displayName", 1, 64)
          : uname;
      const role = body.role === "admin" ? "admin" : "user";
      const color = AVATAR_COLORS[Math.floor(Math.random() * AVATAR_COLORS.length)];
      const iterations = parseInt(env.PBKDF2_ITERATIONS ?? "0", 10) || DEFAULT_ITERATIONS;

      const exists = await env.DB.prepare("SELECT 1 AS x FROM users WHERE username = ?").bind(uname).first();
      if (exists) throw new ApiError(409, "用户名已存在", "username_taken");

      const id = crypto.randomUUID();
      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO users (id, username, password_hash, display_name, avatar_color, role, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)",
      )
        .bind(id, uname, await hashPassword(pass, iterations), displayName, color, role, now)
        .run();

      const created = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();

      // Give the new account a direct chat with the admin who created it,
      // so both sides see something useful right after first login.
      let chatId: string | null = null;
      if (body.withAdminChat !== false && id !== me.id) {
        const existing = await env.DB.prepare(
          `SELECT c.id FROM chats c
           JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
           JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
           WHERE c.type = 'direct' LIMIT 1`,
        )
          .bind(me.id, id)
          .first<any>();
        chatId = existing?.id ?? (await createChat(env, me.id, [id], "direct", null));
      }

      return json({ user: publicUser(created!), chatId }, 201);
    }

    if (method === "POST" && seg.length === 5 && seg[4] === "reset-password") {
      const body = await readBody(request);
      const targetId = seg[3];
      const pass = password(body.password);
      const target = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(targetId).first<UserRow>();
      if (!target) throw new ApiError(404, "用户不存在", "not_found");
      const iterations = parseInt(env.PBKDF2_ITERATIONS ?? "0", 10) || DEFAULT_ITERATIONS;
      await env.DB.batch([
        env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?").bind(await hashPassword(pass, iterations), targetId),
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(targetId),
      ]);
      return ok({ ok: true });
    }
  }

  throw new ApiError(404, `No route for ${method} ${path}`, "not_found");
}

export { ApiError };
